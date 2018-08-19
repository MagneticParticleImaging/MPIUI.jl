using Gtk.ShortNames, Gtk.GConstants

mutable struct SFBrowserWidget
  store
  tv
  box
  tmSorted
  sysFuncs
  datasetStore
end

function updateData!(m::SFBrowserWidget, d::DatasetStore)
  #generateSFDatabase(d)

  sysFuncs = loadSFDatabase(d)

  m.datasetStore = d

  if sysFuncs != nothing
    updateData!(m, sysFuncs)
  end
end

function updateData!(m::SFBrowserWidget, sysFuncs)

  m.sysFuncs = sysFuncs

  Gtk.@sigatom empty!(m.store)
  println(sysFuncs)

  for l = 2:size(sysFuncs,1)
    push!(m.store,( sysFuncs[l,15],
            sysFuncs[l,1],round(sysFuncs[l,2], digits=2),
           "$(round((sysFuncs[l,3]), digits=2)) x $(round((sysFuncs[l,4]), digits=2)) x $(round((sysFuncs[l,5]), digits=2))",
                              "$(sysFuncs[l,6]) x $(sysFuncs[l,7]) x $(sysFuncs[l,8])",
                              sysFuncs[l,10],sysFuncs[l,11],sysFuncs[l,12],sysFuncs[l,14], true))
  end
end


function SFBrowserWidget(smallWidth=false; gradient = nothing, driveField = nothing)

 #Name,Gradient,DFx,DFy,DFz,Size x,Size y,Size z,Bandwidth,Tracer,TracerBatch,DeltaSampleConcentration,DeltaSampleVolume,Path


  store = ListStore(String,String,Float64,String,String,
                     String,String,String,String, Bool)

  tv = TreeView(TreeModel(store))
  r1 = CellRendererText()
  r2 = CellRendererToggle()
  c1 = TreeViewColumn("Date", r1, Dict("text" => 0))
  c2 = TreeViewColumn("Name", r1, Dict("text" => 1))
  c3 = TreeViewColumn("Gradient", r1, Dict("text" => 2))
  c4 = TreeViewColumn("DF", r1, Dict("text" => 3))
  c5 = TreeViewColumn("Size", r1, Dict("text" => 4))
  c6 = TreeViewColumn("Tracer", r1, Dict("text" => 5))
  c7 = TreeViewColumn("Batch", r1, Dict("text" => 6))
  c8 = TreeViewColumn("Conc.", r1, Dict("text" => 7))
  c9 = TreeViewColumn("Path", r1, Dict("text" => 8))

  for (i,c) in enumerate((c1,c2,c3,c4,c5,c6,c7,c8,c9))
    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,80)
    push!(tv,c)
  end

  #G_.max_width(c0,20)
  G_.max_width(c1,200)
  G_.max_width(c2,200)

  selection = G_.selection(tv)

  tmFiltered = TreeModelFilter(store)
  G_.visible_column(tmFiltered,9)
  tmSorted = TreeModelSort(tmFiltered)
  G_.model(tv, tmSorted)

  G_.sort_column_id(TreeSortable(tmSorted),0,GtkSortType.DESCENDING)


  cbOpenMeas = CheckButton("Open as Meas")


  signal_connect(tv, "row-activated") do treeview, path, col, other...
    if hasselection(selection)
      currentIt = selected(selection)

      sffilename = TreeModel(tmSorted)[currentIt,9]

      Gtk.@sigatom begin
        if !get_gtk_property(cbOpenMeas,:active,Bool)
          updateData!(mpilab[].sfViewerWidget, sffilename)
          G_.current_page(mpilab[]["nbView"], 3)
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

  if smallWidth
    grid = Grid()
    push!(vbox, grid)
    #set_gtk_property!(vbox, :expand, grid, true)

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

  function updateSFDB( widget )
    if m.datasetStore != nothing
      MPIFiles.generateSFDatabase(m.datasetStore)
      updateData!(m, m.datasetStore)
    end
  end

  signal_connect(updateSFDB, btnSFUpdate, "clicked")

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
        showMe = showMe && (G == store[l,3])
      end
      if length(df_) == 3
        showMe = showMe && ([parse(Float64,dv) for dv in split(store[l,4],"x")] == df_ )
      end
      if length(s_) == 3
        showMe = showMe && ([parse(Int64,sv) for sv in split(store[l,5],"x")] == s_ )
      end
      if length(tracer) > 0
        showMe = showMe && contains(lowercase(store[l,6]),lowercase(tracer))
      end

      store[l,10] = showMe
    end
  end

  signal_connect(updateShownSF, entGradient, "changed")
  signal_connect(updateShownSF, entDF, "changed")
  signal_connect(updateShownSF, entSize, "changed")
  signal_connect(updateShownSF, entTracer, "changed")

  if gradient != nothing
    Gtk.@sigatom set_gtk_property!(entGradient,:text,string(gradient))
  end

  if driveField != nothing
    driveField[:].*=1000
    str = join([string(df," x ") for df in driveField])[1:end-2]
    Gtk.@sigatom set_gtk_property!(entDF, :text, str)
  end


  m = SFBrowserWidget(store,tv,vbox,tmSorted, nothing, nothing)

  #updateData!(m, sfDatabase.database)

  return m
end


mutable struct SFSelectionDialog <: Gtk.GtkDialog
  handle::Ptr{Gtk.GObject}
  selection
  store
  tmSorted
end

function SFSelectionDialog(;gradient = nothing, driveField = nothing)

  dialog = Dialog("Select System Function", mpilab[]["mainWindow"], GtkDialogFlags.MODAL,
                        Dict("gtk-cancel" => GtkResponseType.CANCEL,
                             "gtk-ok"=> GtkResponseType.ACCEPT) )

  resize!(dialog, 1024, 1024)

  box = G_.content_area(dialog)

  sfBrowser = SFBrowserWidget(gradient = gradient, driveField = driveField)
  updateData!(sfBrowser, activeDatasetStore(mpilab[]))

  push!(box, sfBrowser.box)
  set_gtk_property!(box, :expand, sfBrowser.box, true)

  selection = G_.selection(sfBrowser.tv)

  dlg = SFSelectionDialog(dialog.handle, selection, sfBrowser.store, sfBrowser.tmSorted)

  showall(box)

  Gtk.gobject_move_ref(dlg, dialog)
  return dlg
end

function getSelectedSF(dlg::SFSelectionDialog)
  currentItTM = selected(dlg.selection)
  sffilename =  TreeModel(dlg.tmSorted)[currentItTM,9]
  return sffilename
end



# signal_connect(tv, "row-activated") do treeview, path, col, other...
#     if hasselection(selection)
#       currentIt = selected(selection)
#
#       sffilename = store[currentIt,1]
#
#       SFViewer(sffilename)
#     end
#     false
#   end
