export SequenceSelectionDialog

mutable struct SequenceSelectionDialog <: Gtk.GtkDialog
  handle::Ptr{Gtk.GObject}
  store
  tmSorted
  tv
  selection
  box::Box
  canvas
  sequences::Vector{String}
  updating::Bool
end


function SequenceSelectionDialog(params::Dict)

  dialog = Dialog("Select Sequence", mpilab[]["mainWindow"], GtkDialogFlags.MODAL,
                        Dict("gtk-cancel" => GtkResponseType.CANCEL,
                             "gtk-ok"=> GtkResponseType.ACCEPT) )

  resize!(dialog, 1024, 600)
  box = G_.content_area(dialog)

  store = ListStore(String,Int,Int,Int,Bool)

  tv = TreeView(TreeModel(store))
  r1 = CellRendererText()
  r2 = CellRendererToggle()

  c0 = TreeViewColumn("Name", r1, Dict("text" => 0))
  c1 = TreeViewColumn("#Periods", r1, Dict("text" => 1))
  c2 = TreeViewColumn("#Patches", r1, Dict("text" => 2))
  c3 = TreeViewColumn("#PeriodsPerPatch", r1, Dict("text" => 3))

  for (i,c) in enumerate((c0,c1,c2,c3))
    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,80)
    push!(tv,c)
  end

  G_.max_width(c0,300)
  G_.max_width(c1,200)
  G_.max_width(c2,200)

  tmFiltered = TreeModelFilter(store)
  G_.visible_column(tmFiltered,4)
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

  sequences = sequenceList()

  dlg = SequenceSelectionDialog(dialog.handle, store, tmSorted, tv, selection, box, canvas, sequences, false)

  updateData!(dlg)

  showall(tv)
  showall(box)

  Gtk.gobject_move_ref(dlg, dialog)

  signal_connect(selection, "changed") do widget
    if hasselection(selection)
      currentIt = selected(selection)

      seq = TreeModel(tmSorted)[currentIt,1]

      @idle_add begin
        s = Sequence(seq)

        p = Winston.FramedPlot(xlabel="time / s", ylabel="field / ???")
        
        t = (1:acqNumPatches(s)) .* (acqNumPeriodsPerFrame(s) * params["dfCycle"] / acqNumPatches(s)) 

        colors = ["blue","green","red", "magenta", "cyan", "black", "gray"]
        for i=1:size(s.values,1)
          Winston.add(p, Winston.Curve(t, s.values[i,:], color=colors[i], linewidth=4))
        end
        display(canvas, p)

      end

    end
    return
  end

  return dlg
end

function updateData!(m::SequenceSelectionDialog)

  @idle_add begin
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)

      for seq in m.sequences
        s = Sequence(seq)

        push!(m.store, (seq, acqNumPeriodsPerFrame(s), acqNumPatches(s), acqNumPeriodsPerPatch(s), true))
      end
      m.updating = false
  end
end


function getSelectedSequence(dlg::SequenceSelectionDialog)
  currentItTM = selected(dlg.selection)
  sequence =  TreeModel(dlg.tmSorted)[currentItTM,1]
  return sequence
end
