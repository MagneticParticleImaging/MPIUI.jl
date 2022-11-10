mutable struct MagneticFieldHandler <: AbstractDataHandler
  dataWidget::MagneticFieldViewerWidget
  storageParams::FileStorageParameter
  @atomic enabled::Bool
  @atomic ready::Bool
end 

function MagneticFieldHandler(scanner=nothing)
  data = MagneticFieldViewerWidget()
  return MagneticFieldHandler(data, FileStorageParameter("*.hd5"), true, true)
end

getStorageTitle(handler::MagneticFieldHandler) = "Magnetic Field"
getStorageWidget(handler::MagneticFieldHandler) = handler.storageParams
getParameterTitle(handler::MagneticFieldHandler) = "N/A"
getParameterWidget(handler::MagneticFieldHandler) = nothing
getDisplayTitle(handler::MagneticFieldHandler) = "Magnetic Field"
getDisplayWidget(handler::MagneticFieldHandler) = handler.dataWidget

# Ask for something before protocol finishes, such a storage request
function handleFinished(handler::MagneticFieldHandler, protocol::RobotBasedMagneticFieldStaticProtocol)
  return FileStorageRequestEvent(filename(handler.storageParams))
end

# Ask for something in response to a successful storage request
function handleStorage(handler::MagneticFieldHandler, protocol::RobotBasedMagneticFieldStaticProtocol, event::StorageSuccessEvent, initiator::MagneticFieldHandler)
  @info "Received storage success event"
  #TODO Probably require some pre-processing?
  updateData!(handler.dataWidget, event.filename)
end