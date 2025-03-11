mutable struct FieldCameraWidget{C <: AbstractFieldCamera} <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  camera::C
  button
  tDes
  vars
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
  vars = @polyvar x y z
  corr = MPIMeasurements.translation(camera)
  field = getXYZValues(camera)
  coeffs, _, _ = magneticField(tDes, field, vars...)
  coeffs_MF = MPIUI.MagneticFieldCoefficients(coeffs, radius, center)

  viewer = MagneticFieldViewerWidget()
  push!(box, viewer)
  
  widget = FieldCameraWidget(box.handle, camera, button, tDes, vars, coeffs_MF, viewer, nothing)

  Gtk4.GLib.gobject_move_ref(widget, box)

  signal_connect(button, :toggled) do w
    if get_gtk_property(m["tbStartTemp"], :active, Bool)
      startCamera(m)
    else
      stopCamera(m)
    end
  end

end

function startCamera(m::FieldCameraWidget)
  m.timer = Timer(timer -> updateCamera(timer, m), 0.0, interval=0.1)
end

@guarded function updateSensor(timer::Timer, m::FieldCameraWidget)
  field = getXYZValues(camera)
  coeffs, _, _ = magneticField(m.tDes, field, m.vars...)
  m.coeffs = MPIUI.MagneticFieldCoefficients(coeffs, m.tDes.radius, m.tDes.center)
  updateData!(m.viewer, m.coeffs)
end

function stopCamera(m::FieldCameraWidget)
  if m.timer != nothing
      close(m.timer)
      m.timer = nothing
  end
end