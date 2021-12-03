export MPILab, scanner

mutable struct MPILab
  builder
  scanner
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
  #measurementWidget
  protocolWidget
  dataViewerWidget
  rawDataWidget
  recoWidget
  scannerBrowser
  currentAnatomRefFilename
  sfViewerWidget
  updating
end

Base.show(io::IO, f::MPILab) = print(io, "MPILab")

getindex(m::MPILab, w::AbstractString) = G_.object(m.builder, w)

mpilab = Ref{MPILab}()

activeDatasetStore(m::MPILab) = m.datasetStores[m.activeStore]
activeRecoStore(m::MPILab) = typeof(activeDatasetStore(m)) <: BrukerDatasetStore ?
                                      m.brukerRecoStore : activeDatasetStore(m)

function loaddata(filename)
  file, ext = splitext(filename)
  if ext == ".nii"
    loaddata_analyze(filename)
  else
    loadRecoData(filename)
  end
end


function MPILab(offlineMode=false)::MPILab
   
  mkpath(logpath)
  logger = TeeLogger(
    MinLevelLogger(ConsoleLogger(), Logging.Info),
    MinLevelLogger(
      DatetimeRotatingFileLogger(logpath, raw"\m\p\i\l\a\b-YYYY-mm-dd.\l\o\g"), 
        Logging.Debug)
  );
  global_logger(logger)

  @info "Starting MPILab"

  uifile = joinpath(@__DIR__,"builder","mpiLab.ui")

  m_ = MPILab( Builder(filename=uifile), nothing, 1, DatasetStore[],
              nothing, nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, false, false, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, nothing, "", nothing, false)

  let m=m_

  mpilab[] = m

  w = m["mainWindow"]

  @static if Sys.islinux()
    defaultConfigPath = expanduser("~/.mpilab/configs")
  else
    defaultConfigPath = joinpath(homedir(), ".mpilab\\configs")
  end

  addConfigurationPath(defaultConfigPath)

  @debug "## Init Settings ..."
  initSettings(m)
  @debug "## Init Scanner ..."
  initScanner(m, offlineMode)
  @debug "## Init Scanner Tab ..."
  initScannerTab(m)
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
  @debug "## Init Protocol Tab ..."
  initProtocolTab(m)


  @idle_add set_gtk_property!(m["lbInfo"],:use_markup,true)
  @idle_add set_gtk_property!(m["cbDatasetStores"],:active,0)
  infoMessage(m, "")

  # ugly but necessary since showall unhides all widgets
  #@idle_add visible(m["boxMeasTab"],
  #    isMeasurementStore(m.measurementWidget,activeDatasetStore(m)) )
  #@idle_add visible(m["tbOpenMeasurementTab"],
  #        isMeasurementStore(m.measurementWidget,activeDatasetStore(m)) )

  # Set the icon of MPILab
  Gtk.GError() do error_check
    filename = joinpath(@__DIR__,"assets","MPILabIcon.png")
    G_.icon_from_file(w, filename, error_check)
    return true
  end

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


  
  signal_connect(w, "delete-event") do widget, event
    if m.protocolWidget != nothing && m.scanner != nothing
      close(m.scanner)
      #stopSurveillance(m.measurementWidget) # TODO I think this is now in the scanner browser
    end
    return false
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
    @info "changing dataset store"
    
    m.activeStore = get_gtk_property(m["cbDatasetStores"], :active, Int64)+1
    @idle_add begin
      m.updating = true
      scanDatasetDir(m)
      updateData!(m.sfBrowser,activeDatasetStore(m))

      if !isnothing(m.protocolWidget)
        visible(m["tbProtocolTab"],
          isMeasurementStore(m.protocolWidget,activeDatasetStore(m)))
      end

      if length(m.studyStore) > 0
        # select first study so that always measurements can be performed
        iter = Gtk.mutable(Gtk.GtkTreeIter)
        Gtk.get_iter_first( TreeModel(m.studyStoreSorted) , iter)
        select!(m.selectionStudy, iter)
      end
      m.updating = false
    end
    return nothing
  end

  return nothing
end

function initViewSwitch(m::MPILab)
  signal_connect(m["nbView"], "switch-page") do widget, page, page_num
    @debug "switched to tab" page_num
    if page_num == 0
      infoMessage(m, "")
      if m.currentExperiment != nothing
        @idle_add updateData(m.rawDataWidget, path(m.currentExperiment))
      end
    elseif page_num == 1
      infoMessage(m, "")
    elseif page_num == 2
      infoMessage(m, "")
      if m.currentExperiment != nothing
        @idle_add updateData!(m.recoWidget, path(m.currentExperiment) )
      end
    elseif page_num == 4
      # TODO scanner? Previously was measurementWidget
    elseif page_num == 5
      # TODO Protocol
      #@idle_add unselectall!(m.selectionExp)
      #m.currentExperiment = nothing
      #infoMessage(m, m.measurementWidget.message)
    end
    return nothing
  end

  updatingTab = false

  signal_connect(m["tbDataTab"], "clicked") do widget
    if !updatingTab
      @idle_add begin
          updatingTab = true
          G_.current_page(m["nbView"], 0)
          G_.current_page(m["nbData"], 0)
          set_gtk_property!(m["tbDataTab"], :active, true)
          set_gtk_property!(m["tbCalibrationTab"], :active, false)
          set_gtk_property!(m["tbScannerTab"], :active, false)
          set_gtk_property!(m["tbProtocolTab"], :active, false)
          visible(m["panedReco"],true)
          updatingTab = false
      end
    end
  end

  signal_connect(m["tbCalibrationTab"], "clicked") do widget
    if !updatingTab
      @idle_add begin
          updatingTab = true
          G_.current_page(m["nbView"], 3)
          G_.current_page(m["nbData"], 1)
          set_gtk_property!(m["tbDataTab"], :active, false)
          set_gtk_property!(m["tbCalibrationTab"], :active, true)
          set_gtk_property!(m["tbScannerTab"], :active, false)
          set_gtk_property!(m["tbProtocolTab"], :active, false)
          visible(m["panedReco"],false)
          updatingTab = false
      end
    end
  end

  signal_connect(m["tbScannerTab"], "clicked") do widget
    if !updatingTab
      @idle_add begin
          updatingTab = true
          G_.current_page(m["nbView"], 4)
          G_.current_page(m["nbData"], 2)
          set_gtk_property!(m["tbDataTab"], :active, false)
          set_gtk_property!(m["tbCalibrationTab"], :active, false)
          set_gtk_property!(m["tbScannerTab"], :active, true)
          set_gtk_property!(m["tbProtocolTab"], :active, false)
          updatingTab = false
      end
    end
  end

  signal_connect(m["tbProtocolTab"], "clicked") do widget
    if !updatingTab
      @idle_add begin
          updatingTab = true
          G_.current_page(m["nbView"], 5)
          G_.current_page(m["nbData"], 0)
          set_gtk_property!(m["tbDataTab"], :active, false)
          set_gtk_property!(m["tbCalibrationTab"], :active, false)
          set_gtk_property!(m["tbScannerTab"], :active, false)
          set_gtk_property!(m["tbProtocolTab"], :active, true)
          visible(m["panedReco"],false) # is this necessary?
          updatingTab = false
      end
    end
  end


  return nothing
end

function reinit(m::MPILab)
  #m.brukerStore = BrukerDatasetStore( m.settings["datasetDir"] )
  #m.mdfStore = MDFDatasetStore( m.settings["reconstructionDir"] )


  scanDatasetDir(m)
end

function initStudyStore(m::MPILab)

  m.studyStore = ListStore(String,String,String,String,String,Bool)

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
  G_.visible_column(tmFiltered,5)
  m.studyStoreSorted = TreeModelSort(tmFiltered)
  G_.model(tv, m.studyStoreSorted)

  m.selectionStudy = G_.selection(tv)

  #G_.sort_column_id(TreeSortable(m.studyStore),0,GtkSortType.ASCENDING)
  G_.sort_column_id(TreeSortable(m.studyStoreSorted),0,GtkSortType.DESCENDING)


  if length(m.studyStore) > 0
    # select first study so that always measurements can be performed
    iter = Gtk.mutable(Gtk.GtkTreeIter)
    Gtk.get_iter_first( TreeModel(m.studyStoreSorted) , iter)
    @idle_add select!(m.selectionStudy, iter)
  end

  function selectionChanged( widget )
    if !m.updating && hasselection(m.selectionStudy) && !m.clearingStudyStore 
      m.updating = true
      currentIt = selected( m.selectionStudy )

      m.currentStudy = Study(activeDatasetStore(m), 
                             TreeModel(m.studyStoreSorted)[currentIt,2];
                             foldername = TreeModel(m.studyStoreSorted)[currentIt,4],
                             subject = TreeModel(m.studyStoreSorted)[currentIt,3],
                             date = DateTime(string(TreeModel(m.studyStoreSorted)[currentIt,1],"T",
				                           TreeModel(m.studyStoreSorted)[currentIt,5])))

      updateExperimentStore(m, m.currentStudy)

      @debug "Current Study Id: " m.currentStudy.name
      updateAnatomRefStore(m)

      if !isnothing(m.protocolWidget)
        m.protocolWidget.currStudyName = m.currentStudy.name
        m.protocolWidget.currStudyDate = m.currentStudy.date
      end
      m.updating = false
    end
  end

  signal_connect(m.selectionStudy, "changed") do widget
    @idle_add selectionChanged(widget)
  end

  function updateShownStudies( widget )
    if !m.updating
      @idle_add begin
        m.updating = true
        unselectall!(m.selectionExp)
        unselectall!(m.selectionStudy)
        unselectall!(m.selectionVisu)
        unselectall!(m.selectionReco)
        empty!(m.experimentStore)
        empty!(m.reconstructionStore)
        empty!(m.visuStore)

        studySearchText = get_gtk_property(m["entSearchStudies"], :text, String)

        for l=1:length(m.studyStore)
          showMe = true

          if length(studySearchText) > 0
            showMe = showMe && occursin(lowercase(studySearchText),
                                lowercase(m.studyStore[l,2]))
          end

          m.studyStore[l,6] = showMe
        end
        m.updating = false
      end
    end
  end

  signal_connect(updateShownStudies, m["entSearchStudies"], "changed")

  signal_connect(m["tbRemoveStudy"], "clicked") do widget
    if hasselection(m.selectionStudy)
      if ask_dialog("Do you really want to delete the study $(m.currentStudy.name)?", mpilab[]["mainWindow"])
        remove(m.currentStudy)

        # TODO
        #currentIt = selected( m.selectionStudy )
        #@idle_add delete!(TreeModel(m.studyStoreSorted), currentIt)

        @idle_add scanDatasetDir(m)
      end
    end
  end


  signal_connect(m["tbAddStudy"], "clicked") do widget
    name = get_gtk_property(m["entSearchStudies"], :text, String)
    study = Study(activeDatasetStore(m), name)
    addStudy(activeDatasetStore(m), study)
    @idle_add scanDatasetDir(m)

    iter = Gtk.mutable(Gtk.GtkTreeIter)
    Gtk.get_iter_first( TreeModel(m.studyStoreSorted) , iter)
    for l=1:length(m.studyStore)
      if TreeModel(m.studyStoreSorted)[iter,2] == name
        break
      else
        Gtk.get_iter_next( TreeModel(m.studyStoreSorted) , iter)
      end
    end

    @idle_add select!(m.selectionStudy, iter)
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
    push!(m.studyStore, (split(string(study.date),"T")[1], study.name, study.subject,
			  study.foldername, split(string(study.date),"T")[2], true))
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
      targetPath = joinpath(activeRecoStore(m).path, "reconstructions", getMDFStudyFolderName(m.currentStudy),
						     "anatomicReferences", last(splitdir(filename)) )
      mkpath(targetPath)
      try_chmod(targetPath, 0o777, recursive=true)
      cp(filename, targetPath, force=true)
      @idle_add updateAnatomRefStore(m)
    end

  end

  signal_connect(tv, "row-activated") do treeview, path_, col, other...
    try
      if hasselection(selection)
        currentIt = selected( selection )

        name = m.anatomRefStore[currentIt,1]
        filename = m.anatomRefStore[currentIt,2]

        im = loaddata(filename)
        im_ = copyproperties(im,squeeze(data(im)))
        @idle_add DataViewer(im_)
      end
    catch ex
      showError(ex)
    end
    false
  end

  signal_connect(m.selectionAnatomicRefs, "changed") do widget
    if !m.updating && hasselection(m.selectionAnatomicRefs)
      currentIt = selected( m.selectionAnatomicRefs )

      m.currentAnatomRefFilename = m.anatomRefStore[currentIt,2]
    end
  end
end


function updateAnatomRefStore(m::MPILab)
  if m.anatomRefStore != nothing
      empty!(m.anatomRefStore)

      currentPath = joinpath(activeRecoStore(m).path, "reconstructions", getMDFStudyFolderName(m.currentStudy),
    						  "anatomicReferences" )

      if isdir(currentPath)
        files = readdir(currentPath)

        for file in files
          name, ext = splitext(file)
          if (isfile(joinpath(currentPath,file)) &&
               (ext == ".hdf" || ext == ".mdf" ||ext == ".nii" || ext == ".dcm") ) ||
             (isdir(joinpath(currentPath,file)) && isfile(joinpath(currentPath,file),"acqp"))
            push!(m.anatomRefStore, (name,joinpath(currentPath,file)))
          end
        end
      end
  end
  nothing
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
      @idle_add begin
        updateData(m.rawDataWidget, path(m.currentExperiment))
        G_.current_page(m["nbView"], 0)
      end
    end
  end


  signal_connect(m["tbReco"], "clicked") do widget
    if hasselection(m.selectionExp)
      @idle_add begin
        if m.settings["enableRecoStore", true]
          updateData!(m.recoWidget, path(m.currentExperiment), m.currentStudy, m.currentExperiment )
          G_.current_page(m["nbView"], 2)
        end
      end
    end
  end

  signal_connect(m["tbOpenExperimentFolder"], "clicked") do widget
    if hasselection(m.selectionStudy)
      @idle_add begin
        openFileBrowser(path(m.currentStudy))
      end
    end
  end


  signal_connect(tv, "row-activated") do treeview, path_, col, other...
    if hasselection(m.selectionExp)
      @idle_add begin
        #updateData!(m.recoWidget, path(m.currentExperiment) )
        @info path(m.currentExperiment)
        updateData(m.rawDataWidget, path(m.currentExperiment))
        G_.current_page(m["nbView"], 0)
      end
    end
    false
  end

  signal_connect(m.selectionExp, "changed") do widget
    if !m.updating && hasselection(m.selectionExp) && !m.clearingStudyStore &&
       m.currentStudy != nothing && !m.clearingExpStore

      currentIt = selected( m.selectionExp )
      
      exp = getExperiment(m.currentStudy, m.experimentStore[currentIt,1])

      if exp != nothing && ispath(path(exp))
         m.currentExperiment = exp

         @idle_add updateReconstructionStore(m)
         #@idle_add updateAnatomRefStore(m)

         @idle_add begin
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
      m.updating = false
    end
  end


  signal_connect(m["tbRemoveExp"], "clicked") do widget
    if hasselection(m.selectionExp)
      if ask_dialog("Do you really want to delete the experiment $(m.currentExperiment.num)?")
        remove(m.currentExperiment)

        @idle_add updateExperimentStore(m, m.currentStudy)
      end
    end
  end

  signal_connect(r2, "edited") do widget, path_, text
    try
    if hasselection(m.selectionExp)
      currentIt = selected( m.selectionExp )
      if splitext(path(m.currentExperiment))[2] == ".mdf"
        @idle_add m.experimentStore[currentIt,2] = string(text)
        Base.GC.gc() # This is important to run all finalizers of MPIFile
        h5open(path(m.currentExperiment), "r+") do file
          if haskey(file, "/experiment/name")
            delete_object(file, "/experiment/name")
          end
          write(file, "/experiment/name", string(text) )
          @info "changed experiment name"
        end
      end
    end
    catch ex
      showError(ex)
    end
  end

end

function updateExperimentStore(m::MPILab, study::Study)
  if m.experimentStore == nothing || m.reconstructionStore == nothing ||
     m.visuStore == nothing
     return
  end

  @idle_add begin
    m.clearingExpStore = true
    m.updating = true  
    unselectall!(m.selectionExp)
    empty!(m.experimentStore)
    empty!(m.reconstructionStore)
    empty!(m.visuStore)

    experiments = getExperiments(study)

    for exp in experiments
      push!(m.experimentStore,(exp.num, exp.name, exp.numFrames,
                join(exp.df,"x"),exp.sfGradient, path(exp)))
    end
    m.clearingExpStore = false
    m.updating = false
  end
  return
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

  signal_connect(tv, "row-activated") do treeview, path_, col, other...
    if hasselection(m.selectionReco)
      im = loaddata(m.currentReco.path)
      #@idle_add DataViewer(im)
      @idle_add begin
         updateData!(m.dataViewerWidget, im)
         G_.current_page(m["nbView"], 1)
      end
    end
    false
  end

  signal_connect(r2, "edited") do widget, path_, text
    @debug "" text
    if hasselection(m.selectionReco)
      currentIt = selected( m.selectionReco )

      @idle_add m.reconstructionStore[currentIt,3] = string(text)
    end
    m.currentReco.params[:description] = string(text)
    save(m.currentReco)
    #@idle_add updateReconstructionStore(m)
  end

  signal_connect(m.selectionReco, "changed") do widget
    if !m.updating && hasselection(m.selectionReco) && 
        m.currentStudy != nothing && m.currentExperiment != nothing

      currentIt = selected( m.selectionReco )

      recoNum = m.reconstructionStore[currentIt,1]

      m.currentReco = getReco(activeRecoStore(m), m.currentStudy, m.currentExperiment, recoNum)

      if isfile(m.currentReco.path)
        im = loaddata(m.currentReco.path)
        #@idle_add DataViewer(im)
        #@idle_add begin
        #   updateData!(m.dataViewerWidget, im)
        #   G_.current_page(m["nbView"], 1)
        #end
      end
    end

    @idle_add updateVisuStore(m)
    return false
  end

  signal_connect(m["tbRemoveReco"], "clicked") do widget
    if hasselection(m.selectionReco)
      remove(m.currentReco)

      @idle_add updateReconstructionStore(m)
    end
  end

  signal_connect(m["tbOpenFusion"], "clicked") do widget
    openFusion(m)
  end

  signal_connect(m["tbRedoReco"], "clicked") do widget
    if hasselection(m.selectionReco)
      params = m.currentReco.params

      @idle_add begin
        updateData!(m.recoWidget, path(m.currentExperiment), params, m.currentStudy, m.currentExperiment)
        G_.current_page(m["nbView"], 2)
      end
    end
  end

  signal_connect(m["tbExportRecoData"], "clicked") do widget
   try
    if hasselection(m.selectionReco)
      filter = Gtk.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
      filenameData = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
      if filenameData != ""
        image = sliceColorDim( loaddata(m.currentReco.path), 1)
        file, ext = splitext(filenameData)
        savedata_analyze(string(file,".nii"), image)
      end
    end
   catch e
    @info e
    showError(e)
   end
  end

end

function openFusion(m::MPILab)
    if hasselection(m.selectionReco) &&
       (isfile(m.currentAnatomRefFilename) ||
         (isdir(m.currentAnatomRefFilename) &&
	   isfile(m.currentAnatomRefFilename,"acqp")))
      try
        imFG = loaddata(m.currentReco.path)
        currentIt = selected( m.selectionAnatomicRefs )

        imBG = loaddata(m.currentAnatomRefFilename)
        imBG_ = copyproperties(imBG,squeeze(data(imBG)))

        imBG_["filename"] = m.currentAnatomRefFilename #last(splitdir(filename))

        #DataViewer(imFG, imBG_)

        @idle_add begin
           updateData!(m.dataViewerWidget, imFG, imBG_)
           G_.current_page(m["nbView"], 1)
        end
      catch ex
        @show  string("Something went wrong!\n", ex, "\n\n", stacktrace(bt))
        #showError(ex)
      end
    end
end


function updateReconstructionStore(m::MPILab)
  if m.reconstructionStore == nothing
    return
  end

  empty!(m.reconstructionStore)

  recons = getRecons(activeRecoStore(m), m.currentStudy, m.currentExperiment)

  for r in recons
    p = r.params
    push!(m.reconstructionStore, (r.num,string(p[:frames]),get(p,:description,""),
        p[:solver],string(p[:iterations]),string(p[:lambd]),
        string(p[:nAverages]),string(p[:SNRThresh]),get(p,:reconstructor,"")))
  end
  return
end

function addReco(m::MPILab, image, currentStudy, currentExperiment)
  addReco(activeRecoStore(m), m.currentStudy, m.currentExperiment, image)
  @idle_add updateReconstructionStore(m)
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

  signal_connect(tv, "row-activated") do treeview, path_, col, other...
    if hasselection(m.selectionReco)
      if hasselection(m.selectionVisu)

        im = loaddata(m.currentReco.path)

        params = m.currentVisu.params
        if params!=nothing && params[:filenameBG] != ""
          path = joinpath(activeRecoStore(m).path, "reconstructions",
                      getMDFStudyFolderName(m.currentStudy), "anatomicReferences", params[:filenameBG])
          imBG = loaddata(path)
          imBG_ = copyproperties(imBG,squeeze(data(imBG)))
          imBG_["filename"] = path #params[:filenameBG]
        else
          imBG_ = nothing
        end
        #@idle_add DataViewer(im, imBG_, params=m.currentVisu.params)

        @idle_add begin
           updateData!(m.dataViewerWidget, im, imBG_, params=m.currentVisu.params)
           G_.current_page(m["nbView"], 1)
        end
      end
    end

    false
  end

  signal_connect(r2, "edited") do widget, path_, text
    if hasselection(m.selectionVisu)
      currentIt = selected( m.selectionVisu )
      m.currentVisu.params[:description] = string(text)
      @idle_add m.visuStore[currentIt,2] = string(text)
      @idle_add save(m.currentVisu)
    end
  end

  signal_connect(m["tbRemoveVisu"], "clicked") do widget
    if hasselection(m.selectionVisu)
     remove(m.currentVisu)
     @idle_add updateVisuStore(m)
    end
  end

  signal_connect(m.selectionVisu, "changed") do widget
    if !m.updating && hasselection(m.selectionVisu)
      currentIt = selected( m.selectionVisu )

      visuNum = m.visuStore[currentIt,1]

      m.currentVisu = getVisu(activeRecoStore(m), m.currentStudy, m.currentExperiment, m.currentReco, visuNum)
    end
  end
end


function updateVisuStore(m::MPILab)
  if m.visuStore == nothing
    return
  end

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
  return
end

function addVisu(m::MPILab, visuParams)
  if hasselection(m.selectionReco)
    addVisu(activeRecoStore(m), m.currentStudy, m.currentExperiment, m.currentReco, visuParams)
    @idle_add updateVisuStore(m)
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

### Scanner Tab ###
function initScannerTab(m::MPILab)

  m.scannerBrowser = ScannerBrowser(m.scanner, m["boxScannerTab"])

  boxScannerTab = m["boxScanner"]
  push!(boxScannerTab,m.scannerBrowser)
  set_gtk_property!(boxScannerTab, :expand, m.scannerBrowser, true)
  showall(boxScannerTab)
end

### Protocol Tab ###

function initProtocolTab(m::MPILab)
  m.protocolWidget = ProtocolWidget(m.scanner)

  boxProtoTab = m["boxProtocolTab"]
  push!(boxProtoTab, m.protocolWidget)
  set_gtk_property!(boxProtoTab, :expand, m.protocolWidget, true)
  showall(boxProtoTab)
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

function initScanner(m::MPILab, offlineMode::Bool)
  settings = offlineMode ? "" : m.settings["scanner"]
  scanner = nothing
  if settings != ""
    scanner = MPIScanner(settings)
  end
  m.scanner = scanner
end

function infoMessage(m::MPILab, message::String, color::String)
  infoMessage(m, """<span foreground="$color" font_weight="bold" size="x-large">$message</span>""")
end

function infoMessage(m::MPILab, message::String)
  @idle_add set_gtk_property!(m["lbInfo"],:label, message)
end

function progress(m::MPILab, startStop::Bool)
  @idle_add set_gtk_property!(m["spProgress"],:active, startStop)
end

function scanner(m::MPILab)
  return m.scanner
end