mutable struct MagneticFieldHandler <: AbstractDataHandler
  dataWidget::MagneticFieldViewerWidget
  storageParams::FileStorageParameter
  @atomic enabled::Bool
  @atomic ready::Bool
end 

function MagneticFieldHandler(scanner=nothing)
  data = MagneticFieldViewerWidget()
  return MagneticFieldHandler(data, FileStorageParameter("", "*.hd5"), true, true)
end

getStorageTitle(handler::MagneticFieldHandler) = "Magnetic Field"
getStorageWidget(handler::MagneticFieldHandler) = handler.storageParams
getParameterTitle(handler::MagneticFieldHandler) = "Magnetic Field"
getParameterWidget(handler::MagneticFieldHandler) = nothing
getDisplayTitle(handler::MagneticFieldHandler) = "Magnetic Field"
getDisplayWidget(handler::MagneticFieldHandler) = handler.dataWidget

# Ask for something before protocol finishes, such a storage request
function handleFinished(handler::MagneticFieldHandler, protocol::RobotBasedTDesignFieldProtocol)
  return FileStorageRequestEvent(filename(handler.storageParams))
end

# Ask for something in response to a successful storage request
function handleStorage(handler::MagneticFieldHandler, protocol::RobotBasedTDesignFieldProtocol, event::StorageSuccessEvent, initiator::MagneticFieldHandler)
  @info "Received storage success event"
  filename = event.filename
  field, radius, N, t, center, correction  = h5open(filename, "r") do file
    field = read(file,"/fields") 		# measured field (size: 3 x #points x #patches)
    radius = read(file,"/positions/tDesign/radius")	# radius of the measured ball
    N = read(file,"/positions/tDesign/N")		# number of points of the t-design
    t = read(file,"/positions/tDesign/t")		# t of the t-design
    center = read(file,"/positions/tDesign/center")	# center of the measured ball
    correction = read(file, "/sensor/correctionTranslation")
    return field, radius, N, t, center, correction
  end
  @polyvar x y z
  tDes = loadTDesign(Int(t),N,radius*u"m", center.*u"m")
  coeffs, expansion, func = magneticField(tDes, field, x,y,z)
  for c=1:size(coeffs,2), j = 1:3
    coeffs[j,c] = SphericalHarmonicExpansions.translation(coeffs[j,c], correction[:,j])
    #expansion[j,c] = sphericalHarmonicsExpansion(coeffs[j,c],x,y,z);
  end
  coeffs_MF = MPIUI.MagneticFieldCoefficients(coeffs, radius, center)
  MPIUI.write(filename, coeffs_MF)
  updateData!(handler.dataWidget, filename)
end