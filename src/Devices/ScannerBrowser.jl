
mutable struct ScannerBrowser <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  store
  tmSorted
  tv
  selection
  updating
end

getindex(m::ScannerBrowser, w::AbstractString) = G_.object(m.builder, w)

function ScannerBrowser(scanner=nothing)
  @info "Starting ScannerBrowser"
  #uifile = joinpath(@__DIR__,"builder","rawDataViewer.ui")

  #b = Builder(filename=uifile)
  #mainBox = G_.object(b, "boxRawViewer")
  mainBox = Box(:v)

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

  m = ScannerBrowser(mainBox.handle, store, tmSorted, tv, selection, false)
  Gtk.gobject_move_ref(m, mainBox)

  updateData!(m, scanner)

  showall(tv)
  showall(m)

  @info "Finished starting ScannerBrowser"
  return m
end

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



