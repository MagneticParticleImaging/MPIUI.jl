export SequenceSelectionDialog

mutable struct SequenceSelectionDialog <: Gtk.GtkDialog
  handle::Ptr{Gtk.GObject}
  store
  tmSorted
  tv
  selection
  box::Box
  canvas
  scanner::MPIScanner
  sequences::Vector{String}
  updating::Bool
end


function SequenceSelectionDialog(scanner::MPIScanner, params::Dict)

  dialog = Dialog("Select Sequence", mpilab[]["mainWindow"], GtkDialogFlags.MODAL,
                        Dict("gtk-cancel" => GtkResponseType.CANCEL,
                             "gtk-ok"=> GtkResponseType.ACCEPT) )

  resize!(dialog, 1024, 600)
  box = G_.content_area(dialog)

  store = ListStore(String,Int,Int,Int,Float64,String,Bool)

  tv = TreeView(TreeModel(store))
  r1 = CellRendererText()
  r2 = CellRendererToggle()

  c0 = TreeViewColumn("Name", r1, Dict("text" => 0))
  c1 = TreeViewColumn("#Periods", r1, Dict("text" => 1))
  c2 = TreeViewColumn("#Patches", r1, Dict("text" => 2))
  c3 = TreeViewColumn("#PeriodsPerPatch", r1, Dict("text" => 3))
  c4 = TreeViewColumn("FramePeriod", r1, Dict("text" => 4))
  c5 = TreeViewColumn("DFStrength", r1, Dict("text" => 5))

  for (i,c) in enumerate((c0,c1,c2,c3,c4,c5))
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

  sequences = getSequenceList(scanner)

  dlg = SequenceSelectionDialog(dialog.handle, store, tmSorted, tv, selection, 
                                box, canvas, scanner, sequences, false)

  updateData!(dlg)

  showall(tv)
  showall(box)

  Gtk.gobject_move_ref(dlg, dialog)

  signal_connect(selection, "changed") do widget
    if hasselection(selection)
      currentIt = selected(selection)

      seq = TreeModel(tmSorted)[currentIt,1]

      @idle_add begin
        s = Sequence(scanner, seq)

        p = Winston.FramedPlot(xlabel="time / s", ylabel="field / ???")
        
        t = (1:acqNumPatches(s)) .* (acqNumPeriodsPerFrame(s) * ustrip(dfCycle(s)) / acqNumPatches(s)) 

        channels = acyclicElectricalTxChannels(s)
        colors = ["blue","green","red", "magenta", "cyan", "black", "gray"]
        for i=1:length(channels)
          Winston.add(p, Winston.Curve(t, ustrip.(MPIFiles.values(channels[i])), color=colors[i], linewidth=4))
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
  sequence =  TreeModel(dlg.tmSorted)[currentItTM,1]
  return sequence
end
