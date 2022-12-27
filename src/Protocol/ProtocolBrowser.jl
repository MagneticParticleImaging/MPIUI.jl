export ProtocolSelectionDialog

mutable struct ProtocolSelectionDialog <: Gtk4.GtkDialog
  handle::Ptr{Gtk4.GObject}
  store
  tmSorted
  tv
  selection
  box::Gtk4.GtkBoxLeaf
  scanner::MPIScanner
  protocols::Vector{String}
  updating::Bool
end


function ProtocolSelectionDialog(scanner::MPIScanner, params::Dict)

  dialog = Dialog("Select Protocol", mpilab[]["mainWindow"], Gtk4.DialogFlags_MODAL,
                        Dict("gtk-cancel" => Gtk4.ResponseType_CANCEL,
                             "gtk-ok"=> Gtk4.ResponseType_ACCEPT) )

  resize!(dialog, 1024, 600)
  box = G_.content_area(dialog)

  store = GtkListStore(String, String, String, Bool)

  tv = GtkTreeView(GtkTreeModel(store))
  r1 = GtkCellRendererText()
  r2 = GtkCellRendererToggle()

  c0 = GtkTreeViewColumn("Name", r1, Dict("text" => 0))
  c1 = GtkTreeViewColumn("Type", r1, Dict("text" => 1))
  c2 = GtkTreeViewColumn("Description", r1, Dict("text" => 2))

  for (i,c) in enumerate((c0,c1,c2))
    G_.set_sort_column_id(c,i-1)
    G_.set_resizable(c,true)
    G_.set_max_width(c,80)
    push!(tv,c)
  end
  @info "Pushed tv columns"

  G_.set_max_width(c0,300)
  G_.set_max_width(c1,200)
  G_.set_max_width(c2,200)

  tmFiltered = GtkTreeModelFilter(store)
  G_.set_visible_column(tmFiltered,3)
  tmSorted = GtkTreeModelSort(tmFiltered)
  G_.set_model(tv, tmSorted)

  G_.set_sort_column_id(GtkTreeSortable(tmSorted),0,GtkSortType.DESCENDING)
  selection = G_.get_selection(tv)

  sw = GtkScrolledWindow()
  push!(sw, tv)
  push!(box, sw)
  set_gtk_property!(box, :expand, sw, true)
  @info "Set to box"

  protocols = getProtocolList(scanner)
  @info "Got $(length(protocols)) protocols"

  dlg = ProtocolSelectionDialog(dialog.handle, store, tmSorted, tv, selection, 
                                box, scanner, protocols, false)

  updateData!(dlg)

  show(tv)
  show(box)

  Gtk4.GLib.gobject_move_ref(dlg, dialog)

  return dlg
end

function updateData!(m::ProtocolSelectionDialog)

  @idle_add_guarded begin
      @info "Update protocol store"
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)

      for protoName in m.protocols
        p = Protocol(protoName, m.scanner)
        
        push!(m.store, (protoName, string(typeof(p)), MPIMeasurements.description(p), true))
        @info "Pushed value"
      end
      m.updating = false
  end
end


function getSelectedProtocol(dlg::ProtocolSelectionDialog)
  currentItTM = selected(dlg.selection)
  protocol =  GtkTreeModel(dlg.tmSorted)[currentItTM,1]
  return protocol
end
