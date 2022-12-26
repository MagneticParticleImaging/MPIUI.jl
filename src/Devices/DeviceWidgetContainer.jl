mutable struct DeviceWidgetContainer <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  updating::Bool
  embedded::Bool
  deviceWindow::Gtk4.GtkWindowLeaf
  deviceWidget# TODO ::Gtk4.GtkContainer
end


getindex(m::DeviceWidgetContainer, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)


function DeviceWidgetContainer(deviceName::String, deviceWidget)
  uifile = joinpath(@__DIR__, "..", "builder", "deviceWidgetContainer.ui")

  b = GtkBuilder(filename=uifile)
  mainBox = Gtk4.G_.get_object(b, "boxContainer")

  window = GtkWindow(deviceName, 800, 600)
  visible(window, false)

  m = DeviceWidgetContainer(mainBox.handle, b, false, true, window, deviceWidget)
  
  set_gtk_property!(m["lblDeviceName"], :label, deviceName)
  push!(m["boxDeviceWidget"], deviceWidget)
  set_gtk_property!(m["boxDeviceWidget"], :expand, deviceWidget, true)
  show(m)

  initCallbacks(m)
  
  return m
end

function initCallbacks(m::DeviceWidgetContainer)
  
  signal_connect(m["btnPopout"], :toggled) do w
    @idle_add_guarded if !m.updating
      m.updating = true

      try
        popout!(m, get_gtk_property(w, :active, Bool))
      catch ex
        showError(ex)
      end

      m.updating = false
    end
  end

  signal_connect(m.deviceWindow, "delete-event") do w, event
    @idle_add_guarded begin
      set_gtk_property!(m["btnPopout"], :active, false)
    end
    return true
  end

end

function popout!(m::DeviceWidgetContainer, popout::Bool)
  empty!(m.deviceWindow)
  empty!(m["boxDeviceWidget"])
  if popout
    push!(m.deviceWindow, m.deviceWidget)
    push!(m["boxDeviceWidget"], GtkLabel("Device Widget is opened in Pop-out Window"))
    visible(m.deviceWindow, true)
    show(m.deviceWindow)
  else
    push!(m["boxDeviceWidget"], m.deviceWidget)
    visible(m.deviceWindow, false)
  end
  show(m)
end