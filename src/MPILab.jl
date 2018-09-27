export MPILab

mutable struct MPILab
  builder
  activeStore
  datasetStores
  brukerRecoStore
  studyStore
  studyStoreSorted
  experimentStore
  reconstructionStore
  visuStore
  anatomRefStore
  currentStudy
  currentExperiment
  currentReco
  currentVisu
  selectionAnatomicRefs
  selectionReco
  selectionVisu
  selectionExp
  selectionStudy
  sfBrowser
  settings
  clearingStudyStore
  clearingExpStore
  basicRobot
  robotScanner
  multiPatchRobot
  measurementWidget
  dataViewerWidget
  rawDataWidget
  recoWidget
  currentAnatomRefFilename
  sfViewerWidget
end

getindex(m::MPILab, w::AbstractString) = G_.object(m.builder, w)

mpilab = Ref{MPILab}()

activeDatasetStore(m::MPILab) = m.datasetStores[m.activeStore]
activeRecoStore(m::MPILab) = typeof(activeDatasetStore(m)) <: BrukerDatasetStore ?
                                      m.brukerRecoStore : activeDatasetStore(m)

function MPILab(offlineMode=false)::MPILab
  @info "Starting MPILab"

  uifile = joinpath(@__DIR__,"builder","mpiLab.ui")

  m_ = MPILab( Builder(filename=uifile), 1, DatasetStore[],
              nothing, nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, false, false, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, "", nothing)

  let m=m_

  mpilab[] = m

  w = m["mainWindow"]

  @debug "## Init Settings ..."
  initSettings(m)
  @debug "## Init Measurement Tab ..."
  initMeasurementTab(m, offlineMode)
  @debug "## Init Store switch ..."
  initStoreSwitch(m)

  @debug "## Init Study ..."
  initStudyStore(m)

  @debug "## Init Experiment Store ..."
  initExperimentStore(m)
  @debug "## Init SFStore ..."
  initSFStore(m)
  @debug "## Init SF Viewer..."
  initSFViewerTab(m)
  @debug "## Init Image Tab ..."
  initImageTab(m)
  @debug "## Init Raw Data Tab ..."
  initRawDataTab(m)
  if m.settings["enableRecoStore", true]
    @debug "## Init Reco Tab ..."
    initRecoTab(m)
  end
  @debug "## Init Reco Store ..."
  initReconstructionStore(m)
  @debug "## Init Anatom Ref Store ..."
  initAnatomRefStore(m)
  @debug "## Init Visu Store ..."
  initVisuStore(m)
  @debug "## Init View switch ..."
  initViewSwitch(m)

  Gtk.@sigatom set_gtk_property!(m["cbDatasetStores"],:active,0)

  # ugly but necessary since showall unhides all widgets
  #Gtk.@sigatom visible(m["boxMeasTab"],
  #    isMeasurementStore(m.measurementWidget,activeDatasetStore(m)) )
  #Gtk.@sigatom visible(m["tbOpenMeasurementTab"],
  #        isMeasurementStore(m.measurementWidget,activeDatasetStore(m)) )


  show(w)

  signal_connect(w, "key-press-event") do widget, event
    if event.keyval ==  Gtk.GConstants.GDK_KEY_c
      if event.state & 0x04 != 0x00 # Control key is pressed
        @debug "copy visu params to clipboard..."
        str = string( getParams(m.dataViewerWidget) )
        # str_ = replace(str,",Pair",",\n  Pair")
        clipboard( str )
      end
    elseif event.keyval == Gtk.GConstants.GDK_KEY_v
        if event.state & 0x04 != 0x00 # Control key is pressed
          @debug "copy visu params from clipboard to UI..."
          str = clipboard()
          try
          dict= eval(Meta.parse(str))
          setParams(m.dataViewerWidget, dict)
        catch
          @warn "not the right format for SetParams in clipboard..."
        end
        end
    end
  end

  @info "Finished starting MPILab"

  end

  return m_
end

function initStoreSwitch(m::MPILab)
  empty!(m["cbDatasetStores"])
  for store_ in m.settings["datasetStores"]
    if store_ == "/opt/mpidata"
      store = BrukerDatasetStore( store_ )
    else
      store = MDFDatasetStore( store_ )
    end
    push!(m.datasetStores, store)
    push!(m["cbDatasetStores"], store_)
  end
  m.activeStore = 1
  #set_gtk_property!(m["cbDatasetStores"],:active,0)

  m.brukerRecoStore = MDFDatasetStore( m.settings["brukerRecoStore"] )

  signal_connect(m["cbDatasetStores"], "changed") do widget...
    @debug "changing dataset store"
    m.activeStore = get_gtk_property(m["cbDatasetStores"], :active, Int64)+1
    Gtk.@sigatom begin
      scanDatasetDir(m)
      updateData!(m.sfBrowser,activeDatasetStore(m))

      #Gtk.@sigatom visible(m["boxMeasTab"],
      #    isMeasurementStore(m.measurementWidget,activeDatasetStore(m)) )
      visible(m["tbOpenMeasurementTab"],
        isMeasurementStore(m.measurementWidget,activeDatasetStore(m)) )

      if length(m.studyStore) > 0
        # select first study so that always measurements can be performed
        iter = Gtk.mutable(Gtk.GtkTreeIter)
        Gtk.get_iter_first( TreeModel(m.studyStoreSorted) , iter)
        select!(m.selectionStudy, iter)
      end
    end
    return nothing
  end

  return nothing
end

function initViewSwitch(m::MPILab)
  signal_connect(m["nbView"], "switch-page") do widget, page, page_num
    @debug "switched to tab" page_num
    if page_num == 0
      if m.currentExperiment != nothing
        Gtk.@sigatom updateData(m.rawDataWidget, m.currentExperiment.path)
      end
    elseif page_num == 1

    elseif page_num == 2
      if m.currentExperiment != nothing
        Gtk.@sigatom updateData!(m.recoWidget, m.currentExperiment.path )
      end
    elseif page_num == 4
      Gtk.@sigatom unselectall!(m.selectionExp)
      m.currentExperiment = nothing
    end
    return nothing
  end
  return nothing
end

function reinit(m::MPILab)
  #m.brukerStore = BrukerDatasetStore( m.settings["datasetDir"] )
  #m.mdfStore = MDFDatasetStore( m.settings["reconstructionDir"] )


  scanDatasetDir(m)
end

function initStudyStore(m::MPILab)

  m.studyStore = ListStore(String,String,String,String,Bool)

  tv = TreeView(TreeModel(m.studyStore))
  #G_.headers_visible(tv,false)
  r1 = CellRendererText()

  cols = ["Date", "Study", "Subject"]

  for (i,col) in enumerate(cols)
    c = TreeViewColumn(col, r1, Dict("text" => i-1))
    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,300)
    push!(tv,c)
  end

  #Gtk.add_attribute(c1,r2,"text",0)
  #G_.sort_column_id(c1,0)
  #G_.resizable(c1,true)
  #G_.max_width(c1,80)

  sw = m["swStudy"]
  push!(sw,tv)
  showall(sw)


  scanDatasetDir(m)

  tmFiltered = TreeModelFilter(m.studyStore)
  G_.visible_column(tmFiltered,4)
  m.studyStoreSorted = TreeModelSort(tmFiltered)
  G_.model(tv, m.studyStoreSorted)

  m.selectionStudy = G_.selection(tv)

  #G_.sort_column_id(TreeSortable(m.studyStore),0,GtkSortType.ASCENDING)
  G_.sort_column_id(TreeSortable(m.studyStoreSorted),0,GtkSortType.ASCENDING)


  if length(m.studyStore) > 0
    # select first study so that always measurements can be performed
    iter = Gtk.mutable(Gtk.GtkTreeIter)
    Gtk.get_iter_first( TreeModel(m.studyStoreSorted) , iter)
    Gtk.@sigatom select!(m.selectionStudy, iter)
  end

  function selectionChanged( widget )
    if hasselection(m.selectionStudy) && !m.clearingStudyStore
      currentIt = selected( m.selectionStudy )

      m.currentStudy = Study(TreeModel(m.studyStoreSorted)[currentIt,4],
                             TreeModel(m.studyStoreSorted)[currentIt,2],
                             TreeModel(m.studyStoreSorted)[currentIt,3],
                             TreeModel(m.studyStoreSorted)[currentIt,1])

      Gtk.@sigatom updateExperimentStore(m, m.currentStudy)

      @debug "Current Study Id: " id(m.currentStudy)
      Gtk.@sigatom updateAnatomRefStore(m)

      m.measurementWidget.currStudyName = m.currentStudy.name
    end
  end

  signal_connect(m.selectionStudy, "changed") do widget
    Gtk.@sigatom selectionChanged(widget)
  end

  function updateShownStudies( widget )

    studySearchText = get_gtk_property(m["entSearchStudies"], :text, String)

    for l=1:length(m.studyStore)
      showMe = true

      if length(studySearchText) > 0
        showMe = showMe && occursin(lowercase(studySearchText), lowercase(m.studyStore[l,2]))
      end

      Gtk.@sigatom m.studyStore[l,5] = showMe
    end
  end

  signal_connect(updateShownStudies, m["entSearchStudies"], "changed")

  signal_connect(m["tbRemoveStudy"], "clicked") do widget
    if hasselection(m.selectionStudy)
      if ask_dialog("Do you really want to delete the study $(m.currentStudy.name)?", mpilab[]["mainWindow"])
        remove(m.currentStudy)

        # TODO
        #currentIt = selected( m.selectionStudy )
        #Gtk.@sigatom delete!(TreeModel(m.studyStoreSorted), currentIt)

        Gtk.@sigatom scanDatasetDir(m)
      end
    end
  end


  signal_connect(m["tbAddStudy"], "clicked") do widget
    name = get_gtk_property(m["entSearchStudies"], :text, String)
    study = Study("", name, "", "")
    addStudy(activeDatasetStore(m), study)
    Gtk.@sigatom scanDatasetDir(m)

    iter = Gtk.mutable(Gtk.GtkTreeIter)
    Gtk.get_iter_first( TreeModel(m.studyStoreSorted) , iter)
    for l=1:length(m.studyStore)
      if TreeModel(m.studyStoreSorted)[iter,2] == name
        break
      else
        Gtk.get_iter_next( TreeModel(m.studyStoreSorted) , iter)
      end
    end

    Gtk.@sigatom select!(m.selectionStudy, iter)
  end

  signal_connect(m["tbOpenMeasurementTab"], "clicked") do widget
    Gtk.@sigatom G_.current_page(m["nbView"], 4)
  end

end

function scanDatasetDir(m::MPILab)
  #unselectall!(m.selectionStudy)

  m.clearingStudyStore = true # worst hack ever
  empty!(m.studyStore)
  m.currentStudy = nothing
  m.currentExperiment = nothing
  m.clearingStudyStore = false

  studies = getStudies( activeDatasetStore(m) )

  for study in studies
    push!(m.studyStore, (study.date, study.name, study.subject, study.path, true))
  end
end


### Anatomic Reference Store ###

function initAnatomRefStore(m::MPILab)

  m.anatomRefStore = ListStore(String, String)

  tv = TreeView(TreeModel(m.anatomRefStore))
  r1 = CellRendererText()

  cols = ["Name"]

  for (i,col) in enumerate(cols)
    c = TreeViewColumn(col, r1, Dict("text" => i-1))
    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,300)
    push!(tv,c)
  end


  sw = m["swAnatomData"]
  push!(sw,tv)
  showall(sw)

  G_.sort_column_id(TreeSortable(m.anatomRefStore),0,GtkSortType.ASCENDING)

  selection = G_.selection(tv)
  m.selectionAnatomicRefs = selection

  signal_connect(m["tbAddAnatomicalData"], "clicked") do widget
    filename = open_dialog("Select Anatomic Reference", mpilab[]["mainWindow"], action=GtkFileChooserAction.OPEN)
    if !isfile(filename)
      @warn "$filename * is not a file"
    else
      targetPath = joinpath(activeRecoStore(m).path, "reconstructions", id(m.currentStudy), "anatomicReferences", last(splitdir(filename)) )
      mkpath(targetPath)
      try_chmod(targetPath, 0o777, recursive=true)
      cp(filename, targetPath, force=true)
      Gtk.@sigatom updateAnatomRefStore(m)
    end

  end

  signal_connect(tv, "row-activated") do treeview, path, col, other...
    if hasselection(selection)
      currentIt = selected( selection )

      name = m.anatomRefStore[currentIt,1]
      filename = m.anatomRefStore[currentIt,2]

      im = loaddata(filename)
      im_ = copyproperties(im,squeeze(data(im)))
      Gtk.@sigatom DataViewer(im_)
    end
    false
  end

  signal_connect(m.selectionAnatomicRefs, "changed") do widget
    if hasselection(m.selectionAnatomicRefs)
      currentIt = selected( m.selectionAnatomicRefs )

      m.currentAnatomRefFilename = m.anatomRefStore[currentIt,2]
    end
  end
end


function updateAnatomRefStore(m::MPILab)
  empty!(m.anatomRefStore)

  currentPath = joinpath(activeRecoStore(m).path, "reconstructions", id(m.currentStudy), "anatomicReferences" )

  if isdir(currentPath)
    files = readdir(currentPath)

    for file in files
      name, ext = splitext(file)
      if isfile(joinpath(currentPath,file)) && (ext == ".hdf" || ext == ".mdf" ||ext == ".nii" ||ext == ".dcm")
        push!(m.anatomRefStore, (name,joinpath(currentPath,file)))
      end
    end
  end

end


### Experiment Store ###

function initExperimentStore(m::MPILab)

  m.experimentStore = ListStore(Int64,String,Int64,String,
                                 Float64,String)
  tmFiltered = nothing

  tv = TreeView(TreeModel(m.experimentStore))
  r1 = CellRendererText()
  r2 = CellRendererText()
  set_gtk_property!(r2, :editable, true)

  cols = ["Num", "Name", "Frames", "DF", "Grad"]

  for (i,col) in enumerate(cols)

    if i==2 #magic number
      c = TreeViewColumn(col, r2, Dict("text" => i-1))
    else
      c = TreeViewColumn(col, r1, Dict("text" => i-1))
    end

    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,300)
    push!(tv,c)
  end

  sw = m["swExp"]
  push!(sw,tv)
  showall(sw)

  G_.sort_column_id(TreeSortable(m.experimentStore),0,GtkSortType.ASCENDING)

  m.selectionExp = G_.selection(tv)

  signal_connect(m["tbRawData"], "clicked") do widget
    if hasselection( m.selectionExp)
      Gtk.@sigatom begin
        updateData(m.rawDataWidget, m.currentExperiment.path)
        G_.current_page(m["nbView"], 0)
      end
    end
  end


  signal_connect(m["tbReco"], "clicked") do widget
    if hasselection(m.selectionExp)
      Gtk.@sigatom begin
        if m.settings["enableRecoStore", true]
          updateData!(m.recoWidget, m.currentExperiment.path, m.currentStudy, m.currentExperiment )
          G_.current_page(m["nbView"], 2)
        end
      end
    end
  end

  signal_connect(m["tbOpenExperimentFolder"], "clicked") do widget
    if hasselection(m.selectionStudy)
      Gtk.@sigatom begin
        openFileBrowser(m.currentStudy.path)
      end
    end
  end


  signal_connect(tv, "row-activated") do treeview, path, col, other...
    if hasselection(m.selectionExp)
      Gtk.@sigatom begin
        #updateData!(m.recoWidget, m.currentExperiment.path )
        updateData(m.rawDataWidget, m.currentExperiment.path)
        G_.current_page(m["nbView"], 0)
      end
    end
    false
  end

  signal_connect(m.selectionExp, "changed") do widget
    if hasselection(m.selectionExp) && !m.clearingStudyStore &&
      m.currentStudy != nothing && !m.clearingExpStore

      currentIt = selected( m.selectionExp )

      exp = getExperiment(m.currentStudy, m.experimentStore[currentIt,1])
      @debug "Experiment path" exp.path
      if exp != nothing && ispath(exp.path)
        m.currentExperiment = exp
        #Experiment( string(m.experimentStore[currentIt,length(cols)+1]),
        #  m.experimentStore[currentIt,1], m.experimentStore[currentIt,2],
        #  m.experimentStore[currentIt,3],
        #  [parse(Float64,s) for s in split( string(m.experimentStore[currentIt,4]),"x") ],
        #  m.experimentStore[currentIt,5])


         Gtk.@sigatom updateReconstructionStore(m)
         #Gtk.@sigatom updateAnatomRefStore(m)

         Gtk.@sigatom begin
           exp = m.currentExperiment
           set_gtk_property!(tv, :tooltip_text,
             """Num: $(exp.num)\n
                Name: $(exp.name)\n
                NumFrames: $(exp.numFrames)\n
                DF: $(join(exp.df,"x"))\n
                Gradient: $(exp.sfGradient)\n
                Averages: $(exp.numAverages)\n
                Operator: $(exp.operator)\n
                Time: $(exp.time)""")

         end
      end
    end
  end


  signal_connect(m["tbRemoveExp"], "clicked") do widget
    if hasselection(m.selectionExp)
      if ask_dialog("Do you really want to delete the experiment $(m.currentExperiment.num)?")
        remove(m.currentExperiment)

        Gtk.@sigatom updateExperimentStore(m, m.currentStudy)
      end
    end
  end

  signal_connect(r2, "edited") do widget, path, text
    if hasselection(m.selectionExp)
      currentIt = selected( m.selectionExp )

      if splitext(m.currentExperiment.path)[2] == ".mdf"
        Gtk.@sigatom m.experimentStore[currentIt,2] = string(text)
        GC.gc() # This is important to run all finalizers of MPIFile
        h5open(m.currentExperiment.path, "r+") do file
          if exists(file, "/experiment/name")
            o_delete(file, "/experiment/name")
          end
          write(file, "/experiment/name", string(text) )
        end
      end
      #m.currentVisu.params[:description] = string(text)
      #Gtk.@sigatom save(m.currentVisu)
    end
  end

end

function updateExperimentStore(m::MPILab, study::Study)
  m.clearingExpStore = true
  Gtk.@sigatom unselectall!(m.selectionExp)

  Gtk.@sigatom empty!(m.experimentStore)
  Gtk.@sigatom empty!(m.reconstructionStore)

  experiments = getExperiments( activeDatasetStore(m), study)

  for exp in experiments
    Gtk.@sigatom push!(m.experimentStore,(exp.num, exp.name, exp.numFrames,
                join(exp.df,"x"),exp.sfGradient, exp.path))
  end
  m.clearingExpStore = false
end


### Reconstruction Store ###


function initReconstructionStore(m::MPILab)

  m.reconstructionStore =
      ListStore(Int64,String,String,String,String,String,String,String, String)

  tv = TreeView(TreeModel(m.reconstructionStore))
  r1 = CellRendererText()
  r2 = CellRendererText()
  set_gtk_property!(r2, :editable, true)

  cols = ["Num","Frames","Description","Solver","Iter", "Lambda", "Averages", "SNRThresh", "User"]

  for (i,col) in enumerate(cols)

    if i==3 #magic number
      c = TreeViewColumn(col, r2, Dict("text" => i-1))
    else
      c = TreeViewColumn(col, r1, Dict("text" => i-1))
    end

    G_.max_width(c,100)
    G_.resizable(c,true)
    G_.sort_column_id(c,i-1)
    push!(tv,c)
  end

  sw = m["swReco"]
  push!(sw,tv)
  showall(sw)

  G_.sort_column_id(TreeSortable(m.reconstructionStore),0,GtkSortType.ASCENDING)

  m.selectionReco = G_.selection(tv)

  signal_connect(tv, "row-activated") do treeview, path, col, other...
    if hasselection(m.selectionReco)
      im = loaddata(m.currentReco.path)
      #Gtk.@sigatom DataViewer(im)
      Gtk.@sigatom begin
         updateData!(m.dataViewerWidget, im)
         G_.current_page(m["nbView"], 1)
      end
    end
    false
  end

  signal_connect(r2, "edited") do widget, path, text
    @debug "" text
    if hasselection(m.selectionReco)
      currentIt = selected( m.selectionReco )

      Gtk.@sigatom m.reconstructionStore[currentIt,3] = string(text)
    end
    m.currentReco.params[:description] = string(text)
    save(m.currentReco)
    #Gtk.@sigatom updateReconstructionStore(m)
  end

  signal_connect(m.selectionReco, "changed") do widget
    if hasselection(m.selectionReco) && m.currentStudy != nothing &&
       m.currentExperiment != nothing

      currentIt = selected( m.selectionReco )

      recoNum = m.reconstructionStore[currentIt,1]

      m.currentReco = getReco(activeRecoStore(m), m.currentStudy, m.currentExperiment, recoNum)

      if isfile(m.currentReco.path)
        im = loaddata(m.currentReco.path)
        #Gtk.@sigatom DataViewer(im)
        #Gtk.@sigatom begin
        #   updateData!(m.dataViewerWidget, im)
        #   G_.current_page(m["nbView"], 1)
        #end
      end
    end

    Gtk.@sigatom updateVisuStore(m)
    return false
  end

  signal_connect(m["tbRemoveReco"], "clicked") do widget
    if hasselection(m.selectionReco)
      remove(m.currentReco)

      Gtk.@sigatom updateReconstructionStore(m)
    end
  end

  signal_connect(m["tbOpenFusion"], "clicked") do widget
    if hasselection(m.selectionReco) && isfile(m.currentAnatomRefFilename)

      imFG = loaddata(m.currentReco.path)

      currentIt = selected( m.selectionAnatomicRefs )

      imBG = loaddata(m.currentAnatomRefFilename)
      imBG_ = copyproperties(imBG,squeeze(data(imBG)))

      imBG_["filename"] = m.currentAnatomRefFilename #last(splitdir(filename))

      #DataViewer(imFG, imBG_)

      Gtk.@sigatom begin
         updateData!(m.dataViewerWidget, imFG, imBG_)
         G_.current_page(m["nbView"], 1)
      end


    end
  end

  signal_connect(m["tbRedoReco"], "clicked") do widget
    if hasselection(m.selectionReco)
      params = m.currentReco.params

      Gtk.@sigatom begin
        updateData!(m.recoWidget, m.currentExperiment.path, params, m.currentStudy, m.currentExperiment)
        G_.current_page(m["nbView"], 2)
      end
    end
  end

  signal_connect(m["tbExportRecoData"], "clicked") do widget
    if hasselection(m.selectionReco)
      filter = Gtk.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
      filenameData = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
      if filenameData != ""
        image = loaddata(m.currentReco.path)
        file, ext = splitext(filenameData)
        savedata(string(file,".nii"), image)
      end
    end
  end


end


function updateReconstructionStore(m::MPILab)
  empty!(m.reconstructionStore)

  recons = getRecons(activeRecoStore(m), m.currentStudy, m.currentExperiment)

  for r in recons
    p = r.params
    push!(m.reconstructionStore, (r.num,string(p[:frames]),get(p,:description,""),
        p[:solver],string(p[:iterations]),string(p[:lambd]),
        string(p[:nAverages]),string(p[:SNRThresh]),get(p,:reconstructor,"")))
  end
end

function addReco(m::MPILab, image, currentStudy, currentExperiment)
  addReco(activeRecoStore(m), m.currentStudy, m.currentExperiment, image)
  Gtk.@sigatom updateReconstructionStore(m)
end

### Visualization Store ###

function initVisuStore(m::MPILab)

  m.visuStore = ListStore(Int64,String,String,String,String,String)

  tv = TreeView(TreeModel(m.visuStore))
  r1 = CellRendererText()
  r2 = CellRendererText()
  set_gtk_property!(r2, :editable, true)

  cols = ["Num","Description","Spatial MIP","Frame Proj", "Cmap", "Fusion"]

  for (i,col) in enumerate(cols)
    if i==2 #magic number
      c = TreeViewColumn(col, r2, Dict("text" => i-1))
    else
      c = TreeViewColumn(col, r1, Dict("text" => i-1))
    end

    G_.sort_column_id(c,i-1)
    push!(tv,c)
  end

  sw = m["swVisu"]
  push!(sw,tv)
  showall(sw)

  G_.sort_column_id(TreeSortable(m.visuStore),0,GtkSortType.ASCENDING)

  m.selectionVisu = G_.selection(tv)

  signal_connect(tv, "row-activated") do treeview, path, col, other...
    if hasselection(m.selectionReco)
      if hasselection(m.selectionVisu)

        im = loaddata(m.currentReco.path)

        params = m.currentVisu.params
        if params!=nothing && params[:filenameBG] != ""
          path = joinpath(activeRecoStore(m).path, "reconstructions",
                      id(m.currentStudy), "anatomicReferences", params[:filenameBG])
          imBG = loaddata(path)
          imBG_ = copyproperties(imBG,squeeze(data(imBG)))
          imBG_["filename"] = path #params[:filenameBG]
        else
          imBG_ = nothing
        end
        #Gtk.@sigatom DataViewer(im, imBG_, params=m.currentVisu.params)

        Gtk.@sigatom begin
           updateData!(m.dataViewerWidget, im, imBG_, params=m.currentVisu.params)
           G_.current_page(m["nbView"], 1)
        end
      end
    end

    false
  end

  signal_connect(r2, "edited") do widget, path, text
    if hasselection(m.selectionVisu)
      currentIt = selected( m.selectionVisu )
      m.currentVisu.params[:description] = string(text)
      Gtk.@sigatom m.visuStore[currentIt,2] = string(text)
      Gtk.@sigatom save(m.currentVisu)
    end
  end

  signal_connect(m["tbRemoveVisu"], "clicked") do widget
    if hasselection(m.selectionVisu)
     remove(m.currentVisu)
     Gtk.@sigatom updateVisuStore(m)
    end
  end

  signal_connect(m.selectionVisu, "changed") do widget
    if hasselection(m.selectionVisu)
      currentIt = selected( m.selectionVisu )

      visuNum = m.visuStore[currentIt,1]

      m.currentVisu = getVisu(activeRecoStore(m), m.currentStudy, m.currentExperiment, m.currentReco, visuNum)
    end
  end
end


function updateVisuStore(m::MPILab)
  empty!(m.visuStore)

  if hasselection(m.selectionReco) && m.currentStudy != nothing &&
     m.currentExperiment != nothing

    visus = getVisus(activeRecoStore(m), m.currentStudy, m.currentExperiment, m.currentReco)
    filename = getVisuPath( m.currentReco )

    for (i,visu) in enumerate(visus)
      params = visu.params
      anatomicRef = (get(params, :filenameBG, "") != "") ? last(splitdir(params[:filenameBG])) : ""
      push!(m.visuStore, ( visu.num ,get(params,:description,""),
                             string(get(params,:spatialMIP,"")),
                             string(get(params,:frameProj,"")),
                             existing_cmaps()[params[:coloring][1].cmap+1], anatomicRef))
    end
  end
end

function addVisu(m::MPILab, visuParams)
  if hasselection(m.selectionReco)
    addVisu(activeRecoStore(m), m.currentStudy, m.currentExperiment, m.currentReco, visuParams)
    Gtk.@sigatom updateVisuStore(m)
  end
end


### System Function Store ###


function initSFStore(m::MPILab)

  m.sfBrowser = SFBrowserWidget(true)

  boxSFPane = m["boxSF"]
  push!(boxSFPane,m.sfBrowser.box)
  set_gtk_property!(boxSFPane, :expand, m.sfBrowser.box, true)
  showall(boxSFPane)
end

### Measurement Tab ###


function initMeasurementTab(m::MPILab, offlineMode)

  settings = offlineMode ? "" : m.settings["scanner"]
  m.measurementWidget = MeasurementWidget(settings)

  boxMeasTab = m["boxMeasTab"]
  push!(boxMeasTab,m.measurementWidget)
  set_gtk_property!(boxMeasTab, :expand, m.measurementWidget, true)
  showall(boxMeasTab)
end

### Image Tab ###


function initImageTab(m::MPILab)

  m.dataViewerWidget = DataViewerWidget()

  boxImageTab = m["boxImageTab"]
  push!(boxImageTab,m.dataViewerWidget)
  set_gtk_property!(boxImageTab, :expand, m.dataViewerWidget, true)
end

### Raw Data Tab ###

function initRawDataTab(m::MPILab)

  m.rawDataWidget = RawDataWidget()

  boxRawViewer = m["boxRawViewer"]
  push!(boxRawViewer,m.rawDataWidget)
  set_gtk_property!(boxRawViewer, :expand, m.rawDataWidget, true)
  showall(boxRawViewer)
end

### Reco Data Tab ###

function initRecoTab(m::MPILab)

  m.recoWidget = RecoWidget()

  boxRecoTab = m["boxRecoTab"]
  push!(boxRecoTab,m.recoWidget)
  set_gtk_property!(boxRecoTab, :expand, m.recoWidget, true)
end

### Raw Data Tab ###

function initSFViewerTab(m::MPILab)

  m.sfViewerWidget = SFViewerWidget()

  boxSFTab = m["boxSFTab"]
  push!(boxSFTab,m.sfViewerWidget)
  set_gtk_property!(boxSFTab, :expand, m.sfViewerWidget, true)
  showall(boxSFTab)
end

### Settings

function initSettings(m::MPILab)
  m.settings = Settings()
  #m["gridSettings_"][1,1] = m.settings["gridSettings"]
end
