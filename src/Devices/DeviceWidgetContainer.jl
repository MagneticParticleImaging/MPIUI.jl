mutable struct DeviceWidgetContainer <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  updating::Bool
  embedded::Bool
  deviceWindow::Gtk.GtkWindow
  deviceWidget::Gtk.GtkContainer
end


getindex(m::DeviceWidgetContainer, w::AbstractString) = G_.object(m.builder, w)


function DeviceWidgetContainer(deviceName::String, deviceWidget)
  uifile = joinpath(@__DIR__, "..", "builder", "deviceWidgetContainer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxContainer")

  window = GtkWindow(deviceName, 800, 600)
  # Hide close button until I figure out how to prevent destroy related segfaults
  set_gtk_property!(window, :deletable, false)
  visible(window, false)

  m = DeviceWidgetContainer(mainBox.handle, b, false, true, window, deviceWidget)
  
  set_gtk_property!(m["lblDeviceName"], :label, deviceName)
  push!(m["boxDeviceWidget"], deviceWidget)
  set_gtk_property!(m["boxDeviceWidget"], :expand, deviceWidget, true)
  showall(m)

  initCallbacks(m)
  
  return m
end

function initCallbacks(m::DeviceWidgetContainer)
  
  signal_connect(m["btnPopout"], :toggled) do w
    @idle_add if !m.updating
      m.updating = true

      try
        popout!(m, get_gtk_property(w, :active, Bool))
      catch ex
        showError(ex)
      end

      m.updating = false
    end
  end

  #signal_connect(m.deviceWindow, :destroy) do w
  #  @idle_add begin
  #    empty!(m["boxDeviceWidget"])
  #    push!(m["boxDeviceWidget"], m.deviceWidget)
  #    showall(m)
  #    #   set_gtk_property!(m["btnPopout"], :active, false)
  #  end
  #end

end

function popout!(m::DeviceWidgetContainer, popout::Bool)
  empty!(m.deviceWindow)
  empty!(m["boxDeviceWidget"])
  if popout
    push!(m.deviceWindow, m.deviceWidget)
    push!(m["boxDeviceWidget"], GtkLabel("Device Widget is opened in Pop-out Window"))
    visible(m.deviceWindow, true)
    showall(m.deviceWindow)
  else
    push!(m["boxDeviceWidget"], m.deviceWidget)
    visible(m.deviceWindow, false)
  end
  showall(m)
end