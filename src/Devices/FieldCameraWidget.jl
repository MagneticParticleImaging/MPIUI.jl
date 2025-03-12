mutable struct FieldCameraWidget{C <: AbstractFieldCamera} <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  camera::C
  button
  tDes
  coeffs
  viewer::MagneticFieldViewerWidget
  timer::Union{Timer, Nothing}
end

function FieldCameraWidget(camera::AbstractFieldCamera)
  box = GtkBox(:v)
  toggle = GtkToggleButton("Enable")
  push!(box, toggle)

  t, N, center, radius = MPIMeasurements.tDesignParameter(camera)
  tDes = loadTDesign(Int(t),N,radius*u"m", center.*u"m")
  corr = MPIMeasurements.translation(camera)
  field = getXYZValues(camera)
  coeffs = MPISphericalHarmonics.magneticField(tDes, field)
  coeffs_MF = MPIUI.MagneticFieldCoefficients(coeffs, radius, center)

  viewer = MagneticFieldViewerWidget()
  push!(box, viewer)
  
  widget = FieldCameraWidget(box.handle, camera, toggle, tDes, coeffs_MF, viewer, nothing)

  Gtk4.GLib.gobject_move_ref(widget, box)

  signal_connect(toggle, :toggled) do w
    if get_gtk_property(toggle, :active, Bool)
      startCamera(widget)
    else
      stopCamera(widget)
    end
  end

  return widget
end

function startCamera(m::FieldCameraWidget)
  m.timer = Timer(timer -> updateCamera(timer, m), 0.0, interval=0.1)
end

@guarded function updateCamera(timer::Timer, m::FieldCameraWidget)
  field = getXYZValues(m.camera)
  mfTime = @elapsed coeffs = MPISphericalHarmonics.magneticField(m.tDes, field)
  mfcTime = @elapsed m.coeffs = MPIUI.MagneticFieldCoefficients(coeffs, ustrip(u"m", m.tDes.radius), ustrip.(u"m", m.tDes.center))
  plotTime = @elapsed updateData!(m.viewer, m.coeffs)
  @info "MagneticField $mfTime, FieldCoeff $mfcTime, Plot $plotTime"
end

function stopCamera(m::FieldCameraWidget)
  if m.timer != nothing
      close(m.timer)
      m.timer = nothing
  end
end