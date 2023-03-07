
mutable struct SFBrowserWidget
  store
  tv
  box
  tmSorted
  sysFuncs
  datasetStore
  selection
  updating
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

  @idle_add_guarded begin
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)

      uuids = Dict{String,Any}()
      for l = 2:size(sysFuncs,1)
        f = MPIFile(string(sysFuncs[l,14]),fastMode=true)
        uuid = string(experimentUuid(f))
        if !haskey(uuids, uuid)
          uuids[uuid] = Int[]
        end
        push!(uuids[uuid], l)
      end

      makeTupleSF(sysFuncs,l) = (sysFuncs[l,17], split(sysFuncs[l,15],"T")[1],
                       sysFuncs[l,1],round(sysFuncs[l,2], digits=2),
                       "$(round((sysFuncs[l,3]), digits=2)) x $(round((sysFuncs[l,4]), digits=2)) x $(round((sysFuncs[l,5]), digits=2))",
                        "$(sysFuncs[l,6]) x $(sysFuncs[l,7]) x $(sysFuncs[l,8])",
                        sysFuncs[l,10],sysFuncs[l,11],sysFuncs[l,12],sysFuncs[l,14], true)

      for (k,v) in uuids
        l = v[1]
        iter = push!(m.store, makeTupleSF(sysFuncs,l))
        for q = 2:length(v)
          l = v[q]
          push!(m.store, makeTupleSF(sysFuncs,l), iter)
        end
      end
      m.updating = false
  end
end


function SFBrowserWidget(smallWidth=false; gradient = nothing, driveField = nothing)

 #Name,Gradient,DFx,DFy,DFz,Size x,Size y,Size z,Bandwidth,Tracer,TracerBatch,DeltaSampleConcentration,DeltaSampleVolume,Path

  store = GtkTreeStore(Int,String,String,Float64,String,String,
                     String,String,String,String, Bool)

  tv = GtkTreeView(GtkTreeModel(store))
  r1 = GtkCellRendererText()
  r2 = GtkCellRendererToggle()

  if !smallWidth
    c0 = GtkTreeViewColumn("Num", r1, Dict("text" => 0))
    c1 = GtkTreeViewColumn("Date", r1, Dict("text" => 1))
    c2 = GtkTreeViewColumn("Name", r1, Dict("text" => 2))
    c3 = GtkTreeViewColumn("Gradient", r1, Dict("text" => 3))
    c4 = GtkTreeViewColumn("DF", r1, Dict("text" => 4))
    c5 = GtkTreeViewColumn("Size", r1, Dict("text" => 5))
    c6 = GtkTreeViewColumn("Tracer", r1, Dict("text" => 6))
    c7 = GtkTreeViewColumn("Batch", r1, Dict("text" => 7))
    c8 = GtkTreeViewColumn("Conc.", r1, Dict("text" => 8))
    c9 = GtkTreeViewColumn("Path", r1, Dict("text" => 9))

    for (i,c) in enumerate((c0,c1,c2,c3,c4,c5,c6,c7,c8,c9))
      G_.set_sort_column_id(c,i-1)
      G_.set_resizable(c,true)
      G_.set_max_width(c,80)
      push!(tv,c)
    end
  else
    c0 = GtkTreeViewColumn("Num", r1, Dict("text" => 0))
    c1 = GtkTreeViewColumn("Date", r1, Dict("text" => 1))
    c2 = GtkTreeViewColumn("Name", r1, Dict("text" => 2))
    c3 = GtkTreeViewColumn("Path", r1, Dict("text" => 9))

    for (i,c) in enumerate((c0,c1,c2,c3))
      G_.set_sort_column_id(c,i-1)
      G_.set_resizable(c,true)
      G_.set_max_width(c,80)
      push!(tv,c)
    end
  end
  G_.set_max_width(c1,200)
  G_.set_max_width(c2,200)

  tmFiltered = GtkTreeModelFilter(GtkTreeModel(store))
  G_.set_visible_column(tmFiltered,10)
  tmSorted = GtkTreeModelSort(tmFiltered)
  G_.set_model(tv, GtkTreeModel(tmSorted))

  G_.set_sort_column_id(GtkTreeSortable(tmSorted),0,Gtk4.SortType_DESCENDING)

  selection = G_.get_selection(tv)

  cbOpenMeas = GtkCheckButton("Open as Meas")
  cbOpenInWindow = GtkCheckButton("Open in Window")

  if smallWidth
    signal_connect(tv, "row-activated") do treeview, path, col, other...
      if hasselection(selection)
        currentIt = selected(selection)

        sffilename = GtkTreeModel(tmSorted)[currentIt,10]

        @idle_add_guarded begin
          if !get_gtk_property(cbOpenMeas,:active,Bool)
            if measIsCalibProcessed(MPIFile(sffilename,fastMode=true))
              if get_gtk_property(cbOpenInWindow,:active,Bool)
                SFViewer(sffilename)
              else
                updateData!(mpilab[].sfViewerWidget, sffilename)
                Gtk4.G_.set_current_page(mpilab[]["nbView"], 3)
              end
            else
              @show sffilename
              d = info_dialog(()-> nothing, "The calibration file $(sffilename) is not yet processed!", mpilab[]["mainWindow"])
              d.modal = true
            end
          else
            updateData(mpilab[].rawDataWidget, sffilename)
            Gtk4.G_.set_current_page(mpilab[]["nbView"], 0)
          end
        end
      end
      false
    end
  end

  vbox = GtkBox(:v)

  entGradient = GtkEntry()
  entDF = GtkEntry()
  entSize = GtkEntry()
  entTracer = GtkEntry()

  for ent in [entGradient,entDF,entSize,entTracer]
    set_gtk_property!(ent,:width_chars,11)
  end

  btnSFUpdate = GtkButton("Update")
  btnSFConvert = GtkButton("Convert")
  btnOpenCalibrationFolder = GtkButton("Open File Browser")
  btnSpectrogram = GtkButton("Spectrogram")

  if smallWidth
    grid = GtkGrid()
    push!(vbox, grid)
    grid.row_spacing = 5
    grid.column_spacing = 5

    grid[1,1] = GtkLabel("Grad.")
    grid[2,1] = entGradient
    grid[1,2] = GtkLabel("DF Str.")
    grid[2,2] = entDF
    grid[3,1] = GtkLabel("Size")
    grid[4,1] = entSize
    grid[3,2] = GtkLabel("Tracer")
    grid[4,2] = entTracer
    grid[1:2,3] = cbOpenMeas
    grid[3:4,3] = btnSFUpdate
    grid[1:2,4] = cbOpenInWindow
    grid[3:4,4] = btnSFConvert
    grid[3:4,5] = btnOpenCalibrationFolder
    grid[1:2,5] = btnSpectrogram
  else
    hbox = GtkBox(:h)
    push!(vbox, hbox)
    set_gtk_property!(hbox,:spacing,5)
    set_gtk_property!(hbox,:margin_left,5)
    set_gtk_property!(hbox,:margin_right,5)
    set_gtk_property!(hbox,:margin_top,5)
    set_gtk_property!(hbox,:margin_bottom,5)

    push!(hbox, GtkLabel("Gradient"))
    push!(hbox, entGradient)
    push!(hbox, GtkLabel("DF Strength"))
    push!(hbox, entDF)
    push!(hbox, GtkLabel("Size"))
    push!(hbox, entSize)
    push!(hbox, GtkLabel("Tracer"))
    push!(hbox, entTracer)
    push!(hbox, btnSFUpdate)
  end


  sw = GtkScrolledWindow()
  G_.set_child(sw, tv)
  push!(vbox, sw)
  sw.vexpand = true

  show(tv)
  show(vbox)

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
      filename = GtkTreeModel(m.tmSorted)[currentIt,10]
      conversionDialog(m, filename)
    end
  end

  signal_connect(convSF, btnSFConvert, "clicked")

  signal_connect(btnOpenCalibrationFolder, "clicked") do widget
    @idle_add_guarded begin
        openFileBrowser(calibdir(m.datasetStore))
    end
  end

  signal_connect(btnSpectrogram, "clicked") do widget
    if hasselection(selection)
      currentIt = selected(selection)

      sffilename = GtkTreeModel(tmSorted)[currentIt,10]

      @idle_add_guarded SpectrogramViewer(sffilename)

    end
  end

  function n_children(store)
    ccall((:gtk_tree_model_iter_n_children, Gtk.libgtk), Cint, (Ptr{GObject}, Ptr{GtkTreeIter}), store, C_NULL)
  end

  function n_children(store, iter)
    return ccall((:gtk_tree_model_iter_n_children, Gtk.libgtk), Cint, (Ptr{GObject}, Ref{GtkTreeIter}), store, iter)
  end

  function updateShownSF( widget )
    @idle_add_guarded begin
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

      for q=1:n_children(store) #(size(m.sysFuncs,1)-1) #  length(store)
        l = [q]
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
  end

  signal_connect(updateShownSF, entGradient, "changed")
  signal_connect(updateShownSF, entDF, "changed")
  signal_connect(updateShownSF, entSize, "changed")
  signal_connect(updateShownSF, entTracer, "changed")

  if gradient != nothing
    @idle_add_guarded set_gtk_property!(entGradient,:text,string(gradient))
  end

  if driveField != nothing
    driveField[:].*=1000
    str = join([string(df," x ") for df in driveField])[1:end-2]
    @idle_add_guarded set_gtk_property!(entDF, :text, str)
  end

  m = SFBrowserWidget(store, tv, vbox, tmSorted, nothing, nothing, selection, false)

  signal_connect(m.selection, "changed") do widget
    if hasselection(m.selection) && !m.updating
      @idle_add_guarded begin
        currentIt = selected( m.selection )
        filename = GtkTreeModel(m.tmSorted)[currentIt,10]
        f = MPIFile(filename, fastMode=true)
        num = experimentNumber(f)
        name = experimentName(f)
        tname = tracerName(f)
        path1 = filepath(f)
        path2 = filename
        time = acqStartTime(f)
        numPeriods = acqNumPeriodsPerFrame(f)
        numAverages = acqNumAverages(f)
        sizeSF =  GtkTreeModel(m.tmSorted)[currentIt,6]
        isCalibProcessed = measIsCalibProcessed(f)
        dfStr = GtkTreeModel(m.tmSorted)[currentIt,5]
        str =   """Num: $(num)\n
                Name: $(name)\n
                Tracer: $(tname)\n
                Path 1: $(path1)\n
                Path 2: $(path2)\n
                Time: $(time)\n
                Averages: $(numAverages)\n
                Periods: $(numPeriods)\n
                Size: $(sizeSF)\n
                DF Strength: $(dfStr)\n
                IsProcessed: $(isCalibProcessed)"""
        set_gtk_property!(m.tv, :tooltip_text, str)
      end
    end
  end

  return m
end


mutable struct SFSelectionDialog <: Gtk4.GtkDialog
  handle::Ptr{Gtk4.GObject}
  selection
  store
  tmSorted
end

function SFSelectionDialog(;gradient = nothing, driveField = nothing)

  dialog = GtkDialog("Select System Function",
                        ["_Cancel" => Gtk4.ResponseType_CANCEL,
                             "_OK"=> Gtk4.ResponseType_ACCEPT],
                             Gtk4.DialogFlags_MODAL, mpilab[]["mainWindow"] )

  Gtk4.default_size(dialog, 1024, 1024)

  box = G_.get_content_area(dialog)

  sfBrowser = SFBrowserWidget(gradient = gradient, driveField = driveField)
  updateData!(sfBrowser, activeDatasetStore(mpilab[]))

  push!(box, sfBrowser.box)

  selection = G_.get_selection(sfBrowser.tv)

  dlg = SFSelectionDialog(dialog.handle, selection, sfBrowser.store, sfBrowser.tmSorted)

  show(box)

  Gtk4.GLib.gobject_move_ref(dlg, dialog)
  return dlg
end

function getSelectedSF(dlg::SFSelectionDialog)
  currentItTM = selected(dlg.selection)
  sffilename =  GtkTreeModel(dlg.tmSorted)[currentItTM,10]
  return sffilename
end


@guarded function conversionDialog(m::SFBrowserWidget, filename::AbstractString)
  
  f = MPIFile(filename)

  dialog = GtkDialog("Convert System Function",  
                    ["_Cancel" => Gtk4.ResponseType_CANCEL,
                    "_Ok"=> Gtk4.ResponseType_ACCEPT],
                    Gtk4.DialogFlags_MODAL,
                    mpilab[]["mainWindow"], )

  box = G_.get_content_area(dialog)

  grid = GtkGrid()
  push!(box, grid)
  set_gtk_property!(grid, :row_spacing, 5)
  set_gtk_property!(grid, :column_spacing, 5)

  grid[1,1] = GtkLabel("Num Period Averages")
  grid[2,1] = GtkSpinButton(1:acqNumPeriodsPerFrame(f))
  adjNumPeriodAverages = GtkAdjustment(grid[2,1])

  grid[1,2] = GtkLabel("Num Period Grouping")
  grid[2,2] = GtkSpinButton(1:acqNumPeriodsPerFrame(f))
  adjNumPeriodGrouping = GtkAdjustment(grid[2,2])

  grid[1,3] = GtkLabel("Apply Calib Postprocessing")
  grid[2,3] = GtkCheckButton(active=true)

  grid[1,4] = GtkLabel("Fix Distortions")
  grid[2,4] = GtkCheckButton(active=false)

  function on_response(dialog, response_id)
    if response_id == Integer(Gtk4.ResponseType_ACCEPT)   
      numPeriodAverages = get_gtk_property(adjNumPeriodAverages,:value,Int64)
      numPeriodGrouping = get_gtk_property(adjNumPeriodGrouping,:value,Int64)
      applyCalibPostprocessing = get_gtk_property(grid[2,3],:active,Bool)
      fixDistortions = get_gtk_property(grid[2,4],:active,Bool)

      @info numPeriodAverages  numPeriodGrouping

      calibNum = getNewCalibNum(m.datasetStore)

      filenameNew = joinpath(calibdir(m.datasetStore),string(calibNum)*".mdf")
      @info "Start converting System Matrix"
      saveasMDF(filenameNew, f, applyCalibPostprocessing=applyCalibPostprocessing, 
                experimentNumber = calibNum, fixDistortions=fixDistortions,
                numPeriodAverages = numPeriodAverages, numPeriodGrouping = numPeriodGrouping)

      updateData!(m, m.datasetStore)
    end
    destroy(dialog)
  end

  signal_connect(on_response, dialog, "response")
  @idle_add_guarded show(dialog) 
  return
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
