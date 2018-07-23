export RecoWindow, RecoWidget

import Base: getindex

function linearSolverList()
  Any["kaczmarz", "cgnr", "fusedlasso"]
end

function RecoWindow(filenameMeas=nothing; params = defaultRecoParams())
  w = Window("Reconstruction",800,600)
  dw = RecoWidget(filenameMeas, params=params)
  push!(w,dw)

  G_.transient_for(w, mpilab["mainWindow"])
  G_.modal(w,true)
  showall(w)

  dw
end

type RecoWidget<: Gtk.GtkGrid
  handle::Ptr{Gtk.GObject}
  builder
  dv
  bMeas
  sysMatrix
  sfParamsChanged
  bSF
  freq
  recoResult
  bEmpty
  selectedSF
  bgExperiments
  recoGrid
end

getindex(m::RecoWidget, w::AbstractString) = G_.object(m.builder, w)

function RecoWidget(filenameMeas=nothing; params = defaultRecoParams())

  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","reconstructionWidget.ui")

  b = Builder(filename=uifile)
  mainGrid = G_.object(b, "gridReco")
  m = RecoWidget( mainGrid.handle, b,
                  nothing,
                  nothing,
                  nothing, true,
                  nothing, nothing, nothing, nothing, 1,
                  Dict{Int64,String}(),nothing)
  Gtk.gobject_move_ref(m, mainGrid)

  spReco = m["spReco"]
  setParams(m, params)

  m.dv = DataViewerWidget()
  push!(m["boxDW"], m.dv)
  setproperty!(m["boxDW"], :fill, m.dv, true)
  setproperty!(m["boxDW"], :expand, m.dv, true)

  #if filenameMeas != nothing
  #  G_.title(m["recoWindow"], string("Reconstruction: ", filenameMeas))
  #end

  updateData!(m, filenameMeas)

  choices = linearSolverList()
  for c in choices
    push!(m["cbSolver"], c)
  end
  setproperty!(m["cbSolver"],:active,0)

  choices = linearOperatorList()
  for c in choices
    push!(m["cbSparsityTrafo"], c)
  end
  setproperty!(m["cbSparsityTrafo"],:active,0)


  setproperty!(m["entSF"],:editable,false)
  setproperty!(m["entNumFreq"],:editable,false)

  initBGSubtractionWidgets(m)

  println(mpilab.settings)

  function performMultiProcessReco( widget )
    println("Num Procs: $(procs())")
    recoWorkers = workers()
    println("Num Workers: $(recoWorkers)")
    nWorkers = length(recoWorkers)
    start(spReco)
    params = getParams(m)

    if m.sfParamsChanged
      updateSF(m)
    end

    if params[:emptyMeasPath] != nothing
      params[:bEmpty] = MPIFile( params[:emptyMeasPath] )
    end
    bSF=m.bSF
    bMeas=m.bMeas
    freq=m.freq

    recoTasks = Vector{Task}(nWorkers)
    recoResults = Vector{ImageMetadata.ImageMeta}(nWorkers)

    splittedFrames = splittingFrames(params, nWorkers)

    @Gtk.sigatom begin
      @async begin
        for p=1:nWorkers
          recoTasks[p] = @async begin
              println("Entering recoTask...")
              taskParams = copy(params)
              taskParams[:frames] = splittedFrames[p]
              recoResult = remotecall_fetch(multiCoreReconstruction, recoWorkers[p], bSF, bMeas, freq, taskParams )
              recoResults[p] = recoResult
              println("Finished recoTask.")
          end # recoTasks[p]
        end # for
        for k=1:nWorkers
          wait(recoTasks[k])
        end
        res = reductionRecoResults(recoResults)
        m.recoResult = res
        m.recoResult["recoParams"] = getParams(m)
        Gtk.@sigatom updateData!(m.dv, m.recoResult )
        stop(spReco)
        println("reco processes finished.")
      end # async
    end # Gtk.sigatom
  end #Function

  function updateSFParamsChanged( widget )
    m.sfParamsChanged = true
  end

  function selectSF( widget )
    dlg = SFSelectionDialog( gradient=sfGradient(m.bMeas)[3], driveField=dfStrength(m.bMeas)  )

    ret = run(dlg)
    if ret == GtkResponseType.ACCEPT

      if hasselection(dlg.selection)
        sffilename =  getSelectedSF(dlg)

        println(sffilename)
        setSF(m, sffilename )
      end


    end
    destroy(dlg)
  end

  function saveReco( widget )
    if m.recoResult != nothing
      m.recoResult["recoParams"][:description] = getproperty(m["entRecoDescrip"], :text, String)
      Gtk.@sigatom addReco(mpilab, m.recoResult)
    end

  end


  function updateBGMeas( widget )
    if getproperty(m["cbBGMeasurements"],"active", Int) >= 0

      bgstr =  Gtk.bytestring( G_.active_text(m["cbBGMeasurements"]))
      if !isempty(bgstr)
        bgnum =  parse(Int64, bgstr)
        filenameBG = m.bgExperiments[bgnum]
        println(filenameBG)
        if isdir(filenameBG) || isfile(filenameBG)
          m.bEmpty = MPIFile(filenameBG)

          setproperty!(m["adjFirstFrameBG"],:upper, numScans(m.bEmpty))
          setproperty!(m["adjLastFrameBG"],:upper, numScans(m.bEmpty))
        end
      end
    end
  end


  function loadRecoProfile( widget )

    cache = loadcache()

    selectedProfileName = Gtk.bytestring( G_.active_text(m["cbRecoProfiles"]))
    println(selectedProfileName)
    if haskey(cache["recoParams"],selectedProfileName)
      Gtk.@sigatom setParams(m, cache["recoParams"][selectedProfileName])
    end

  end
  signalId_cbRecoProfiles = signal_connect(loadRecoProfile, m["cbRecoProfiles"], "changed")

  function saveRecoParams( widget )
    currentRecoParams = getParams(m)
    key = getproperty(m["entRecoParamsName"], :text, String)

    cache = loadcache()
    cache["recoParams"][key] = currentRecoParams
    savecache(cache)

    Gtk.@sigatom updateRecoProfiles()
  end

  function deleteRecoProfile( widget )
    selectedProfileName = Gtk.bytestring( G_.active_text(m["cbRecoProfiles"]))

    Gtk.@sigatom println("delete reco profile ", selectedProfileName)

    cache = loadcache()
    delete!(cache["recoParams"], selectedProfileName)
    savecache(cache)

    Gtk.@sigatom updateRecoProfiles()
  end

  function updateRecoProfiles()
    signal_handler_block(m["cbRecoProfiles"], signalId_cbRecoProfiles)

    cache = loadcache()

    empty!(m["cbRecoProfiles"])
    for key in keys(cache["recoParams"])
      push!(m["cbRecoProfiles"], key)
    end
    setproperty!(m["cbRecoProfiles"],:active,0)
    signal_handler_unblock(m["cbRecoProfiles"], signalId_cbRecoProfiles)
  end

  updateRecoProfiles()


  signal_connect(performReco, m["tbPerformReco"], "clicked", Void, (), false, m)
  signal_connect(performMultiProcessReco, m["tbPerformMultipleProcess"], "clicked")
  signal_connect(saveReco, m["tbSaveReco"], "clicked")
  signal_connect(saveRecoParams, m["btSaveRecoParams"], "clicked")
  signal_connect(deleteRecoProfile, m["btDeleteRecoProfile"], "clicked")
  signal_connect(updateSFParamsChanged, m["adjMinFreq"], "value_changed")
  signal_connect(updateSFParamsChanged, m["adjMaxFreq"], "value_changed")
  signal_connect(updateSFParamsChanged, m["adjSNRThresh"], "value_changed")
  signal_connect(updateSFParamsChanged, m["cbLoadAsReal"], "toggled")
  signal_connect(updateSFParamsChanged, m["cbSolver"], "changed")
  signal_connect(updateBGMeas, m["cbBGMeasurements"], "changed")
  signal_connect(updateSFParamsChanged, m["cbSubtractBG"], "toggled")
  signal_connect(updateSFParamsChanged, m["cbRecX"], "toggled")
  signal_connect(updateSFParamsChanged, m["cbRecY"], "toggled")
  signal_connect(updateSFParamsChanged, m["cbRecZ"], "toggled")
  signal_connect(updateSFParamsChanged, m["cbMatrixCompression"], "toggled")
  signal_connect(updateSFParamsChanged, m["adjRedFactor"], "value_changed")
  signal_connect(updateSFParamsChanged, m["cbSparsityTrafo"], "changed")
  signal_connect(updateBGMeas, m["cbSubtractBG"], "toggled")


  signal_connect(m["adjNumSF"], "value_changed") do widget
    tmpbSF = copy(m.bSF)
    resize!(m.bSF, getproperty(m["adjNumSF"],:value,Int64) )
    if length(m.bSF) > length(tmpbSF)
      for i=(length(tmpbSF)+1):length(m.bSF)
        m.bSF[i] = BrukerFile()
      end
    end

    Gtk.@sigatom setproperty!(m["adjSelectedSF"], :upper, length(m.bSF))
  end

  signal_connect(m["adjSelectedSF"], "value_changed") do widget
    println(m.bSF)

    m.selectedSF = getproperty(m["adjSelectedSF"],:value,Int64)

    txt = m.bSF[m.selectedSF].path
    setproperty!(m["entSF"], :text, txt)
  end

  signal_connect(selectSF, m["btBrowseSF"], "clicked")

  return m
end

function initBGSubtractionWidgets(m::RecoWidget)

  if mpilab.currentStudy != nothing
    empty!(m["cbBGMeasurements"])
    empty!(m.bgExperiments)

    experiments = getExperiments( activeDatasetStore(mpilab), mpilab.currentStudy)

    idxFG = 0

    for (i,exp) in enumerate(experiments)

      m.bgExperiments[exp.num] = exp.path
      push!(m["cbBGMeasurements"], string(exp.num))

      if filepath(m.bMeas) == exp.path
        idxFG = i-1
      end
    end

    Gtk.@sigatom setproperty!(m["cbBGMeasurements"],:active, idxFG)
  end
end

function setSF(m::RecoWidget, filename)

  m.bSF[m.selectedSF] = MPIFile( filename )

  setproperty!(m["entSF"], :text, filename)
  setproperty!(m["adjMinFreq"],:upper,bandwidth(m.bSF[m.selectedSF]) / 1000)
  setproperty!(m["adjMaxFreq"],:upper,bandwidth(m.bSF[m.selectedSF]) / 1000)

  m.sfParamsChanged = true
  nothing
end

function updateData!(m::RecoWidget, filenameMeas, params)
  setParams(m, params)
  updateData!(m, filenameMeas)
end

function updateData!(m::RecoWidget, filenameMeas)
  if filenameMeas != nothing
    m.bMeas = MPIFile(filenameMeas)
    setproperty!(m["adjFrame"],:upper, numScans(m.bMeas))
    setproperty!(m["adjLastFrame"],:upper, numScans(m.bMeas))
    try
      if m.bSF[1].path=="" && isdir( sfPath(m.bMeas) )
        setSF(m, sfPath(m.bMeas)  )
      elseif isdir( m.bSF[1].path )
        setSF(m, m.bSF[1].path )
      end
    catch

    end
    initBGSubtractionWidgets(m)
  end
  nothing
end

function updateSF(m::RecoWidget)
  params = getParams(m)

  bgcorrection = getproperty(m["cbSubtractBG"], :active, Bool)

  m.freq = filterFrequencies(m.bSF, minFreq=params[:minFreq], maxFreq=params[:maxFreq],
                             SNRThresh=params[:SNRThresh], recChannels=params[:recChannels])

  Gtk.@sigatom setproperty!(m["entNumFreq"], :text, string(length(m.freq)))

    #TODO

#     redFactor = getproperty(adjRedFac, :value, Float64)
#     if getproperty(cbSparseReco, :active, Bool)
#       S = getSF(m.bSF, freq, redFactor=redFactor, sparseTrafo="DCT")
#     else

  println("Reloading SF")
  m.sysMatrix, m.recoGrid = getSF(m.bSF, m.freq, params[:sparseTrafo], params[:solver], bgcorrection=bgcorrection,
                      loadasreal = params[:loadasreal], loadas32bit = params[:loadas32bit],
                      redFactor = params[:redFactor])

  m.sfParamsChanged = false
end

function performReco(widgetptr::Ptr, m::RecoWidget)
  params = getParams(m)

  if m.sfParamsChanged
    updateSF(m)
  end


  if params[:emptyMeasPath] != nothing
    params[:bEmpty] = MPIFile( params[:emptyMeasPath] )
  end

  conc = reconstruction(m.sysMatrix, m.bSF, m.bMeas, m.freq, m.recoGrid; params...)

  m.recoResult = conc
  m.recoResult["recoParams"] = getParams(m)
  Gtk.@sigatom updateData!(m.dv, m.recoResult )
  nothing
end

function getParams(m::RecoWidget)
  params = defaultRecoParams()
  params[:lambd] = getproperty(m["adjLambdaL2"], :value, Float64)
  params[:lambdaL1] = getproperty(m["adjLambdaL1"], :value, Float64)
  params[:lambdaTV] = getproperty(m["adjLambdaTV"], :value, Float64)
  params[:iterations] = getproperty(m["adjIterations"], :value, Int64)
  params[:SNRThresh] = getproperty(m["adjSNRThresh"], :value, Float64)
  params[:minFreq] = getproperty(m["adjMinFreq"], :value, Float64) * 1000
  params[:maxFreq] = getproperty(m["adjMaxFreq"], :value, Float64) * 1000
  params[:nAverages] = getproperty(m["adjAverages"], :value, Int64)
  params[:spectralCleaning] = getproperty(m["cbSpectralCleaning"], :active, Bool)
  params[:loadasreal] = getproperty(m["cbLoadAsReal"], :active, Bool)
  params[:solver] = linearSolverList()[max(getproperty(m["cbSolver"],:active, Int64) + 1,1)]
  # Small hack
  if params[:solver] == "fusedlasso"
    params[:loadasreal] = true
  end

  firstFrame = getproperty(m["adjFrame"], :value, Int64)
  lastFrame = getproperty(m["adjLastFrame"], :value, Int64)
  if firstFrame > lastFrame
    lastFrame = firstFrame
    Gtk.@sigatom setproperty!(m["adjLastFrame"], :value, lastFrame)
  end
  frames = firstFrame:lastFrame
  params[:frames] = frames


  bgcorrection = getproperty(m["cbSubtractBG"], :active, Bool)
  params[:emptyMeasPath] = bgcorrection ? filepath(m.bEmpty) : nothing

  if bgcorrection
    firstFrameBG = getproperty(m["adjFirstFrameBG"], :value, Int64)
    lastFrameBG = getproperty(m["adjLastFrameBG"], :value, Int64)
    framesBG = firstFrameBG:lastFrameBG
    params[:bgFrames] = framesBG
  else
    params[:bgFrames] = nothing
  end

  params[:description] = getproperty(m["entRecoDescrip"], :text, String)

  params[:recChannels] = Int64[]
  if getproperty(m["cbRecX"], :active, Bool)
    push!(params[:recChannels],1)
  end
  if getproperty(m["cbRecY"], :active, Bool)
    push!(params[:recChannels],2)
  end
  if getproperty(m["cbRecZ"], :active, Bool)
    push!(params[:recChannels],3)
  end

  matrixCompression = getproperty(m["cbMatrixCompression"], :active, Bool)
  params[:sparseTrafo] = matrixCompression ?
           linearOperatorList()[max(getproperty(m["cbSparsityTrafo"],:active, Int64) + 1,1)] : nothing

  params[:redFactor] = getproperty(m["adjRedFactor"], :value, Float64)

  params[:SFPath] = String[ filepath(b) for b in m.bSF]

  return params
end

function setParams(m::RecoWidget, params)
  Gtk.@sigatom setproperty!(m["adjLambdaL2"], :value, params[:lambd])
  Gtk.@sigatom setproperty!(m["adjLambdaL1"], :value, get(params,:lambdaL1,0.0))
  Gtk.@sigatom setproperty!(m["adjLambdaTV"], :value, get(params,:lambdaTV,0.0))
  Gtk.@sigatom setproperty!(m["adjIterations"], :value, params[:iterations])
  Gtk.@sigatom setproperty!(m["adjSNRThresh"], :value, params[:SNRThresh])
  Gtk.@sigatom setproperty!(m["adjMinFreq"], :value, params[:minFreq] / 1000)
  Gtk.@sigatom setproperty!(m["adjMaxFreq"], :value, params[:maxFreq] / 1000)
  Gtk.@sigatom setproperty!(m["adjAverages"], :value, params[:nAverages])
  Gtk.@sigatom setproperty!(m["adjFrame"], :value, first(params[:frames]))
  Gtk.@sigatom setproperty!(m["adjLastFrame"], :value, last(params[:frames]))
  Gtk.@sigatom setproperty!(m["cbSpectralCleaning"], :active, params[:spectralCleaning])
  Gtk.@sigatom setproperty!(m["cbLoadAsReal"], :active, params[:loadasreal])
  Gtk.@sigatom setproperty!(m["adjRedFactor"], :value, get(params,:redFactor,0.01))

  for (i,solver) in enumerate(linearSolverList())
    if solver == params[:solver]
      Gtk.@sigatom setproperty!(m["cbSolver"],:active, i-1)
    end
  end

  sparseTrafo = get(params, :sparseTrafo, nothing)
  Gtk.@sigatom setproperty!(m["cbMatrixCompression"], :active,
                       sparseTrafo != nothing)
  if sparseTrafo != nothing
    for (i,trafo) in enumerate(linearOperatorList())
      if trafo == sparseTrafo
        Gtk.@sigatom setproperty!(m["cbSparsityTrafo"],:active, i-1)
      end
    end
  end

  setproperty!(m["cbRecX"], :active, in(1,params[:recChannels]))
  setproperty!(m["cbRecY"], :active, in(2,params[:recChannels]))
  setproperty!(m["cbRecZ"], :active, in(3,params[:recChannels]))

  Gtk.@sigatom setproperty!(m["entRecoDescrip"], :text, get(params, :description,""))


  if haskey(params, :SFPath)
    if typeof(params[:SFPath]) <: AbstractString
      params[:SFPath] = String[params[:SFPath]]
    end
    numSF = length(params[:SFPath])
    Gtk.@sigatom setproperty!(m["adjNumSF"], :value, numSF)
    m.bSF = MPIFile(params[:SFPath])
  else
    Gtk.@sigatom setproperty!(m["adjNumSF"], :value, 1)
    m.bSF = MPIFile[BrukerFile()]
  end

end
