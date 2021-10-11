export ProtocolSelectionDialog

mutable struct ProtocolSelectionDialog <: Gtk.GtkDialog
  handle::Ptr{Gtk.GObject}
  store
  tmSorted
  tv
  selection
  box::Box
  canvas
  scanner::MPIScanner
  protocols::Vector{String}
  updating::Bool
end


function ProtocolSelectionDialog(scanner::MPIScanner, params::Dict)

  dialog = Dialog("Select Protocol", mpilab[]["mainWindow"], GtkDialogFlags.MODAL,
                        Dict("gtk-cancel" => GtkResponseType.CANCEL,
                             "gtk-ok"=> GtkResponseType.ACCEPT) )

  resize!(dialog, 1024, 600)
  box = G_.content_area(dialog)

  store = ListStore(String, String, String, String)

  tv = TreeView(TreeModel(store))
  r1 = CellRendererText()
  r2 = CellRendererToggle()

  c0 = TreeViewColumn("Name", r1, Dict("text" => 0))
  c1 = TreeViewColumn("Type", r1, Dict("text" => 1))
  c2 = TreeViewColumn("Description", r1, Dict("text" => 2))

  for (i,c) in enumerate((c0,c1,c2))
    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,80)
    push!(tv,c)
  end

  G_.max_width(c0,300)
  G_.max_width(c1,200)
  G_.max_width(c2,200)
  G_.max_width(c3,200)
  G_.max_width(c4,200)

  tmFiltered = TreeModelFilter(store)
  G_.visible_column(tmFiltered,6)
  tmSorted = TreeModelSort(tmFiltered)
  G_.model(tv, tmSorted)

  G_.sort_column_id(TreeSortable(tmSorted),0,GtkSortType.DESCENDING)
  selection = G_.selection(tv)

  sw = ScrolledWindow()
  push!(sw, tv)
  push!(box, sw)
  set_gtk_property!(box, :expand, sw, true)

  canvas = Canvas()
  push!(box,canvas)
  set_gtk_property!(box,:expand, canvas, true)

  protocols = getProtocolList(scanner)

  dlg = ProtocolSelectionDialog(dialog.handle, store, tmSorted, tv, selection, 
                                box, canvas, scanner, protocols, false)

  updateData!(dlg)

  showall(tv)
  showall(box)

  Gtk.gobject_move_ref(dlg, dialog)

  return dlg
end

function updateData!(m::ProtocolSelectionDialog)

  @idle_add begin
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)

      for protoName in m.protocols
        p = Protocol(protoName, m.scanner)
        
        push!(m.store, (protoName, string(typeof(p), MPIMeasurements.description(p))))
      end
      m.updating = false
  end
end


function getSelectedProtocol(dlg::ProtocolSelectionDialog)
  currentItTM = selected(dlg.selection)
  protocol =  TreeModel(dlg.tmSorted)[currentItTM,1]
  return protocol
end
