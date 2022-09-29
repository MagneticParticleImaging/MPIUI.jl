
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

  # Init Display Widget (warmstart)
  c = ones(Float32,1,3,3,3,1)
  c = makeAxisArray(c, [0.1,0.1,0.1], zeros(3), 1.0) 
  updateData!(dataWidget, ImageMeta(c))

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
  return DataQueryEvent("FG")
end

function handleData(handler::OnlineRecoHandler, protocol::Protocol, event::DataAnswerEvent)
  data = event.data
  if isnothing(data)
    return nothing
  end
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