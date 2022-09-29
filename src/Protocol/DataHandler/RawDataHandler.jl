include("StorageParameter.jl")

mutable struct RawDataHandler <: AbstractDataHandler
  dataWidget::RawDataWidget
  params::StorageParameter
  @atomic enabled::Bool
  @atomic ready::Bool
  # Protocol
  deltaT::Float64
  bgMeas::Array{Float32, 4}
  oldUnit::String
end

function RawDataHandler(scanner=nothing)
  data = RawDataWidget()
  # Init Display Widget
  updateData(data, ones(Float32,10,1,1,1), 1.0)
  return RawDataHandler(data, StorageParameter(scanner), true, true, 0, zeros(Float32,0,0,0,0), "")
end

function init(handler::RawDataHandler, protocol::Protocol)
  seq = protocol.params.sequence
  handler.oldUnit = ""
  handler.deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
  handler.bgMeas = zeros(Float32,0,0,0,0)
end 

isMeasurementStore(handler::RawDataHandler, d::DatasetStore) = handler.params.mdfstore.path == d.path

function updateStudy(handler::RawDataHandler, name::String, date::DateTime)
  handler.params.currStudyName = name
  handler.params.currStudyDate = date
end

function isready(handler::RawDataHandler)
  ready = @atomic handler.ready
  enabled = @atomic handler.enabled
  return ready && enabled
end
enable!(handler::RawDataHandler, val::Bool) = @atomic handler.enabled = val
getStorageTitle(handler::RawDataHandler) = "Raw Data"
getStorageWidget(handler::RawDataHandler) = handler.params
getParameterTitle(handler::RawDataHandler) = "Raw Data"
getParameterWidget(handler::RawDataHandler) = nothing
getDisplayTitle(handler::RawDataHandler) = "Raw Data"
getDisplayWidget(handler::RawDataHandler) = handler.dataWidget

function handleProgress(handler::RawDataHandler, protocol::Union{MPIMeasurementProtocol, RobotMPIMeasurementProtocol}, event::ProgressEvent)
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
function handleProgress(handler::RawDataHandler, protocol::ContinousMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new measurement $(event.done)"
  return DataQueryEvent("")
end
function handleProgress(handler::RawDataHandler, protocol::RobotBasedSystemMatrixProtocol, event::ProgressEvent)
  @debug "Asking for latest position"
  return DataQueryEvent("SIGNAL")
end

function handleFinished(handler::RawDataHandler, protocol::Protocol)
  request = DatasetStoreStorageRequestEvent(handler.params.mdfstore, getStorageMDF(handler.params))
  return request
end

# Atm we check initatior based on type, if multiple same-type widgets are supposed to be supported we'd need equality checks
function handleStorage(handler::RawDataHandler, protocol::Protocol, event::StorageSuccessEvent, initiator::RawDataHandler)
  @info "Received storage success event"
  updateData(handler.dataWidget, event.filename)
  updateExperimentStore(mpilab[], mpilab[].currentStudy)
end

updateData(handler::RawDataHandler, data::Nothing) = nothing

function handleData(handler::RawDataHandler, protocol::Protocol, event::DataAnswerEvent)
  data = event.data
  if isnothing(data)
    return nothing
  end
  if event.query.message == "BG"
    handler.bgMeas = event.data
    # TODO further process bgMeas
  else 
    @atomic handler.ready = false
    @idle_add_guarded begin
      try
        updateData(handler.dataWidget, data, handler.deltaT)
      finally
        @atomic handler.ready = true
      end
    end
  end
end