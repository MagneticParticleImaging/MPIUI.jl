
mutable struct OnlineRecoHandler <: AbstractDataHandler
  dataWidget::DataViewerWidget
  onlineRecoWidget::OnlineRecoWidget
  @atomic enabled::Bool
  @atomic ready::Bool
  # Protocol
  deltaT::Float64
  bgMeas::Array{Float32, 4}
  oldUnit::String
end

function OnlineRecoHandler(scanner=nothing)
  dataWidget = DataViewerWidget()
  onlineRecoWidget = OnlineRecoWidget(:test)

  # Init Display Widget (warmstart)
  c = ones(Float32,1,3,3,3,1)
  c = makeAxisArray(c, [0.1,0.1,0.1], zeros(3), 1.0) 
  updateData!(dataWidget, ImageMeta(c))

  return OnlineRecoHandler(dataWidget, onlineRecoWidget, true, true, 0, zeros(Float32,0,0,0,0), "")
end

function init(handler::OnlineRecoHandler, protocol::Protocol)
  seq = protocol.params.sequence
  handler.oldUnit = ""
  handler.deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
  handler.bgMeas = zeros(Float32,0,0,0,0)
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
        execute_(handler.onlineRecoWidget, data, handler.dataWidget)
      finally
        @atomic handler.ready = true
      end
    end
  end
end