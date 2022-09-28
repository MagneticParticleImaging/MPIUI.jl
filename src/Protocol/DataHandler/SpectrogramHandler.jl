
mutable struct SpectrogramHandler <: AbstractDataHandler
  dataWidget::SpectrogramWidget
  @atomic enabled::Bool
  @atomic ready::Bool
  # Protocol
  deltaT::Float64
end

function SpectrogramHandler(scanner=nothing)
  data = SpectrogramWidget()
  # Init Display Widget
  updateData(data, ones(Float32,10,1,1,1), 1.0)
  return SpectrogramHandler(data, true, true, 0)
end

function init(handler::SpectrogramHandler, protocol::Protocol)
  seq = protocol.params.sequence
  handler.deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
end 

function isready(handler::SpectrogramHandler)
  ready = @atomic handler.ready
  enabled = @atomic handler.enabled
  return ready && enabled
end
function enable!(handler::SpectrogramHandler, val::Bool) 
  @atomic handler.enabled = val
end
getParameterTitle(handler::SpectrogramHandler) = "Spectrogram"
getParameterWidget(handler::SpectrogramHandler) = Box(:v)
getDisplayTitle(handler::SpectrogramHandler) = "Spectrogram"
getDisplayWidget(handler::SpectrogramHandler) = handler.dataWidget

function handleProgress(handler::SpectrogramHandler, protocol::RobotMPIMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new frame $(event.done)"
  return DataQueryEvent("FRAME:$(event.done)")
end
function handleProgress(handler::SpectrogramHandler, protocol::MPIMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new frame $(event.done)"
  return DataQueryEvent("FRAME:$(event.done)")
end
function handleProgress(handler::SpectrogramHandler, protocol::ContinousMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new measurement $(event.done)"
  return DataQueryEvent("")
end
function handleProgress(handler::SpectrogramHandler, protocol::RobotBasedSystemMatrixProtocol, event::ProgressEvent)
  @debug "Asking for latest position"
  return DataQueryEvent("SIGNAL")
end

updateData(handler::SpectrogramHandler, data::Nothing) = nothing

function updateData(handler::SpectrogramHandler, data)
  @atomic handler.ready = false
  @idle_add_guarded begin
    try
      updateData(handler.dataWidget, data, handler.deltaT)
    finally
      @atomic handler.ready = true
    end
  end
end