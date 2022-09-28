abstract type AbstractDataHandler end

# Prepare fields based on upcoming protocol and its parameters
init(handler::AbstractDataHandler, protocol::Protocol) = nothing
isMeasurementStore(handler::AbstractDataHandler, d::DatasetStore) = true
isready(handler::AbstractDataHandler) = false
updateStudy(handler::AbstractDataHandler, name, date) = nothing
function enable!(handler::AbstractDataHandler, val::Bool)
  # NOP
end
getParameterTitle(handler::AbstractDataHandler) = "N/A"
getParameterWidget(handler::AbstractDataHandler) = Gtk.Grid()
getDisplayTitle(handler::AbstractDataHandler) = "N/A"
getDisplayWidget(handler::AbstractDataHandler) = Gtk.Box()
function updateData(handler::AbstractDataHandler, data::Nothing)
  # NOP
end

# Ask for data, which is given in updateData (alternative directly get data event)
handleProgress(handler::AbstractDataHandler, protocol::Protocol, event::ProgressEvent) = nothing
# Ask for something before protocol finishes, such a storage request
handleFinished(handler::AbstractDataHandler, protocol::Protocol) = nothing
# Ask for something in response to a successful storage request
handleStorage(handler::AbstractDataHandler, protocol::Protocol, event::StorageSuccessEvent) = nothing

include("ParamExpander.jl")
include("RawDataHandler.jl")
include("SpectrogramHandler.jl")
include("OnlineRecoHandler.jl")