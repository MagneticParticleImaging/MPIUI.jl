export RecoWindow, RecoWidget

import Base: getindex

function linearSolverList()
  Any["kaczmarz", "cgnr", "fusedlasso"]
end

function RecoWindow(filenameMeas=nothing; params = defaultRecoParams())
  w = Window("Reconstruction",800,600)
  dw = RecoWidget(filenameMeas, params=params)
  push!(w,dw)

  G_.transient_for(w, mpilab[]["mainWindow"])
  G_.modal(w,true)
  showall(w)

  dw
end

mutable struct RecoWidget<: Gtk.GtkGrid
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
  currentStudy
  currentExperiment
end

getindex(m::RecoWidget, w::AbstractString) = G_.object(m.builder, w)

function RecoWidget(filenameMeas=nothing; params = defaultRecoParams())

  uifile = joinpath(@__DIR__,"builder","reconstructionWidget.ui")

  b = Builder(filename=uifile)
  mainGrid = G_.object(b, "gridReco")
  m = RecoWidget( mainGrid.handle, b,
                  nothing,
                  nothing,
                  nothing, true,
                  nothing, nothing, nothing, nothing, 1,
                  Dict{Int64,String}(),nothing,
                  nothing, nothing)
  Gtk.gobject_move_ref(m, mainGrid)

  spReco = m["spReco"]
  setParams(m, params)

  m.dv = DataViewerWidget()
  push!(m["boxDW"], m.dv)
  set_gtk_property!(m["boxDW"], :fill, m.dv, true)
  set_gtk_property!(m["boxDW"], :expand, m.dv, true)

  #if filenameMeas != nothing
  #  G_.title(m["recoWindow"], string("Reconstruction: ", filenameMeas))
  #end

  updateData!(m, filenameMeas)

  choices = linearSolverList()
  for c in choices
    push!(m["cbSolver"], c)
  end
  set_gtk_property!(m["cbSolver"],:active,0)

  choices = linearOperatorList()
  for c in choices
    push!(m["cbSparsityTrafo"], c)
  end
  set_gtk_property!(m["cbSparsityTrafo"],:active,0)


  set_gtk_property!(m["entSF"],:editable,false)
  set_gtk_property!(m["entNumFreq"],:editable,false)

  initBGSubtractionWidgets(m)

  @debug "" mpilab[].settings

  function loadRecoProfile( widget )

    cache = loadcache()

    selectedProfileName = Gtk.bytestring( G_.active_text(m["cbRecoProfiles"]))
    @debug "" selectedProfileName
    if haskey(cache["recoParams"],selectedProfileName)
      Gtk.@sigatom setParams(m, cache["recoParams"][selectedProfileName])
    end

  end
  signalId_cbRecoProfiles = signal_connect(loadRecoProfile, m["cbRecoProfiles"], "changed")

  function saveRecoParams( widget )
    currentRecoParams = getParams(m)
    key = get_gtk_property(m["entRecoParamsName"], :text, String)

    cache = loadcache()
    cache["recoParams"][key] = currentRecoParams
    savecache(cache)

    Gtk.@sigatom updateRecoProfiles()
  end

  function deleteRecoProfile( widget )
    selectedProfileName = Gtk.bytestring( G_.active_text(m["cbRecoProfiles"]))

    Gtk.@sigatom @info "delete reco profile $selectedProfileName"

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
    set_gtk_property!(m["cbRecoProfiles"],:active,0)
    signal_handler_unblock(m["cbRecoProfiles"], signalId_cbRecoProfiles)
  end

  #updateRecoProfiles()

  #signal_connect(performMultiProcessReco, m["tbPerformMultipleProcess"], "clicked")

  signal_connect(saveRecoParams, m["btSaveRecoParams"], "clicked")
  signal_connect(deleteRecoProfile, m["btDeleteRecoProfile"], "clicked")

  initCallbacks(m)

  return m
end

function initCallbacks(m_::RecoWidget)
  #@time signal_connect(performReco, m["tbPerformReco"], "clicked", Nothing, (), false, m)
  let m = m_
    signal_connect((w)->performReco(m), m["tbPerformReco"], "clicked")
    signal_connect((w)->selectSF(m), m["btBrowseSF"], "clicked")
    signal_connect(m["adjSelectedSF"], "value_changed") do widget
      @debug "" m.bSF

      m.selectedSF = get_gtk_property(m_["adjSelectedSF"],:value,Int64)

      txt = m.bSF[m.selectedSF].path
      set_gtk_property!(m["entSF"], :text, txt)
    end
    signal_connect(m["adjNumSF"], "value_changed") do widget
      tmpbSF = copy(m.bSF)
      resize!(m.bSF, get_gtk_property(m["adjNumSF"],:value,Int64) )
      if length(m.bSF) > length(tmpbSF)
        for i=(length(tmpbSF)+1):length(m.bSF)
          m.bSF[i] = BrukerFile()
        end
      end

      Gtk.@sigatom set_gtk_property!(m["adjSelectedSF"], :upper, length(m.bSF))
    end

    updateSFParamsChanged_ = (w)->updateSFParamsChanged(m)

    signal_connect(updateSFParamsChanged_, m["adjMinFreq"], "value_changed")
    signal_connect(updateSFParamsChanged_, m["adjMaxFreq"], "value_changed")
    signal_connect(updateSFParamsChanged_, m["adjSNRThresh"], "value_changed")
    signal_connect(updateSFParamsChanged_, m["cbLoadAsReal"], "toggled")
    signal_connect(updateSFParamsChanged_, m["cbSolver"], "changed")
    signal_connect(updateSFParamsChanged_, m["cbSubtractBG"], "toggled")
    signal_connect(updateSFParamsChanged_, m["cbSubtractInternalBG"], "toggled")
    signal_connect(updateSFParamsChanged_, m["cbRecX"], "toggled")
    signal_connect(updateSFParamsChanged_, m["cbRecY"], "toggled")
    signal_connect(updateSFParamsChanged_, m["cbRecZ"], "toggled")
    signal_connect(updateSFParamsChanged_, m["cbMatrixCompression"], "toggled")
    signal_connect(updateSFParamsChanged_, m["adjRedFactor"], "value_changed")
    signal_connect(updateSFParamsChanged_, m["cbSparsityTrafo"], "changed")

    signal_connect((w)->saveReco(m), m["tbSaveReco"], "clicked")
    signal_connect((w)->updateBGMeas(m), m["cbBGMeasurements"], "changed")
    signal_connect((w)->updateBGMeas(m), m["cbSubtractBG"], "toggled")

  end
end

function saveReco(m::RecoWidget)
  if m.recoResult != nothing
    m.recoResult["recoParams"][:description] = get_gtk_property(m["entRecoDescrip"], :text, String)
    Gtk.@sigatom addReco(mpilab[], m.recoResult, m.currentStudy, m.currentExperiment)
  end
end

function updateBGMeas(m::RecoWidget)
  if get_gtk_property(m["cbBGMeasurements"],"active", Int) >= 0

    bgstr =  Gtk.bytestring( G_.active_text(m["cbBGMeasurements"]))
    if !isempty(bgstr)
      bgnum =  parse(Int64, bgstr)
      filenameBG = m.bgExperiments[bgnum]
      @debug "" filenameBG
      if isdir(filenameBG) || isfile(filenameBG)
        m.bEmpty = MPIFile(filenameBG)

        set_gtk_property!(m["adjFirstFrameBG"],:upper, numScans(m.bEmpty))
        set_gtk_property!(m["adjLastFrameBG"],:upper, numScans(m.bEmpty))
      end
    end
  end
end

function updateSFParamsChanged(m::RecoWidget)
  m.sfParamsChanged = true
end

function selectSF(m::RecoWidget)
  try
    dlg = SFSelectionDialog( gradient=sfGradient(m.bMeas)[3], driveField=dfStrength(m.bMeas)  )

    ret = run(dlg)
    if ret == GtkResponseType.ACCEPT

      if hasselection(dlg.selection)
        sffilename =  getSelectedSF(dlg)

        @debug "" sffilename
        setSF(m, sffilename )
      end
    end
    destroy(dlg)
  catch ex
    showError(ex)
  end
end

function initBGSubtractionWidgets(m::RecoWidget)

  if mpilab[].currentStudy != nothing
    empty!(m["cbBGMeasurements"])
    empty!(m.bgExperiments)

    experiments = getExperiments( activeDatasetStore(mpilab[]), mpilab[].currentStudy)

    idxFG = 0

    for (i,exp) in enumerate(experiments)

      m.bgExperiments[exp.num] = exp.path
      push!(m["cbBGMeasurements"], string(exp.num))

      if filepath(m.bMeas) == exp.path
        idxFG = i-1
      end
    end

    Gtk.@sigatom set_gtk_property!(m["cbBGMeasurements"],:active, idxFG)
  end
end

function setSF(m::RecoWidget, filename)

  m.bSF[m.selectedSF] = MPIFile( filename )

  set_gtk_property!(m["entSF"], :text, filename)
  set_gtk_property!(m["adjMinFreq"],:upper,bandwidth(m.bSF[m.selectedSF]) / 1000)
  set_gtk_property!(m["adjMaxFreq"],:upper,bandwidth(m.bSF[m.selectedSF]) / 1000)

  m.sfParamsChanged = true
  nothing
end

function updateData!(m::RecoWidget, filenameMeas, params::Dict,
                     study=nothing, experiment=nothing)
  setParams(m, params)
  updateData!(m, filenameMeas, study, experiment)
end

function updateData!(m::RecoWidget, filenameMeas, study=nothing, experiment=nothing)
  if filenameMeas != nothing
    m.bMeas = MPIFile(filenameMeas)
    set_gtk_property!(m["adjFrame"],:upper, numScans(m.bMeas))
    set_gtk_property!(m["adjLastFrame"],:upper, numScans(m.bMeas))
    try
      if m.bSF[1].path=="" && isdir( sfPath(m.bMeas) )
        setSF(m, sfPath(m.bMeas)  )
      elseif isdir( m.bSF[1].path )
        setSF(m, m.bSF[1].path )
      end
    catch

    end
    initBGSubtractionWidgets(m)
    m.currentStudy = study
    m.currentExperiment = experiment
  end
  nothing
end

function updateSF(m::RecoWidget)
  params = getParams(m)

  bgcorrection = get_gtk_property(m["cbSubtractBG"], :active, Bool) ||
                 get_gtk_property(m["cbSubtractInternalBG"], :active, Bool)

  m.freq = filterFrequencies(m.bSF, minFreq=params[:minFreq], maxFreq=params[:maxFreq],
                             SNRThresh=params[:SNRThresh], recChannels=params[:recChannels])

  Gtk.@sigatom set_gtk_property!(m["entNumFreq"], :text, string(length(m.freq)))

    #TODO

#     redFactor = get_gtk_property(adjRedFac, :value, Float64)
#     if get_gtk_property(cbSparseReco, :active, Bool)
#       S = getSF(m.bSF, freq, redFactor=redFactor, sparseTrafo="DCT")
#     else

  @info "Reloading SF"
  m.sysMatrix, m.recoGrid = getSF(m.bSF, m.freq, params[:sparseTrafo], params[:solver], bgcorrection=bgcorrection,
                      loadasreal = params[:loadasreal], loadas32bit = params[:loadas32bit],
                      redFactor = params[:redFactor])

  m.sfParamsChanged = false
end

#function performReco(widgetptr::Ptr, m::RecoWidget)
function performReco(m::RecoWidget)
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
  params[:lambd] = get_gtk_property(m["adjLambdaL2"], :value, Float64)
  params[:lambdaL1] = get_gtk_property(m["adjLambdaL1"], :value, Float64)
  params[:lambdaTV] = get_gtk_property(m["adjLambdaTV"], :value, Float64)
  params[:iterations] = get_gtk_property(m["adjIterations"], :value, Int64)
  params[:SNRThresh] = get_gtk_property(m["adjSNRThresh"], :value, Float64)
  params[:minFreq] = get_gtk_property(m["adjMinFreq"], :value, Float64) * 1000
  params[:maxFreq] = get_gtk_property(m["adjMaxFreq"], :value, Float64) * 1000
  params[:nAverages] = get_gtk_property(m["adjAverages"], :value, Int64)
  params[:spectralCleaning] = get_gtk_property(m["cbSpectralCleaning"], :active, Bool)
  params[:loadasreal] = get_gtk_property(m["cbLoadAsReal"], :active, Bool)
  params[:solver] = linearSolverList()[max(get_gtk_property(m["cbSolver"],:active, Int64) + 1,1)]
  # Small hack
  if params[:solver] == "fusedlasso"
    params[:loadasreal] = true
  end

  firstFrame = get_gtk_property(m["adjFrame"], :value, Int64)
  lastFrame = get_gtk_property(m["adjLastFrame"], :value, Int64)
  if firstFrame > lastFrame
    lastFrame = firstFrame
    Gtk.@sigatom set_gtk_property!(m["adjLastFrame"], :value, lastFrame)
  end
  frames = firstFrame:lastFrame
  params[:frames] = frames


  bgcorrection = get_gtk_property(m["cbSubtractBG"], :active, Bool)
  params[:emptyMeasPath] = bgcorrection ? filepath(m.bEmpty) : nothing
  params[:bgCorrectionInternal] = get_gtk_property(m["cbSubtractInternalBG"], :active, Bool)

  if bgcorrection
    firstFrameBG = get_gtk_property(m["adjFirstFrameBG"], :value, Int64)
    lastFrameBG = get_gtk_property(m["adjLastFrameBG"], :value, Int64)
    framesBG = firstFrameBG:lastFrameBG
    params[:bgFrames] = framesBG
  else
    params[:bgFrames] = nothing
  end

  params[:description] = get_gtk_property(m["entRecoDescrip"], :text, String)

  params[:recChannels] = Int64[]
  if get_gtk_property(m["cbRecX"], :active, Bool)
    push!(params[:recChannels],1)
  end
  if get_gtk_property(m["cbRecY"], :active, Bool)
    push!(params[:recChannels],2)
  end
  if get_gtk_property(m["cbRecZ"], :active, Bool)
    push!(params[:recChannels],3)
  end

  matrixCompression = get_gtk_property(m["cbMatrixCompression"], :active, Bool)
  params[:sparseTrafo] = matrixCompression ?
           linearOperatorList()[max(get_gtk_property(m["cbSparsityTrafo"],:active, Int64) + 1,1)] : nothing

  params[:redFactor] = get_gtk_property(m["adjRedFactor"], :value, Float64)

  params[:SFPath] = String[ filepath(b) for b in m.bSF]

  return params
end

function setParams(m::RecoWidget, params)
  Gtk.@sigatom set_gtk_property!(m["adjLambdaL2"], :value, params[:lambd])
  Gtk.@sigatom set_gtk_property!(m["adjLambdaL1"], :value, get(params,:lambdaL1,0.0))
  Gtk.@sigatom set_gtk_property!(m["adjLambdaTV"], :value, get(params,:lambdaTV,0.0))
  Gtk.@sigatom set_gtk_property!(m["adjIterations"], :value, params[:iterations])
  Gtk.@sigatom set_gtk_property!(m["adjSNRThresh"], :value, params[:SNRThresh])
  Gtk.@sigatom set_gtk_property!(m["adjMinFreq"], :value, params[:minFreq] / 1000)
  Gtk.@sigatom set_gtk_property!(m["adjMaxFreq"], :value, params[:maxFreq] / 1000)
  Gtk.@sigatom set_gtk_property!(m["adjAverages"], :value, params[:nAverages])
  Gtk.@sigatom set_gtk_property!(m["adjFrame"], :value, first(params[:frames]))
  Gtk.@sigatom set_gtk_property!(m["adjLastFrame"], :value, last(params[:frames]))
  Gtk.@sigatom set_gtk_property!(m["cbSpectralCleaning"], :active, params[:spectralCleaning])
  Gtk.@sigatom set_gtk_property!(m["cbLoadAsReal"], :active, params[:loadasreal])
  Gtk.@sigatom set_gtk_property!(m["adjRedFactor"], :value, get(params,:redFactor,0.01))

  for (i,solver) in enumerate(linearSolverList())
    if solver == params[:solver]
      Gtk.@sigatom set_gtk_property!(m["cbSolver"],:active, i-1)
    end
  end

  sparseTrafo = get(params, :sparseTrafo, nothing)
  Gtk.@sigatom set_gtk_property!(m["cbMatrixCompression"], :active,
                       sparseTrafo != nothing)
  if sparseTrafo != nothing
    for (i,trafo) in enumerate(linearOperatorList())
      if trafo == sparseTrafo
        Gtk.@sigatom set_gtk_property!(m["cbSparsityTrafo"],:active, i-1)
      end
    end
  end

  set_gtk_property!(m["cbRecX"], :active, in(1,params[:recChannels]))
  set_gtk_property!(m["cbRecY"], :active, in(2,params[:recChannels]))
  set_gtk_property!(m["cbRecZ"], :active, in(3,params[:recChannels]))

  Gtk.@sigatom set_gtk_property!(m["entRecoDescrip"], :text, get(params, :description,""))
  Gtk.@sigatom set_gtk_property!(m["cbSubtractInternalBG"], :active, get(params, :bgCorrectionInternal, false))


  if haskey(params, :SFPath)
    if typeof(params[:SFPath]) <: AbstractString
      params[:SFPath] = String[params[:SFPath]]
    end
    numSF = length(params[:SFPath])
    Gtk.@sigatom set_gtk_property!(m["adjNumSF"], :value, numSF)
    m.bSF = MPIFile(params[:SFPath])
  else
    Gtk.@sigatom set_gtk_property!(m["adjNumSF"], :value, 1)
    m.bSF = MPIFile[BrukerFile()]
  end

end




























#=
function performMultiProcessReco( widget )
  @debug "Num Procs: $(procs())"
  recoWorkers = workers()
  @debug "Num Workers: $(recoWorkers)"
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
            @debug "Entering recoTask..."
            taskParams = copy(params)
            taskParams[:frames] = splittedFrames[p]
            recoResult = remotecall_fetch(multiCoreReconstruction, recoWorkers[p], bSF, bMeas, freq, taskParams )
            recoResults[p] = recoResult
            @debug "Finished recoTask."
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
      @debug "reco processes finished."
    end # async
  end # Gtk.sigatom
end #Function
=#
