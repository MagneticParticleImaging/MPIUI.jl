abstract type AbstractDataHandler end

# Prepare fields based on upcoming protocol and its parameters
init(handler::AbstractDataHandler, protocol::Protocol) = nothing
isMeasurementStore(handler::AbstractDataHandler, d::DatasetStore) = true
isready(handler::AbstractDataHandler) = false
updateStudy(handler::AbstractDataHandler, name, date) = nothing
function enable!(handler::AbstractDataHandler, val::Bool)
  # NOP
end
getStorageTitle(handler::AbstractDataHandler) = "N/A"
getStorageWidget(handler::AbstractDataHandler) = nothing
getParameterTitle(handler::AbstractDataHandler) = "N/A"
getParameterWidget(handler::AbstractDataHandler) = nothing
getDisplayTitle(handler::AbstractDataHandler) = "N/A"
getDisplayWidget(handler::AbstractDataHandler) = nothing

# Ask for data, which is given in updateData (alternative directly get data event)
handleProgress(handler::AbstractDataHandler, protocol::Protocol, event::ProgressEvent) = nothing
# Ask for something before protocol finishes, such a storage request
handleFinished(handler::AbstractDataHandler, protocol::Protocol) = nothing
# Ask for something in response to a successful storage request
handleStorage(handler::AbstractDataHandler, protocol::Protocol, event::StorageSuccessEvent, initiator::AbstractDataHandler) = nothing
# Receive Data requests
handleData(handler::AbstractDataHandler, protocol::Protocol, event::DataAnswerEvent) = nothing

measureBackground(handler::AbstractDataHandler, protocol::Protocol) = protocol.params.measureBackground
measureBackground(handler::AbstractDataHandler, protocol::RobotBasedSystemMatrixProtocol) = false # TODO Check bgMeas

include("ParamExpander.jl")
include("RawDataHandler.jl")
include("SpectrogramHandler.jl")
include("OnlineRecoHandler.jl")