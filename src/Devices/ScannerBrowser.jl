
include("RobotWidget.jl")
include("SurveillanceWidget.jl")
include("DAQWidget.jl")
include("TemperatureSensorWidget.jl")
include("DeviceWidgetContainer.jl")
include("TemperatureControlWidget.jl")

mutable struct ScannerBrowser <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  store
  tmSorted
  tv
  selection
  updating
  deviceBox
  scanner
  widgetCache::Dict{Device, DeviceWidgetContainer}
end

getindex(m::ScannerBrowser, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)

function ScannerBrowser(scanner, deviceBox)
  @info "Starting ScannerBrowser"
  uifile = joinpath(@__DIR__,"..", "builder","scannerBrowser.ui")

  b = GtkBuilder(filename=uifile)
  mainBox = Gtk4.G_.get_object(b, "boxScannerBrowser")

  # IsPresent/Online Icon, Device ID, Device Type, IsPresent value, Visible
  store = GtkListStore(String,String,String, Bool, Bool)

  tv = GtkTreeView(GtkTreeModel(store))
  r0 = GtkCellRendererPixbuf()
  r1 = GtkCellRendererText()
  r2 = GtkCellRendererToggle()

  c0 = GtkTreeViewColumn("Status", r0, Dict("text" => 0))  #Dict("stock-id" => 0))
  c1 = GtkTreeViewColumn("DeviceID", r1, Dict("text" => 1))
  c2 = GtkTreeViewColumn("Type", r1, Dict("text" => 2))

  for (i,c) in enumerate((c0, c1, c2))
    G_.set_sort_column_id(c,i-1)
    G_.set_resizable(c,true)
    G_.set_max_width(c,80)
    push!(tv,c)
  end

  G_.set_max_width(c0,300)
  G_.set_max_width(c1,300)
  G_.set_max_width(c2, 60)

  tmFiltered = GtkTreeModelFilter(store)
  G_.set_visible_column(tmFiltered,4)
  tmSorted = GtkTreeModelSort(tmFiltered)
  G_.set_model(tv, tmSorted)

  G_.set_sort_column_id(GtkTreeSortable(tmSorted),0,GtkSortType.DESCENDING)
  selection = G_.get_selection(tv)

  sw = GtkScrolledWindow()
  push!(sw, tv)
  push!(mainBox, sw)
  set_gtk_property!(mainBox, :expand, sw, true)

  # TODO Add widget that shows properties of selected Device

  m = ScannerBrowser(mainBox.handle, b, store, tmSorted, tv, selection, false, deviceBox, scanner, Dict{Device, Gtk4.GtkContainer}())
  Gtk4.GLib.gobject_move_ref(m, mainBox)

  set_gtk_property!(m["lblScannerName"], :label, name(scanner))

  updateData!(m, scanner)

  show(tv)
  show(m)

  initCallbacks(m)

  @info "Finished starting ScannerBrowser"
  return m
end

function initCallbacks(m::ScannerBrowser)

  signal_connect(m.selection, "changed") do widget
    @idle_add_guarded if !m.updating && hasselection(m.selection) 
      m.updating = true
      currentIt = selected( m.selection )

      name = GtkTreeModel(m.tmSorted)[currentIt,2]
      # Remove all currently loaded widgets
      empty!(m.deviceBox)
      dev = m.scanner.devices[name]
      if MPIMeasurements.isPresent(dev)
        displayDeviceWidget(m, dev)
      else
        info_dialog("Device $name is not availalbe.", mpilab[]["mainWindow"])
      end

      show(m.deviceBox)
      m.updating = false
    end
  end

  signal_connect(m["btnReloadScanner"], :clicked) do w
    try
      refreshScanner(m)
      info_dialog("Scanner has been reloaded successfully!", mpilab[]["mainWindow"])
    catch ex
      showError(ex)
    end
  end

end

function showDeviceWidget(m::ScannerBrowser, widget)
  push!(m.deviceBox, widget)
  set_gtk_property!(m.deviceBox, :expand, widget, true)
  show(widget)
end
function getDeviceWidget(m::ScannerBrowser, dev::Device, widgetType) #::Type{<:Gtk4.GtkObject})
  if haskey(m.widgetCache, dev)
    return m.widgetCache[dev]
  else
    deviceWidget = widgetType(dev)
    widget = DeviceWidgetContainer(deviceID(dev), deviceWidget)
    m.widgetCache[dev] = widget
    return widget
  end
end
function displayDeviceWidget(m::ScannerBrowser, dev::Device)
  info_dialog("Device $(typeof(dev)) not yet implemented.", mpilab[]["mainWindow"])
end
displayDeviceWidget(m::ScannerBrowser, dev::Robot) = showDeviceWidget(m, getDeviceWidget(m, dev, RobotWidget))
displayDeviceWidget(m::ScannerBrowser, dev::AbstractDAQ) = showDeviceWidget(m, getDeviceWidget(m, dev, DAQWidget))
displayDeviceWidget(m::ScannerBrowser, dev::SurveillanceUnit) = showDeviceWidget(m, getDeviceWidget(m, dev, SurveillanceWidget))
displayDeviceWidget(m::ScannerBrowser, dev::TemperatureSensor) = showDeviceWidget(m, getDeviceWidget(m, dev, TemperatureSensorWidget))
displayDeviceWidget(m::ScannerBrowser, dev::TemperatureController) = showDeviceWidget(m, getDeviceWidget(m, dev, TemperatureControllerWidget))



function updateData!(m::ScannerBrowser, scanner=nothing)
  if scanner != nothing

    @idle_add_guarded begin
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)
      for (deviceID, device) in scanner.devices
        present = MPIMeasurements.isPresent(device)
        icon = present ? "gtk-ok" : "gtk-dialog-error"
        push!(m.store, (icon, deviceID, string(typeof(device)), present, true))
      end

      m.updating = false
  end

  end
end

function refreshScanner(m::ScannerBrowser)
  message = """This will reload the current Scanner.toml. \n
  Please make sure that no protocol or device widget is currently communicating as otherwise undefined states can occur.
  Press \"Ok\" if you if you are sure.
  """
  if ask_dialog(message, "Cancel", "Ok", mpilab[]["mainWindow"])
    tempName = name(m.scanner)
    close(m.scanner)
    updateScanner!(mpilab[], MPIScanner(tempName, robust = true))
  end
end

function updateScanner!(m::ScannerBrowser, scanner::MPIScanner)
  m.scanner = scanner
  updateData!(m, m.scanner)
  @idle_add_guarded begin
    for container in values(m.widgetCache)
      popout!(container, false)
    end
    empty!(m.deviceBox)
    m.widgetCache = Dict{Device, Gtk4.GtkContainer}()
  end
end
