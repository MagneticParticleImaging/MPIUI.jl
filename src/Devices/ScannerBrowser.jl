
include("RobotWidget.jl")
include("SurveillanceWidget.jl")
include("DAQWidget.jl")
include("TemperatureSensorWidget.jl")

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
  widgetCache::Dict{Device, Gtk.GtkContainer}
end

getindex(m::ScannerBrowser, w::AbstractString) = G_.object(m.builder, w)

function ScannerBrowser(scanner, deviceBox)
  @info "Starting ScannerBrowser"
  uifile = joinpath(@__DIR__,"..", "builder","scannerBrowser.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxScannerBrowser")

  store = ListStore(String,String,Bool)

  tv = TreeView(TreeModel(store))
  r1 = CellRendererText()
  r2 = CellRendererToggle()

  c0 = TreeViewColumn("DeviceID", r1, Dict("text" => 0))
  c1 = TreeViewColumn("Type", r1, Dict("text" => 1))

  for (i,c) in enumerate((c0,c1))
    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,80)
    push!(tv,c)
  end

  G_.max_width(c0,300)
  G_.max_width(c1,300)

  tmFiltered = TreeModelFilter(store)
  G_.visible_column(tmFiltered,2)
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
    @idle_add if !m.updating && hasselection(m.selection) 
      m.updating = true
      currentIt = selected( m.selection )

      name = TreeModel(m.tmSorted)[currentIt,1]
      @info name

      # Remove all currently loaded widgets
      empty!(m.deviceBox)
      displayDeviceWidget(m, m.scanner.devices[name])

      showall(m.deviceBox)
      m.updating = false
    end
  end

  signal_connect(m["btnReloadScanner"], :clicked) do w
    try
      refreshScanner(m)
      ask_dialog("Scanner was sucessfully reloaded!", "Continue", mpilab[]["mainWindow"])
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
    widget = widgetType(dev)
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



function updateData!(m::ScannerBrowser, scanner=nothing)
  if scanner != nothing

    @idle_add begin
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)

      for (deviceID, device) in scanner.devices
        push!(m.store, (deviceID, string(typeof(device)), true))
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
    updateScanner!(mpilab[], MPIScanner(tempName))
  end
end

function updateScanner!(m::ScannerBrowser, scanner::MPIScanner)
  m.scanner = scanner
  updateData!(m, m.scanner)
  @idle_add begin 
    empty!(m.deviceBox)
    m.widgetCache = Dict{Device, Gtk.GtkContainer}()
  end
end
