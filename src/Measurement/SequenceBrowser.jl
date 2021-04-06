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







#=function getSelectedSF(dlg::SFSelectionDialog)
  currentItTM = selected(dlg.selection)
  sffilename =  TreeModel(dlg.tmSorted)[currentItTM,10]
  return sffilename
end





mutable struct SFBrowserWidget
  store
  tv
  box
  tmSorted
  selection
  updating
end

function updateData!(m::SFBrowserWidget, sysFuncs)

  m.sysFuncs = sysFuncs

  @idle_add begin
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)

      for l = 2:size(sysFuncs,1)

        num = size(sysFuncs,2) == 16 ? 0 : sysFuncs[l,17]

        push!(m.store,( num, split(sysFuncs[l,15],"T")[1],
                sysFuncs[l,1],round(sysFuncs[l,2], digits=2),
               "$(round((sysFuncs[l,3]), digits=2)) x $(round((sysFuncs[l,4]), digits=2)) x $(round((sysFuncs[l,5]), digits=2))",
                                  "$(sysFuncs[l,6]) x $(sysFuncs[l,7]) x $(sysFuncs[l,8])",
                                  sysFuncs[l,10],sysFuncs[l,11],sysFuncs[l,12],sysFuncs[l,14], true))
      end
      m.updating = false
  end
end


function SFBrowserWidget(smallWidth=false; gradient = nothing, driveField = nothing)

 #Name,Gradient,DFx,DFy,DFz,Size x,Size y,Size z,Bandwidth,Tracer,TracerBatch,DeltaSampleConcentration,DeltaSampleVolume,Path


  store = ListStore(Int,String,String,Float64,String,String,
                     String,String,String,String, Bool)

  tv = TreeView(TreeModel(store))
  r1 = CellRendererText()
  r2 = CellRendererToggle()

  if !smallWidth
    c0 = TreeViewColumn("Num", r1, Dict("text" => 0))
    c1 = TreeViewColumn("Date", r1, Dict("text" => 1))
    c2 = TreeViewColumn("Name", r1, Dict("text" => 2))
    c3 = TreeViewColumn("Gradient", r1, Dict("text" => 3))
    c4 = TreeViewColumn("DF", r1, Dict("text" => 4))
    c5 = TreeViewColumn("Size", r1, Dict("text" => 5))
    c6 = TreeViewColumn("Tracer", r1, Dict("text" => 6))
    c7 = TreeViewColumn("Batch", r1, Dict("text" => 7))
    c8 = TreeViewColumn("Conc.", r1, Dict("text" => 8))
    c9 = TreeViewColumn("Path", r1, Dict("text" => 9))

    for (i,c) in enumerate((c0,c1,c2,c3,c4,c5,c6,c7,c8,c9))
      G_.sort_column_id(c,i-1)
      G_.resizable(c,true)
      G_.max_width(c,80)
      push!(tv,c)
    end
  else
    c0 = TreeViewColumn("Num", r1, Dict("text" => 0))
    c1 = TreeViewColumn("Date", r1, Dict("text" => 1))
    c2 = TreeViewColumn("Name", r1, Dict("text" => 2))
    c3 = TreeViewColumn("Path", r1, Dict("text" => 9))

    for (i,c) in enumerate((c0,c1,c2,c3))
      G_.sort_column_id(c,i-1)
      G_.resizable(c,true)
      G_.max_width(c,80)
      push!(tv,c)
    end
  end
  G_.max_width(c1,200)
  G_.max_width(c2,200)

  tmFiltered = TreeModelFilter(store)
  G_.visible_column(tmFiltered,10)
  tmSorted = TreeModelSort(tmFiltered)
  G_.model(tv, tmSorted)

  G_.sort_column_id(TreeSortable(tmSorted),0,GtkSortType.DESCENDING)

  selection = G_.selection(tv)

  cbOpenMeas = CheckButton("Open as Meas")
  cbOpenInWindow = CheckButton("Open in Window")

  signal_connect(tv, "row-activated") do treeview, path, col, other...
    if hasselection(selection)
      currentIt = selected(selection)

      sffilename = TreeModel(tmSorted)[currentIt,10]

      @idle_add begin
        if !get_gtk_property(cbOpenMeas,:active,Bool)
          if measIsCalibProcessed(MPIFile(sffilename,fastMode=true))
            if get_gtk_property(cbOpenInWindow,:active,Bool)
              SFViewer(sffilename)
            else
              updateData!(mpilab[].sfViewerWidget, sffilename)
              G_.current_page(mpilab[]["nbView"], 3)
            end
          else
            @show sffilename
            info_dialog("The calibration file $(sffilename) is not yet processed!", mpilab[]["mainWindow"])
          end
        else
          updateData(mpilab[].rawDataWidget, sffilename)
          G_.current_page(mpilab[]["nbView"], 0)
        end

      end

    end
    false
  end

  vbox = Box(:v)

  entGradient = Entry()
  entDF = Entry()
  entSize = Entry()
  entTracer = Entry()

  for ent in [entGradient,entDF,entSize,entTracer]
    set_gtk_property!(ent,:width_chars,11)
  end

  btnSFUpdate = Button("Update")
  btnSFConvert = Button("Convert")
  btnOpenCalibrationFolder = Button("Open File Browser")

  if smallWidth
    grid = Grid()
    push!(vbox, grid)
    #set_gtk_property!(vbox, :expand, grid, true)
    set_gtk_property!(grid, :row_spacing, 5)
    set_gtk_property!(grid, :column_spacing, 5)

    grid[1,1] = Label("Grad.")
    grid[2,1] = entGradient
    grid[1,2] = Label("DF Str.")
    grid[2,2] = entDF
    grid[3,1] = Label("Size")
    grid[4,1] = entSize
    grid[3,2] = Label("Tracer")
    grid[4,2] = entTracer
    grid[1:2,3] = cbOpenMeas
    grid[3:4,3] = btnSFUpdate
    grid[1:2,4] = cbOpenInWindow
    grid[3:4,4] = btnSFConvert
    grid[3:4,5] = btnOpenCalibrationFolder
  else
    hbox = Box(:h)
    push!(vbox, hbox)
    set_gtk_property!(hbox,:spacing,5)
    set_gtk_property!(hbox,:margin_left,5)
    set_gtk_property!(hbox,:margin_right,5)
    set_gtk_property!(hbox,:margin_top,5)
    set_gtk_property!(hbox,:margin_bottom,5)

    push!(hbox, Label("Gradient"))
    push!(hbox, entGradient)
    push!(hbox, Label("DF Strength"))
    push!(hbox, entDF)
    push!(hbox, Label("Size"))
    push!(hbox, entSize)
    push!(hbox, Label("Tracer"))
    push!(hbox, entTracer)
    push!(hbox, btnSFUpdate)
  end


  sw = ScrolledWindow()
  push!(sw, tv)
  push!(vbox, sw)
  set_gtk_property!(vbox, :expand, sw, true)
  showall(tv)
  showall(vbox)

  function updateSFDB(widget)
    if m.datasetStore != nothing
      MPIFiles.generateSFDatabase(m.datasetStore)
      updateData!(m, m.datasetStore)
    end
  end

  signal_connect(updateSFDB, btnSFUpdate, "clicked")

  function convSF(widget)
    if m.datasetStore != nothing && hasselection(m.selection)
      currentIt = selected( m.selection )
      filename = TreeModel(m.tmSorted)[currentIt,10]
      conversionDialog(m, filename)
    end
  end

  signal_connect(convSF, btnSFConvert, "clicked")

  signal_connect(btnOpenCalibrationFolder, "clicked") do widget
    @idle_add begin
        openFileBrowser(calibdir(m.datasetStore))
    end
  end

  function updateShownSF( widget )
    G = tryparse(Float64,get_gtk_property(entGradient,:text,String))
    s = split(get_gtk_property(entSize,:text,String),"x")
    s_ = Any[]
    if length(s) == 3
      s1 = tryparse(Int64,s[1])
      s2 = tryparse(Int64,s[2])
      s3 = tryparse(Int64,s[3])
      if s1 != nothing && s2 != nothing && s3 != nothing
        s_ = Int64[s1,s2,s3]
      end
    end
    df = split(get_gtk_property(entDF,:text,String),"x")
    df_ = Any[]
    if length(df) == 3
      dfx = tryparse(Float64,df[1])
      dfy = tryparse(Float64,df[2])
      dfz = tryparse(Float64,df[3])
      if dfx != nothing && dfy != nothing && dfz != nothing
        df_ = Float64[dfx,dfy,dfz]
      end
    end
    tracer = get_gtk_property(entTracer,:text,String)

    for l=1:length(store)
      showMe = true
      if G != nothing
        showMe = showMe && (G == store[l,4])
      end
      if length(df_) == 3
        showMe = showMe && ([parse(Float64,dv) for dv in split(store[l,5],"x")] == df_ )
      end
      if length(s_) == 3
        showMe = showMe && ([parse(Int64,sv) for sv in split(store[l,6],"x")] == s_ )
      end
      if length(tracer) > 0
        showMe = showMe && occursin(lowercase(tracer),lowercase(store[l,7]))
      end

      store[l,11] = showMe
    end
  end

  signal_connect(updateShownSF, entGradient, "changed")
  signal_connect(updateShownSF, entDF, "changed")
  signal_connect(updateShownSF, entSize, "changed")
  signal_connect(updateShownSF, entTracer, "changed")

  if gradient != nothing
    @idle_add set_gtk_property!(entGradient,:text,string(gradient))
  end

  if driveField != nothing
    driveField[:].*=1000
    str = join([string(df," x ") for df in driveField])[1:end-2]
    @idle_add set_gtk_property!(entDF, :text, str)
  end

  m = SFBrowserWidget(store, tv, vbox, tmSorted, nothing, nothing, selection, false)

  signal_connect(m.selection, "changed") do widget
    if hasselection(m.selection) && !m.updating
      @idle_add begin
        currentIt = selected( m.selection )
        filename = TreeModel(m.tmSorted)[currentIt,10]
        f = MPIFile(filename, fastMode=true)
        num = experimentNumber(f)
        name = experimentName(f)
        tname = tracerName(f)
        path1 = filepath(f)
        path2 = filename
        time = acqStartTime(f)
        numPeriods = acqNumPeriodsPerFrame(f)
        numAverages = acqNumAverages(f)
        sizeSF =  TreeModel(m.tmSorted)[currentIt,6]
        str =   """Num: $(num)\n
                Name: $(name)\n
                Tracer: $(tname)\n
                Path 1: $(path1)\n
                Path 2: $(path2)\n
                Time: $(time)\n
                Averages: $(numAverages)\n
                Periods: $(numPeriods)\n
                Size: $(sizeSF)"""
        set_gtk_property!(m.tv, :tooltip_text, str)
      end
    end
  end

  return m
end


=#