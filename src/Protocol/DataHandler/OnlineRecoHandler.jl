
mutable struct OnlineRecoHandler <: AbstractDataHandler
  dataWidget::DataViewerWidget
  onlineRecoWidget::OnlineRecoWidget
  @atomic enabled::Bool
  @atomic ready::Bool
  # Protocol
  deltaT::Float64
end

function OnlineRecoHandler(scanner=nothing)
  dataWidget = DataViewerWidget()
  onlineRecoWidget = OnlineRecoWidget(:test)
  # Init Display Widget
  #updateData(data, ones(Float32,10,1,1,1), 1.0)
  return OnlineRecoHandler(dataWidget, onlineRecoWidget, true, true, 0)
end

function init(handler::OnlineRecoHandler, protocol::Protocol)
  seq = protocol.params.sequence
  handler.deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
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
getParameterWidget(handler::OnlineRecoHandler) = handler.onlineRecoWidget
getDisplayTitle(handler::OnlineRecoHandler) = "Online Reco"
getDisplayWidget(handler::OnlineRecoHandler) = handler.dataWidget

function handleProgress(handler::OnlineRecoHandler, protocol::RobotMPIMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new frame $(event.done)"
  return DataQueryEvent("FRAME:$(event.done)")
end
function handleProgress(handler::OnlineRecoHandler, protocol::MPIMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new frame $(event.done)"
  return DataQueryEvent("FRAME:$(event.done)")
end
function handleProgress(handler::OnlineRecoHandler, protocol::ContinousMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new measurement $(event.done)"
  return DataQueryEvent("")
end
function handleProgress(handler::OnlineRecoHandler, protocol::RobotBasedSystemMatrixProtocol, event::ProgressEvent)
  @debug "Asking for latest position"
  return DataQueryEvent("SIGNAL")
end

updateData(handler::OnlineRecoHandler, data::Nothing) = nothing

function updateData(handler::OnlineRecoHandler, data)
  @atomic handler.ready = false
  @idle_add_guarded begin
    try
      #updateData(handler.dataWidget, data, handler.deltaT)
      execute_(handler.onlineRecoWidget, data, handler.dataWidget)
    finally
      @atomic handler.ready = true
    end
  end
end