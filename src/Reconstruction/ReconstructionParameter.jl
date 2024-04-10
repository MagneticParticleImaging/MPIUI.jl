function linearSolverList()
  Any["kaczmarz", "cgnr", "fusedlasso"]
end

mutable struct ReconstructionParameter <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  params::Dict{Symbol,Any}
  sfParamsChanged::Bool
  bSF
  bgExperiments
  bEmpty
  selectedSF

  function ReconstructionParameter(params=defaultRecoParams()) #, value::Sequence, scanner::MPIScanner)
    uifile = joinpath(@__DIR__, "..", "builder", "reconstructionParams.ui")
    b = GtkBuilder(uifile)

    exp = G_.get_object(b, "boxRecoParams")

    #addTooltip(object_(pw.builder, "lblSequence", GtkLabel), tooltip)
    m = new(exp.handle, b, params, true, nothing, Dict{Int64,String}(),
            nothing, 1) #, value, scanner)
    Gtk4.GLib.gobject_move_ref(m, exp)
    
    setParams(m, params)

    choices = linearSolverList()
    for c in choices
      push!(m["cbSolver"], c)
    end
    set_gtk_property!(m["cbSolver"],:active,0)
  
    #choices = linearOperatorList()
    #for c in choices
    #  push!(m["cbSparsityTrafo"], c)
    #end
    #set_gtk_property!(m["cbSparsityTrafo"], :active, 0)
  
    set_gtk_property!(m["entSF"],:editable,false)
    set_gtk_property!(m["entNumFreq"],:editable,false)
  
    initBGSubtractionWidgets(m)
  
    function loadRecoProfile( widget )
  
      cache = loadcache()
  
      selectedProfileName = Gtk4.bytestring(Gtk4.active_text(m["cbRecoProfiles"]))
      @debug "" selectedProfileName
      if haskey(cache["recoParams"],selectedProfileName)
        @idle_add_guarded setParams(m, cache["recoParams"][selectedProfileName])
      end
  
    end
    signalId_cbRecoProfiles = signal_connect(loadRecoProfile, m["cbRecoProfiles"], "changed")
  
    function saveRecoParams( widget )
      currentRecoParams = getParams(m)
      key = get_gtk_property(m["entRecoParamsName"], :text, String)
  
      cache = loadcache()
      cache["recoParams"][key] = currentRecoParams
      savecache(cache)
  
      @idle_add_guarded updateRecoProfiles()
    end
  
    function deleteRecoProfile( widget )
      selectedProfileName = Gtk4.bytestring(Gtk4.active_text(m["cbRecoProfiles"]))
  
      @idle_add_guarded @info "delete reco profile $selectedProfileName"
  
      cache = loadcache()
      delete!(cache["recoParams"], selectedProfileName)
      savecache(cache)
  
      @idle_add_guarded updateRecoProfiles()
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
  
end

getindex(m::ReconstructionParameter, w::AbstractString) = G_.get_object(m.builder, w)


function initCallbacks(m::ReconstructionParameter)

  signal_connect(m["btBrowseSF"], "clicked") do w
    @idle_add selectSF(m)
  end
  signal_connect(m["adjSelectedSF"], "value_changed") do widget
    @debug "" m.bSF

    m.selectedSF = get_gtk_property(m["adjSelectedSF"],:value,Int64)

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

    @idle_add_guarded set_gtk_property!(m["adjSelectedSF"], :upper, length(m.bSF))
  end

  updateSFParamsChanged_ = (w)->updateSFParamsChanged(m)

  signal_connect(updateSFParamsChanged_, m["adjMinFreq"], "value_changed")
  signal_connect(updateSFParamsChanged_, m["adjMaxFreq"], "value_changed")
  signal_connect(updateSFParamsChanged_, m["adjSNRThresh"], "value_changed")
  signal_connect(updateSFParamsChanged_, m["adjMaxMixOrder"], "value_changed")
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
  signal_connect(updateSFParamsChanged_, m["adjPeriodAverages"], "value_changed")
  signal_connect(updateSFParamsChanged_, m["adjPeriodGrouping"], "value_changed")
  signal_connect(updateSFParamsChanged_, m["entGridShape"], "changed")

  signal_connect((w)->updateBGMeas(m), m["cbBGMeasurements"], "changed")
  signal_connect((w)->updateBGMeas(m), m["cbSubtractBG"], "toggled")

end


function getParams(m::ReconstructionParameter)
  params = defaultRecoParams()
  params[:lambd] = get_gtk_property(m["adjLambdaL2"], :value, Float64)
  params[:lambdaL1] = get_gtk_property(m["adjLambdaL1"], :value, Float64)
  params[:lambdaTV] = get_gtk_property(m["adjLambdaTV"], :value, Float64)
  params[:iterations] = get_gtk_property(m["adjIterations"], :value, Int64)
  params[:SNRThresh] = get_gtk_property(m["adjSNRThresh"], :value, Float64)
  params[:maxMixingOrder] = get_gtk_property(m["adjMaxMixOrder"], :value, Int64)
  params[:minFreq] = get_gtk_property(m["adjMinFreq"], :value, Float64) * 1000
  params[:maxFreq] = get_gtk_property(m["adjMaxFreq"], :value, Float64) * 1000
  params[:nAverages] = get_gtk_property(m["adjAverages"], :value, Int64)
  params[:spectralCleaning] = get_gtk_property(m["cbSpectralCleaning"], :active, Bool)
  params[:loadasreal] = get_gtk_property(m["cbLoadAsReal"], :active, Bool)
  solver = linearSolverList()[max(get_gtk_property(m["cbSolver"],:active, Int64) + 1,1)]
  # Small hack
  #=if params[:solver] == "fusedlasso"
    params[:loadasreal] = true
    params[:lambd] = [params[:lambdaL1], params[:lambdaTV]]
    params[:regName] = ["L1", "TV"]
  end=#

  params[:solver] = Kaczmarz

  if params[:solver] == Kaczmarz
    if params[:lambdaL1] == 0.0
      params[:reg] = AbstractRegularization[L2Regularization(Float32(params[:lambd]))]
    else
      params[:reg] = AbstractRegularization[L2Regularization(Float32(params[:lambd])), L1Regularization(Float32(params[:lambdaL1]))]
    end
    append!(params[:reg], [PositiveRegularization(), RealRegularization()])
  end

  firstFrame = get_gtk_property(m["adjFrame"], :value, Int64)
  lastFrame = get_gtk_property(m["adjLastFrame"], :value, Int64)
  if firstFrame > lastFrame
    lastFrame = firstFrame
    @idle_add_guarded set_gtk_property!(m["adjLastFrame"], :value, lastFrame)
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

  params[:numPeriodAverages] = get_gtk_property(m["adjPeriodAverages"], :value, Int64)
  params[:numPeriodGrouping] = get_gtk_property(m["adjPeriodGrouping"], :value, Int64)

  shpString = get_gtk_property(m["entGridShape"], :text, String)
  shp = tryparse.(Int64,split(shpString,"x"))

  params[:gridShape] = (shp[1] == nothing) ? (isfile(filepath(m.bSF[1])) ? calibSize(m.bSF[1]) : [1, 1, 1]) : shp

  return params
end

function setParams(m::ReconstructionParameter, params)
  @idle_add_guarded begin
    set_gtk_property!(m["adjLambdaL2"], :value, first(params[:lambd]))
    set_gtk_property!(m["adjLambdaL1"], :value, get(params,:lambdaL1,0.0))
    set_gtk_property!(m["adjLambdaTV"], :value, get(params,:lambdaTV,0.0))
    set_gtk_property!(m["adjIterations"], :value, params[:iterations])
    set_gtk_property!(m["adjSNRThresh"], :value, params[:SNRThresh])
    set_gtk_property!(m["adjMaxMixOrder"], :value, get(params,:maxMixingOrder,-1))
    set_gtk_property!(m["adjMinFreq"], :value, params[:minFreq] / 1000)
    set_gtk_property!(m["adjMaxFreq"], :value, params[:maxFreq] / 1000)
    set_gtk_property!(m["adjAverages"], :value, params[:nAverages])
    set_gtk_property!(m["adjFrame"], :value, first(params[:frames]))
    set_gtk_property!(m["adjLastFrame"], :value, last(params[:frames]))
    set_gtk_property!(m["cbSpectralCleaning"], :active, params[:spectralCleaning])
    set_gtk_property!(m["cbLoadAsReal"], :active, params[:loadasreal])
    set_gtk_property!(m["adjRedFactor"], :value, get(params,:redFactor,0.01))
    set_gtk_property!(m["adjPeriodAverages"], :value, get(params,:numPeriodAverages,1))
    set_gtk_property!(m["adjPeriodGrouping"], :value, get(params,:numPeriodGrouping,1))


    for (i,solver) in enumerate(linearSolverList())
      if solver == params[:solver]
        set_gtk_property!(m["cbSolver"],:active, i-1)
      end
    end

    sparseTrafo = get(params, :sparseTrafo, nothing)
    set_gtk_property!(m["cbMatrixCompression"], :active,
                        sparseTrafo != nothing)
    if sparseTrafo != nothing
      for (i,trafo) in enumerate(linearOperatorList())
        if trafo == sparseTrafo
          set_gtk_property!(m["cbSparsityTrafo"],:active, i-1)
        end
      end
    end

    set_gtk_property!(m["cbRecX"], :active, in(1,params[:recChannels]))
    set_gtk_property!(m["cbRecY"], :active, in(2,params[:recChannels]))
    set_gtk_property!(m["cbRecZ"], :active, in(3,params[:recChannels]))

    set_gtk_property!(m["entRecoDescrip"], :text, get(params, :description,""))
    set_gtk_property!(m["cbSubtractInternalBG"], :active, get(params, :bgCorrectionInternal, false))


    if haskey(params, :SFPath)
      if typeof(params[:SFPath]) <: AbstractString
        params[:SFPath] = String[params[:SFPath]]
      end
      numSF = length(params[:SFPath])
      set_gtk_property!(m["adjNumSF"], :value, numSF)
      m.bSF = MPIFile(params[:SFPath])
    else
      set_gtk_property!(m["adjNumSF"], :value, 1)
      m.bSF = MPIFile[BrukerFile()]
    end

    # grid shape
    shp = get(params,:gridShape,"")
    shpStr = (shp != "") ? @sprintf("%d x %d x %d", shp...) : ""
    set_gtk_property!(m["entGridShape"], :text, shpStr)
  end
  return nothing
end



function updateBGMeas(m::ReconstructionParameter)
  if get_gtk_property(m["cbBGMeasurements"],"active", Int) >= 0

    bgstr = Gtk4.bytestring(Gtk4.active_text(m["cbBGMeasurements"]))
    if !isempty(bgstr)
      bgnum =  parse(Int64, bgstr)
      filenameBG = m.bgExperiments[bgnum]
      @debug "" filenameBG
      if isdir(filenameBG) || isfile(filenameBG)
        m.bEmpty = MPIFile(filenameBG)

        set_gtk_property!(m["adjFirstFrameBG"],:upper, acqNumFrames(m.bEmpty))
        set_gtk_property!(m["adjLastFrameBG"],:upper, acqNumFrames(m.bEmpty))
      end
    end
  end
end

@guarded function updateSFParamsChanged(m::ReconstructionParameter)
  m.sfParamsChanged = true

  @idle_add_guarded begin
    params = getParams(m)
    if m.bSF != nothing && isfile(filepath(m.bSF[1]))
      freq = filterFrequencies(m.bSF, minFreq=params[:minFreq], maxFreq=params[:maxFreq],
            SNRThresh=params[:SNRThresh], recChannels=params[:recChannels],
            numPeriodAverages = params[:numPeriodAverages], 
            numPeriodGrouping = params[:numPeriodGrouping],
            maxMixingOrder = params[:maxMixingOrder])

      set_gtk_property!(m["entNumFreq"], :text, string(length(freq)))
    end
  end
end

@guarded function selectSF(m::ReconstructionParameter)
  #dlg = SFSelectionDialog( gradient=maximum(acqGradient(m.bMeas)), driveField=dfStrength(m.bMeas)  )
  dlg = SFSelectionDialog()

  function on_response(dlg, response_id)
      if response_id == Integer(Gtk4.ResponseType_ACCEPT)

        if hasselection(dlg.selection)
          sffilename =  getSelectedSF(dlg)
    
          @info "" sffilename
          setSF(m, sffilename, resetGrid=true)
        end
      end
      destroy(dlg)
  end

  signal_connect(on_response, dlg, "response")
  show(dlg)
end

function initBGSubtractionWidgets(m::ReconstructionParameter, study=nothing, experiment=nothing)

    if study != nothing
      empty!(m["cbBGMeasurements"])
      empty!(m.bgExperiments)

      experiments = getExperiments(study)

      idxFG = 0

      for (i,exp) in enumerate(experiments)

        m.bgExperiments[exp.num] = path(exp) 
        push!(m["cbBGMeasurements"], string(exp.num))

        if experiment != nothing && path(exp) == path(experiment)
          idxFG = i-1
        end

        @idle_add_guarded set_gtk_property!(m["cbBGMeasurements"],:active, idxFG)
      end
    end

end

function setSF(m::ReconstructionParameter, filename; resetGrid::Bool = false)

  m.bSF[m.selectedSF] = MPIFile( filename )

  @idle_add_guarded begin
    if isfile(filepath(m.bSF[m.selectedSF]))
      set_gtk_property!(m["entSF"], :text, filename)
      set_gtk_property!(m["adjMinFreq"],:upper,rxBandwidth(m.bSF[m.selectedSF]) / 1000)
      set_gtk_property!(m["adjMaxFreq"],:upper,rxBandwidth(m.bSF[m.selectedSF]) / 1000)

      if resetGrid 
        # use calibration grid from SM
        set_gtk_property!(m["entGridShape"], :text, @sprintf("%d x %d x %d", calibSize(m.bSF[m.selectedSF])...))
      end
    end
    m.sfParamsChanged = true
  end

  return nothing
end
