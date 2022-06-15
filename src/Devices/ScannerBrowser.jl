
include("RobotWidget.jl")
include("SurveillanceWidget.jl")
include("DAQWidget.jl")
include("TemperatureSensorWidget.jl")
include("DeviceWidgetContainer.jl")

mutable struct ScannerBrowser <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
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

getindex(m::ScannerBrowser, w::AbstractString) = G_.object(m.builder, w)

function ScannerBrowser(scanner, deviceBox)
  @info "Starting ScannerBrowser"
  uifile = joinpath(@__DIR__,"..", "builder","scannerBrowser.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxScannerBrowser")

  # IsPresent/Online Icon, Device ID, Device Type, IsPresent value, Visible
  store = ListStore(String,String,String, Bool, Bool)

  tv = TreeView(TreeModel(store))
  r0 = CellRendererPixbuf()
  r1 = CellRendererText()
  r2 = CellRendererToggle()

  c0 = TreeViewColumn("Status", r0, Dict("stock-id" => 0))
  c1 = TreeViewColumn("DeviceID", r1, Dict("text" => 1))
  c2 = TreeViewColumn("Type", r1, Dict("text" => 2))

  for (i,c) in enumerate((c0, c1, c2))
    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,80)
    push!(tv,c)
  end

  G_.max_width(c0,300)
  G_.max_width(c1,300)
  G_.max_width(c2, 60)

  tmFiltered = TreeModelFilter(store)
  G_.visible_column(tmFiltered,4)
  tmSorted = TreeModelSort(tmFiltered)
  G_.model(tv, tmSorted)

  G_.sort_column_id(TreeSortable(tmSorted),0,GtkSortType.DESCENDING)
  selection = G_.selection(tv)

  sw = ScrolledWindow()
  push!(sw, tv)
  push!(mainBox, sw)
  set_gtk_property!(mainBox, :expand, sw, true)

  # TODO Add widget that shows properties of selected Device

  m = ScannerBrowser(mainBox.handle, b, store, tmSorted, tv, selection, false, deviceBox, scanner, Dict{Device, Gtk.GtkContainer}())
  Gtk.gobject_move_ref(m, mainBox)

  set_gtk_property!(m["lblScannerName"], :label, name(scanner))

  updateData!(m, scanner)

  showall(tv)
  showall(m)

  initCallbacks(m)

  @info "Finished starting ScannerBrowser"
  return m
end

function initCallbacks(m::ScannerBrowser)

  signal_connect(m.selection, "changed") do widget
    @idle_add_guarded if !m.updating && hasselection(m.selection) 
      m.updating = true
      currentIt = selected( m.selection )

      name = TreeModel(m.tmSorted)[currentIt,2]
      # Remove all currently loaded widgets
      empty!(m.deviceBox)
      dev = m.scanner.devices[name]
      if MPIMeasurements.isPresent(dev)
        displayDeviceWidget(m, dev)
      else
        info_dialog("Device $name is not availalbe.", mpilab[]["mainWindow"])
      end

      showall(m.deviceBox)
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
  showall(widget)
end
function getDeviceWidget(m::ScannerBrowser, dev::Device, widgetType::Type{<:Gtk.GtkContainer})
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
#displayDeviceWidget(m::ScannerBrowser, dev::SurveillanceUnit) = showDeviceWidget(m, getDeviceWidget(m, dev, SurveillanceWidget))
displayDeviceWidget(m::ScannerBrowser, dev::TemperatureSensor) = showDeviceWidget(m, getDeviceWidget(m, dev, TemperatureSensorWidget))



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
    m.widgetCache = Dict{Device, Gtk.GtkContainer}()
  end
end
