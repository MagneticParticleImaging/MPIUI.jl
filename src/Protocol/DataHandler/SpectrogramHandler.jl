
mutable struct SpectrogramHandler <: AbstractDataHandler
  dataWidget::SpectrogramWidget
  @atomic enabled::Bool
  @atomic ready::Bool
  # Protocol
  deltaT::Float64
  bgMeas::Array{Float32, 4}
  fgMeas::Array{Float32, 4}
  oldUnit::String
  paramsBox::Gtk4.GtkBoxLeaf
  cbRolling::Gtk4.GtkCheckButtonLeaf
end

function SpectrogramHandler(scanner=nothing)
  data = SpectrogramWidget()
  # Init Display Widget
  updateData(data, randn(Float32,10,1,1,1), 1.0)

  paramsBox = GtkBox(:v)
  cbRolling = GtkCheckButton("Rolling")
  push!(paramsBox, cbRolling)
  set_gtk_property!(cbRolling, :active, false)

  #signal_connect(cbRolling, :state_set) do w, state
  #  
  #  return false
  #end

  return SpectrogramHandler(data, true, true, 0, zeros(Float32,0,0,0,0), 
      zeros(Float32,0,0,0,0), "", paramsBox, cbRolling)
end

function init(handler::SpectrogramHandler, protocol::Protocol)
  seq = protocol.params.sequence
  handler.oldUnit = ""
  handler.deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
  handler.bgMeas = zeros(Float32,0,0,0,0)
  handler.fgMeas = zeros(Float32,0,0,0,0)
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
getDisplayTitle(handler::SpectrogramHandler) = "Spectrogram"
getDisplayWidget(handler::SpectrogramHandler) = handler.dataWidget
getParameterWidget(handler::SpectrogramHandler) = handler.paramsBox

function handleProgress(handler::SpectrogramHandler, protocol::Union{MPIMeasurementProtocol, RobotMPIMeasurementProtocol}, event::ProgressEvent)
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
function handleProgress(handler::SpectrogramHandler, protocol::ContinousMeasurementProtocol, event::ProgressEvent)
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

function handleStorage(handler::SpectrogramHandler, protocol::Protocol, event::StorageSuccessEvent, initiator::RawDataHandler)
  updateData(handler.dataWidget, event.filename)
end

function handleData(handler::SpectrogramHandler, protocol::Protocol, event::DataAnswerEvent)
  data = event.data
  if isnothing(data)
    return nothing
  end
  if event.query.message == "BG"
    handler.bgMeas = event.data
    handler.fgMeas = zeros(Float32,0,0,0,0)
    setBG(handler.dataWidget, handler.bgMeas)
  else 
    @atomic handler.ready = false
    @idle_add_guarded begin
      try
        if isempty(handler.fgMeas) || !get_gtk_property(handler.cbRolling, :active, Bool)
          handler.fgMeas = data
        else
          handler.fgMeas = cat(handler.fgMeas, data, dims=4)
        end
        updateData(handler.dataWidget, handler.fgMeas, handler.deltaT)
      finally
        @atomic handler.ready = true
      end
    end
  end
end