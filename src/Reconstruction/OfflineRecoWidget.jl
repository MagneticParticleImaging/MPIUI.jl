export RecoWindow, OfflineRecoWidget

include("ReconstructionParameter.jl")
include("RecoPlanParameter.jl")
include("RecoPlanParameterList.jl")

mutable struct OfflineRecoWidget <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  builder
  params::ReconstructionParameter
  dv
  bMeas
  sysMatrix
  freq
  recoResult
  recoGrid
  currentStudy
  currentExperiment
end

getindex(m::OfflineRecoWidget, w::AbstractString) = G_.get_object(m.builder, w)

mutable struct RecoWindow
  w::Gtk4.GtkWindowLeaf
  rw::OfflineRecoWidget
end

function RecoWindow(filenameMeas=nothing; params = defaultRecoParams())
  w = GtkWindow("Reconstruction",800,600)
  dw = OfflineRecoWidget(filenameMeas, params=params)
  push!(w,dw)

  #if isassigned(mpilab)
  #  G_.transient_for(w, mpilab[]["mainWindow"])
  #end
  G_.modal(w,true)
  show(w)

  return RecoWindow(w,dw)
end

function OfflineRecoWidget(filenameMeas=nothing; params = defaultRecoParams())

  uifile = joinpath(@__DIR__, "..", "builder", "reconstructionWidget.ui")

  b = GtkBuilder(uifile)
  mainGrid = G_.get_object(b, "gridReco")
  boxParams = G_.get_object(b, "boxParams")

  recoParams = ReconstructionParameter(params)

  push!(boxParams, recoParams)
###  set_gtk_property!(boxParams,:fill,recoParams, true) 
###  set_gtk_property!(boxParams,:expand,recoParams, true) 
  show(recoParams) 

  @info "in OfflineRecoWidget"

  m = OfflineRecoWidget( mainGrid.handle, b,
                  recoParams,
                  nothing,
                  nothing,
                  nothing, nothing, nothing, nothing,
                  nothing, nothing)
  Gtk4.GLib.gobject_move_ref(m, mainGrid)

  m.dv = DataViewerWidget()
  push!(m["boxDW"], m.dv)
  ###set_gtk_property!(m["boxDW"], :fill, m.dv, true)
  ###set_gtk_property!(m["boxDW"], :expand, m.dv, true)

  updateData!(m, filenameMeas)

  initCallbacks(m)

  return m
end

function initCallbacks(m::OfflineRecoWidget)
  signal_connect((w)->performReco(m), m["tbPerformReco"], "clicked")
  signal_connect((w)->saveReco(m), m["tbSaveReco"], "clicked")
end

function setParams(m::OfflineRecoWidget, params)
  return setParams(m.params, params)
end

function getParams(m::OfflineRecoWidget)
  return getParams(m.params)
end

function setSF(m::OfflineRecoWidget, path)
  return setSF(m.params, path)
end

function saveReco(m::OfflineRecoWidget)
  if m.recoResult !== nothing
    m.recoResult.recoParams[:description] = get_gtk_property(m.params["entRecoDescrip"], :text, String)
    if isassigned(mpilab)
      @idle_add_guarded addReco(mpilab[], m.recoResult, m.currentStudy, m.currentExperiment)
    else
      if m.currentStudy !== nothing && m.currentExperiment !== nothing
        # using MDFDatasetStore
        addReco(getMDFStore(m.currentStudy), m.currentStudy, m.currentExperiment, m.recoResult)
      else
        # no DatasetStore -> save reco in the same folder as the measurement
        pathfile = joinpath(split(filepath(m.bMeas),"/")[1:end-1]...,"reco")
        saveRecoData(pathfile*".mdf",m.recoResult)
        @info "Reconstruction saved at $(pathfile).mdf"
      end
    end
  end
end

function updateData!(m::OfflineRecoWidget, filenameMeas, params::Dict,
                     study=nothing, experiment=nothing)
  setParams(m.params, params)
  updateData!(m, filenameMeas, study, experiment)
end

@guarded function updateData!(m::OfflineRecoWidget, filenameMeas, study=nothing, experiment=nothing)
  if filenameMeas != nothing
    m.bMeas = MPIFile(filenameMeas)
    set_gtk_property!(m.params["adjFrame"],:upper, acqNumFrames(m.bMeas))
    set_gtk_property!(m.params["adjLastFrame"],:upper, acqNumFrames(m.bMeas))
    try
      if filepath(m.params.bSF[1])=="" #&& isdir( sfPath(m.bMeas) )
        #setSF(m, sfPath(m.bMeas)  )
      elseif isdir( filepath(m.params.bSF[1]) ) || isfile( filepath(m.params.bSF[1]) )
        setSF(m.params, filepath(m.params.bSF[1]) )
      end
    catch e
      @show e
    end
    initBGSubtractionWidgets(m.params, study, experiment)
    m.currentStudy = study
    m.currentExperiment = experiment
  end
  return nothing
end

function updateSF(m::OfflineRecoWidget)
  params = getParams(m.params)

  bgcorrection = (params[:emptyMeasPath] != nothing) || params[:bgCorrectionInternal]
                 
  m.freq = filterFrequencies(m.params.bSF, minFreq=params[:minFreq], maxFreq=params[:maxFreq],
                             SNRThresh=params[:SNRThresh], recChannels=params[:recChannels],
                             numPeriodAverages = params[:numPeriodAverages], 
                             numPeriodGrouping = params[:numPeriodGrouping],
                             maxMixingOrder = params[:maxMixingOrder])


  @info "Reloading SF"
  @show m.params.bSF
  infoMessage(m, "Loading System Matrix...")

  m.sysMatrix, m.recoGrid = getSF(m.params.bSF, m.freq, params[:sparseTrafo], params[:solver], bgcorrection=bgcorrection,
                      loadasreal = params[:loadasreal], loadas32bit = params[:loadas32bit],
                      redFactor = params[:redFactor], numPeriodAverages = params[:numPeriodAverages], 
                      numPeriodGrouping = params[:numPeriodGrouping], gridsize = params[:gridShape])

  infoMessage(m, "")
  m.params.sfParamsChanged = false

  return nothing
end

function infoMessage(m::OfflineRecoWidget, message::String="", color::String="green")
  @idle_add_guarded begin
    message = """<span foreground="$color" font_weight="bold" size="x-large">$message</span>"""
    if isassigned(mpilab)
      infoMessage(mpilab[], message)
    end
  end
end

function progress(m::OfflineRecoWidget, startStop::Bool)
  if isassigned(mpilab)
    progress(mpilab[], startStop)
  end
end


function performReco(m::OfflineRecoWidget)
  @tspawnat 2 performReco_(m)
end

@guarded function performReco_(m::OfflineRecoWidget)
  
  params = getParams(m.params)

  @idle_add_guarded progress(m, true)

  if m.params.sfParamsChanged
    updateSF(m)
  end

  if params[:emptyMeasPath] != nothing
    params[:bEmpty] = MPIFile( params[:emptyMeasPath] )
    if typeof(params[:bEmpty]) == BrukerFileCalib
      bbEmpty = params[:bEmpty]
      bbEmpty_ = BrukerFileMeas(bbEmpty.path,bbEmpty.params,bbEmpty.paramsProc,bbEmpty.methodRead,bbEmpty.acqpRead,bbEmpty.visupars_globalRead,bbEmpty.recoRead,bbEmpty.methrecoRead,bbEmpty.visuparsRead,bbEmpty.mpiParRead,bbEmpty.maxEntriesAcqp);
      params[:bEmpty] = bbEmpty_
    end
  end

  # If S is processed and fits not to the measurements because of numPeriodsGrouping
  # or numPeriodAverages being applied we need to set these so that the 
  # measurements are loaded correctly
  if rxNumSamplingPoints(m.params.bSF[1]) > rxNumSamplingPoints(m.bMeas)
    params[:numPeriodGrouping] = rxNumSamplingPoints(m.params.bSF[1]) ÷ rxNumSamplingPoints(m.bMeas)
  end
  if acqNumPeriodsPerFrame(m.params.bSF[1]) < acqNumPeriodsPerFrame(m.bMeas)
    params[:numPeriodAverages] = acqNumPeriodsPerFrame(m.bMeas) ÷ (acqNumPeriodsPerFrame(m.params.bSF[1]) * params[:numPeriodGrouping])
  end

  infoMessage(m, "Performing Reconstruction...")

  if typeof(m.bMeas) == BrukerFileCalib
    m.bMeas = BrukerFileMeas(m.bMeas.path,m.bMeas.params,m.bMeas.paramsProc,m.bMeas.methodRead,m.bMeas.acqpRead,m.bMeas.visupars_globalRead,m.bMeas.recoRead,m.bMeas.methrecoRead,m.bMeas.visuparsRead,m.bMeas.mpiParRead,m.bMeas.maxEntriesAcqp);

    conc = MPIReco.reconstruction(m.sysMatrix, m.params.bSF, m.bMeas, m.freq, m.recoGrid; params...)

  else
    conc = MPIReco.reconstruction(m.sysMatrix, m.params.bSF, m.bMeas, m.freq, m.recoGrid; params...)
  end
  m.recoResult = conc
  m.recoResult.recoParams = getParams(m.params)
  @idle_add_guarded begin
    updateData!(m.dv, m.recoResult)
    infoMessage(m, "")
    progress(m, false)
  end

  return nothing
end
