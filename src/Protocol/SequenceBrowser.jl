export SequenceSelectionDialog

mutable struct SequenceSelectionDialog <: Gtk4.GtkDialog
  handle::Ptr{Gtk4.GObject}
  store
  tmSorted
  tv
  selection
  box::Gtk4.GtkBoxLeaf
  canvas
  scanner::MPIScanner
  sequences::Vector{String}
  updating::Bool
end


function SequenceSelectionDialog(scanner::MPIScanner, params::Dict)

  dialog = Dialog("Select Sequence", mpilab[]["mainWindow"], Gtk4.DialogFlags_MODAL,
                        Dict("gtk-cancel" => Gtk4.ResponseType_CANCEL,
                             "gtk-ok"=> Gtk4.ResponseType_ACCEPT) )

  resize!(dialog, 1024, 600)
  box = G_.content_area(dialog)

  store = GtkListStore(String,Int,Int,Int,Float64,String,Bool)

  tv = GtkTreeView(GtkTreeModel(store))
  r1 = GtkCellRendererText()
  r2 = GtkCellRendererToggle()

  c0 = GtkTreeViewColumn("Name", r1, Dict("text" => 0))
  c1 = GtkTreeViewColumn("#Periods", r1, Dict("text" => 1))
  c2 = GtkTreeViewColumn("#Patches", r1, Dict("text" => 2))
  c3 = GtkTreeViewColumn("#PeriodsPerPatch", r1, Dict("text" => 3))
  c4 = GtkTreeViewColumn("FramePeriod", r1, Dict("text" => 4))
  c5 = GtkTreeViewColumn("DFStrength", r1, Dict("text" => 5))

  for (i,c) in enumerate((c0,c1,c2,c3,c4,c5))
    G_.set_sort_column_id(c,i-1)
    G_.set_resizable(c,true)
    G_.set_max_width(c,80)
    push!(tv,c)
  end

  G_.set_max_width(c0,300)
  G_.set_max_width(c1,200)
  G_.set_max_width(c2,200)
  G_.set_max_width(c3,200)
  G_.set_max_width(c4,200)

  tmFiltered = GtkTreeModelFilter(store)
  G_.set_visible_column(tmFiltered,6)
  tmSorted = GtkTreeModelSort(tmFiltered)
  G_.set_model(tv, tmSorted)

  G_.set_sort_column_id(GtkTreeSortable(tmSorted),0,GtkSortType.DESCENDING)
  selection = G_.get_selection(tv)

  sw = GtkScrolledWindow()
  push!(sw, tv)
  push!(box, sw)
  set_gtk_property!(box, :expand, sw, true)

  canvas = GtkCanvas()
  push!(box,canvas)
  set_gtk_property!(box,:expand, canvas, true)

  sequences = getSequenceList(scanner)

  dlg = SequenceSelectionDialog(dialog.handle, store, tmSorted, tv, selection, 
                                box, canvas, scanner, sequences, false)

  updateData!(dlg)

  show(tv)
  show(box)

  Gtk4.GLib.gobject_move_ref(dlg, dialog)

  signal_connect(selection, "changed") do widget
    if hasselection(selection)
      currentIt = selected(selection)

      seq = GtkTreeModel(tmSorted)[currentIt,1]

      @idle_add_guarded begin
        s = Sequence(scanner, seq)

        p = Winston.FramedPlot(xlabel="time / s", ylabel="field / ???")
        
        t = (1:acqNumPatches(s)) .* (acqNumPeriodsPerFrame(s) * ustrip(dfCycle(s)) / acqNumPatches(s)) 

        channels = acyclicElectricalTxChannels(s)
        colors = ["blue","green","red", "magenta", "cyan", "black", "gray"]
        for i=1:length(channels)
          Winston.add(p, Winston.Curve(t, ustrip.(MPIMeasurements.values(channels[i])), color=colors[i], linewidth=4))
        end
        display(canvas, p)

      end

    end
    return
  end

  return dlg
end

function updateData!(m::SequenceSelectionDialog)

  @idle_add_guarded begin
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)

      for seq in m.sequences
        s = Sequence(m.scanner, seq)
        
        time = ustrip(dfCycle(s)) * acqNumPeriodsPerFrame(s)
        dfString = *([ string(x*1e3," x ") for x in diag(ustrip.(dfStrength(s)[1,:,:])) ]...)[1:end-3]
        @info (acqNumPeriodsPerFrame(s), acqNumPatches(s), acqNumPeriodsPerPatch(s), time, true)
        push!(m.store, (seq, acqNumPeriodsPerFrame(s), acqNumPatches(s), acqNumPeriodsPerPatch(s), time, dfString, true))
      end
      m.updating = false
  end
end


function getSelectedSequence(dlg::SequenceSelectionDialog)
  currentItTM = selected(dlg.selection)
  sequence =  GtkTreeModel(dlg.tmSorted)[currentItTM,1]
  return sequence
end
