
mutable struct OnlineRecoHandler <: AbstractDataHandler
  dataWidget::DataViewerWidget
  params::ReconstructionParameter
  @atomic enabled::Bool
  @atomic ready::Bool
  # Protocol
  deltaT::Float64
  bgMeas::Array{Float32, 4}
  oldUnit::String
  systemMatrix
  freq
  recoGrid
end


function OnlineRecoHandler(scanner=nothing)
  dataWidget = DataViewerWidget()
  params = defaultRecoParams()
  recoParams = ReconstructionParameter(params) 


  # Init Display Widget (warmstart)
  c = ones(Float32,1,3,3,3,1)
  c = makeAxisArray(c, [0.1,0.1,0.1], zeros(3), 1.0) 
  updateData!(dataWidget, ImageMeta(c))

  return OnlineRecoHandler(dataWidget, recoParams, true, true, 0, zeros(Float32,0,0,0,0), "",
                           nothing, nothing, nothing)
end

function init(handler::OnlineRecoHandler, protocol::Protocol)
  seq = protocol.params.sequence
  handler.oldUnit = ""
  handler.deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
  handler.bgMeas = zeros(Float32,0,0,0,0)
  # TODO Load system matrix if dispaly is enabled
end 

function isready(handler::OnlineRecoHandler)
  ready = @atomic handler.ready
  enabled = @atomic handler.enabled
  return ready && enabled
end
function enable!(handler::OnlineRecoHandler, val::Bool) 
  @atomic handler.enabled = val
end
getParameterTitle(handler::OnlineRecoHandler) = "Online Reco"
getParameterWidget(handler::OnlineRecoHandler) = handler.params
getDisplayTitle(handler::OnlineRecoHandler) = "Online Reco"
getDisplayWidget(handler::OnlineRecoHandler) = handler.dataWidget

function handleProgress(handler::OnlineRecoHandler, protocol::Union{MPIMeasurementProtocol, RobotMPIMeasurementProtocol}, event::ProgressEvent)
  query = nothing
  if handler.oldUnit == "BG Frames" && event.unit == "Frames"
    @debug "Asking for background measurement"
    # TODO technically we lose the "first" proper frame now, until we implement returning multiple queries
    # If there is only one fg we get that in the next plot from the mdf anyway
    query = DataQueryEvent("BG")
  else
    @debug "Asking for new frame $(event.done)"
    query = DataQueryEvent("FRAME:$(event.done)")
  end
  handler.oldUnit = event.unit
  return query
end
function handleProgress(handler::OnlineRecoHandler, protocol::ContinousMeasurementProtocol, event::ProgressEvent)
  query = nothing
  if handler.oldUnit == "BG Measurement" && event.unit == "Measurements"
    @debug "Asking for background measurement"
    # TODO technically we lose the "first" proper frame now, until we implement returning multiple queries
    # If there is only one fg we get that in the next plot from the mdf anyway
    query = DataQueryEvent("BG")
  else
    @debug "Asking for new measurement $(event.done)"
    query = DataQueryEvent("FG")
  end
  handler.oldUnit = event.unit
  return query
end

function handleProgress(handler::OnlineRecoHandler, protocol::RobotBasedSystemMatrixProtocol, event::ProgressEvent)
  query = nothing
  if isempty(handler.bgMeas)
    query = DataQueryEvent("BG")
  else
    query = DataQueryEvent("CURR")
  end
  return query
end


############


# THIS is a copy from Offline Widget
function updateSF(m::OnlineRecoHandler)
  params = getParams(m.params)

  bgcorrection = (params[:emptyMeasPath] != nothing) || params[:bgCorrectionInternal]
                 
  m.freq = filterFrequencies(m.params.bSF, minFreq=params[:minFreq], maxFreq=params[:maxFreq],
                             SNRThresh=params[:SNRThresh], recChannels=params[:recChannels],
                             numPeriodAverages = params[:numPeriodAverages], 
                             numPeriodGrouping = params[:numPeriodGrouping],
                             maxMixingOrder = params[:maxMixingOrder])


  @info "Reloading SF"
 
  m.systemMatrix, m.recoGrid = getSF(m.params.bSF, m.freq, params[:sparseTrafo], params[:solver], bgcorrection=bgcorrection,
                      loadasreal = params[:loadasreal], loadas32bit = params[:loadas32bit],
                      redFactor = params[:redFactor], numPeriodAverages = params[:numPeriodAverages], 
                      numPeriodGrouping = params[:numPeriodGrouping], gridsize = params[:gridShape])

  m.params.sfParamsChanged = false

  return nothing
end


function reconstruct(m::OnlineRecoHandler, data)
  @tspawnat 2 reconstruct_(m, data)
  #execute_(m, data, dv)
end

@guarded function reconstruct_(m::OnlineRecoHandler, data)
  
  @info "Performing Reconstruction"

  params = getParams(m.params)

  if m.params.sfParamsChanged
    updateSF(m)
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  #if params[:emptyMeasPath] != nothing
  #  params[:bEmpty] = MPIFile( params[:emptyMeasPath] )
  #end

  # If S is processed and fits not to the measurements because of numPeriodsGrouping
  # or numPeriodAverages being applied we need to set these so that the 
  # measurements are loaded correctly

  @info "$(rxNumSamplingPoints(m.params.bSF[1]))   $(size(data,1))"

  if rxNumSamplingPoints(m.params.bSF[1]) > size(data,1)
    tmp = permutedims(data, (1,3,2,4))
  
    numPeriodGrouping = rxNumSamplingPoints(m.params.bSF[1]) ÷ size(data,1)
    
    tmp2 = reshape(tmp, size(tmp,1)*numPeriodGrouping, div(size(tmp,2),numPeriodGrouping),
                          size(tmp,3), size(tmp,4) )
    data = permutedims(tmp2, (1,3,2,4))  
    #data = reshape(data, rxNumSamplingPoints(m.params.bSF[1]), size(data,2), :, size(data,4))
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  @info "$(acqNumPeriodsPerFrame(m.params.bSF[1]))   $(size(data,3))"

  if acqNumPeriodsPerFrame(m.params.bSF[1]) < size(data,3)
    #params[:numPeriodAverages] = acqNumPeriodsPerFrame(m.bMeas) ÷ (acqNumPeriodsPerFrame(m.params.bSF[1]) * params[:numPeriodGrouping])
    error("Implement me!")
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  # apply FFT
  if measIsFourierTransformed(m.params.bSF[1])
    data = rfft(data, 1)
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"


  #=if tfCorrection && !measIsTFCorrected(f)
    tf = rxTransferFunction(f)
    inductionFactor = rxInductionFactor(f)
    data[2:end,:,:,:] ./= tf[2:end,:,:,:]
    @warn "This measurement has been corrected with a Transfer Function. Name of TF: $(rxTransferFunctionFileName(f))"
    if inductionFactor != nothing
       	for k=1:length(inductionFactor)
       		data[:,k,:,:] ./= inductionFactor[k]
       	end
    end
  end =#

  if m.freq != nothing
    # here we merge frequencies and channels
    # data = reshape(data, size(data,1)*size(data,2), size(data,3), size(data,4))
    data = data[m.freq, :, :]
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  if eltype(m.systemMatrix) <: Real
    data = MPIFiles.returnasreal(data)
  end

  data = reshape(data, :, size(data,3))

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  c = MPIReco.reconstruction(m.systemMatrix, data; shape=shape(m.recoGrid), params...)

  #conc = MPIReco.reconstruction(m.systemMatrix, m.params.bSF, m.bMeas, m.freq, m.recoGrid; params...)

  D = shape(m.recoGrid)
  numChan = length(m.params.bSF)
  cB = permutedims(reshape(c, D[1]*D[2]*D[3], numChan),[2,1])
  cF = reshape(cB, numChan, D[1], D[2], D[3], 1)

  #images = cat(cF, images, dims=5)
  cF = makeAxisArray(cF, spacing(m.recoGrid), m.recoGrid.center, 1.0) 

  cF = ImageMeta(cF)

  #m.recoResult = conc
  #m.recoResult.recoParams = getParams(m.params)

  @idle_add_guarded begin
    updateData!(m.dataWidget, cF)
  end

  return nothing
end






##########


function handleData(handler::OnlineRecoHandler, protocol::Protocol, event::DataAnswerEvent)
  data = event.data
  if isnothing(data)
    return nothing
  end
  if event.query.message == "BG"
    handler.bgMeas = event.data
    ## TODO something  setBG(handler.dataWidget, handler.bgMeas)
  else 
    @atomic handler.ready = false
    @idle_add_guarded begin
      try
        reconstruct(handler, data)
      finally
        @atomic handler.ready = true
      end
    end
  end
end
