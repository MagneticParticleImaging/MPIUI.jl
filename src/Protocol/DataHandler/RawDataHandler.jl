include("StorageParameter.jl")

mutable struct RawDataHandler <: AbstractDataHandler
  dataWidget::RawDataWidget
  params::StorageParameter
  @atomic enabled::Bool
  @atomic ready::Bool
  # Protocol
  deltaT::Float64
end

function RawDataHandler(scanner=nothing)
  data = RawDataWidget()
  # Init Display Widget
  updateData(data, ones(Float32,10,1,1,1), 1.0)
  return RawDataHandler(data, StorageParameter(scanner), true, true, 0)
end

#for prot in [:RobotMPIMeasurementProtocol, :MPIMeasurementProtocol, :ContinousMeasurementProtocol, :RobotBasedSystemMatrixProtocol]
#  @eval begin 
    function init(handler::RawDataHandler, protocol::Protocol)
      seq = protocol.params.sequence
      handler.deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
    end 
#  end
#end

isMeasurementStore(handler::RawDataHandler, d::DatasetStore) = handler.params.mdfstore.path == d.path

function updateStudy(handler::AbstractDataHandler, name::String, date::DateTime)
  handler.params.currStudyName = name
  handler.params.currStudyDate = date
end

function isready(handler::RawDataHandler)
  ready = @atomic handler.ready
  enabled = @atomic handler.enabled
  return ready && enabled
end
enable!(handler::RawDataHandler, val::Bool) = @atomic handler.enabled = val
getParameterTitle(handler::RawDataHandler) = "Raw Data"
getParameterWidget(handler::RawDataHandler) = handler.params
getDisplayTitle(handler::RawDataHandler) = "Raw Data"
getDisplayWidget(handler::RawDataHandler) = handler.dataWidget

function handleProgress(handler::RawDataHandler, protocol::RobotMPIMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new frame $(event.done)"
  return DataQueryEvent("FRAME:$(event.done)")
end
function handleProgress(handler::RawDataHandler, protocol::MPIMeasurementProtocol, event::ProgressEvent)
  @debug "Asking for new frame $(event.done)"
  return DataQueryEvent("FRAME:$(event.done)")
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

function handleStorage(handler::RawDataHandler, protocol::Protocol, event::StorageSuccessEvent)
  @info "Received storage success event"
  updateData(handler.dataWidget, event.filename)
  updateExperimentStore(mpilab[], mpilab[].currentStudy)
end

updateData(handler::RawDataHandler, data::Nothing) = nothing

function updateData(handler::RawDataHandler, data)
  @atomic handler.ready = false
  @idle_add_guarded begin
    try
      updateData(handler.dataWidget, data, handler.deltaT)
    finally
      @atomic handler.ready = true
    end
  end
end