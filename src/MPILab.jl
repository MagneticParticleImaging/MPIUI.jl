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
  logMessagesWidget
  updating
end

Base.show(io::IO, f::MPILab) = print(io, "MPILab")

getindex(m::MPILab, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)

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
   
  @info "Starting MPILab"

  if Threads.nthreads() < 4 && !offlineMode
    error("Too few threads to run MPIUI with an active scanner")
  end

  uifile = joinpath(@__DIR__,"builder","mpiLab.ui")

  m_ = MPILab( GtkBuilder(filename=uifile), nothing, 1, DatasetStore[],
              nothing, nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, nothing, nothing,
              nothing, nothing, false, false, nothing, nothing, nothing, nothing,
              nothing, nothing, nothing, nothing, "", nothing, nothing, false)

  let m=m_

  mpilab[] = m

  w = m["mainWindow"]
  set_gtk_property!(w, :sensitive, false)

  @idle_add_guarded show(w)

  addConfigurationPath(scannerpath)

  @debug "## Init Logging ..."
  initLogging(m)
  @debug "## Init Settings ..."
  initSettings(m)
  @debug "## Init Scanner ..."
  initScanner(m, offlineMode)
  @debug "## Init Scanner Tab ..."
  initScannerTab(m, offlineMode)
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
  initProtocolTab(m, offlineMode)

  if !offlineMode && !(scannerDatasetStore(m.scanner) in m.settings["datasetStores"])
    @warn "The scanner's dataset store `$(scannerDatasetStore(m.scanner))` does not match one of the stores in the Settings.toml."
  end

  @idle_add_guarded set_gtk_property!(m["lbInfo"],:use_markup,true)
  @idle_add_guarded set_gtk_property!(m["cbDatasetStores"],:active,0)
  infoMessage(m, "")

  # ugly but necessary since show unhides all widgets
  #@idle_add_guarded visible(m["boxMeasTab"],
  #    isMeasurementStore(m.measurementWidget,activeDatasetStore(m)) )
  #@idle_add_guarded visible(m["tbOpenMeasurementTab"],
  #        isMeasurementStore(m.measurementWidget,activeDatasetStore(m)) )

  # Set the icon of MPILab
###  Gtk4.GError() do error_check
###    filename = joinpath(@__DIR__,"assets","MPILabIcon.png")
###    G_.icon_from_file(w, filename, error_check)
###    return true
###  end

 #= signal_connect(w, "key-press-event") do widget, event
    if event.keyval ==  Gtk4.GConstants.GDK_KEY_c
      if event.state & 0x04 != 0x00 # Control key is pressed
        @debug "copy visu params to clipboard..."
        str = string( getParams(m.dataViewerWidget) )
        clipboard( str )
      end
    elseif event.keyval == Gtk4.GConstants.GDK_KEY_v
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
  end =#


  
  signal_connect(w, "close-request") do widget #, event
    if m.protocolWidget != nothing && m.scanner != nothing
      close(m.scanner)
      #stopSurveillance(m.measurementWidget) # TODO I think this is now in the scanner browser
    end
    return #false
  end

  @info "Finished starting MPILab"

  set_gtk_property!(w, :sensitive, true)
  w.sensitive = true

  end

  return m_
end

datetime_logger(logger) = TransformerLogger(logger) do log
  merge(log, (; kwargs = (; log.kwargs..., dateTime = now())))
end

datetimeFormater_logger(logger) = TransformerLogger(logger) do log
  dateTime = nothing
  for (key, val) in log.kwargs
    if key === :dateTime
      dateTime = val
    end
  end
  kwargs = [p for p in pairs(log.kwargs) if p[1] != :dateTime]
  merge(log, (; kwargs = kwargs, message = "$(Dates.format(dateTime, dateTimeFormatter)) $(log.message)"))
end

function initLogging(m::MPILab)
  # Setup Logging Widget
  m.logMessagesWidget = LogMessageListWidget()
  pane = m["paneMain"]
  G_.set_end_child(pane, m.logMessagesWidget)
  set_gtk_property!(pane, :position, 550)

  # Setup Loggers
  mkpath(logpath)
  logger = datetime_logger(TeeLogger(
    datetimeFormater_logger(
        TeeLogger(
        MinLevelLogger(ConsoleLogger(), Logging.Info),
        MinLevelLogger(DatetimeRotatingFileLogger(logpath, raw"\m\p\i\l\a\b-YYYY-mm-dd.\l\o\g"),
            Logging.Debug)
      )
    ),
    WidgetLogger(m.logMessagesWidget)
  ))
  global_logger(logger)
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
    @idle_add_guarded begin
      m.updating = true
      scanDatasetDir(m)
      updateData!(m.sfBrowser,activeDatasetStore(m))

      if !isnothing(m.protocolWidget)
        visible(m["tbProtocolTab"],
          isMeasurementStore(m.protocolWidget,activeDatasetStore(m)))
      end

      if length(m.studyStore) > 0
        # select first study so that always measurements can be performed
###        iter = Gtk4.mutable(Gtk4.GtkTreeIter)
###        Gtk4.get_iter_first( GtkTreeModel(m.studyStoreSorted) , iter)
###        select!(m.selectionStudy, iter)
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
        @idle_add_guarded updateData(m.rawDataWidget, path(m.currentExperiment))
      end
    elseif page_num == 1
      infoMessage(m, "")
    elseif page_num == 2
      infoMessage(m, "")
      if m.currentExperiment != nothing
        @idle_add_guarded updateData!(m.recoWidget, path(m.currentExperiment) )
      end
    elseif page_num == 4
      # TODO scanner? Previously was measurementWidget
    elseif page_num == 5
      # TODO Protocol
      #@idle_add_guarded unselectall!(m.selectionExp)
      #m.currentExperiment = nothing
      #infoMessage(m, m.measurementWidget.message)
    end
    return nothing
  end

  updatingTab = false

  signal_connect(m["tbDataTab"], "clicked") do widget
    if !updatingTab
      @idle_add_guarded begin
          updatingTab = true
          Gtk4.G_.set_current_page(m["nbView"], 0)
          Gtk4.G_.set_current_page(m["nbData"], 0)
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
      @idle_add_guarded begin
          updatingTab = true
          Gtk4.G_.set_current_page(m["nbView"], 3)
          Gtk4.G_.set_current_page(m["nbData"], 1)
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
      @idle_add_guarded begin
          updatingTab = true
          Gtk4.G_.set_current_page(m["nbView"], 4)
          Gtk4.G_.set_current_page(m["nbData"], 2)
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
      @idle_add_guarded begin
          updatingTab = true
          Gtk4.G_.set_current_page(m["nbView"], 5)
          Gtk4.G_.set_current_page(m["nbData"], 0)
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

  m.studyStore = GtkListStore(String,String,String,String,String,Bool)

  tv = GtkTreeView(GtkTreeModel(m.studyStore))
  #G_.headers_visible(tv,false)
  r1 = GtkCellRendererText()

  cols = ["Date", "Study", "Subject", "Time"]
  colMap = [0,1,2,4]

  for (i,col) in enumerate(cols)
    c = GtkTreeViewColumn(col, r1, Dict("text" => colMap[i]))
    G_.set_sort_column_id(c,colMap[i])
    G_.set_resizable(c,true)
    G_.set_max_width(c,300)
    push!(tv,c)
  end

  #Gtk4.add_attribute(c1,r2,"text",0)
  #G_.set_sort_column_id(c1,0)
  #G_.set_resizable(c1,true)
  #G_.set_max_width(c1,80)

  sw = m["swStudy"]
  G_.set_child(sw,tv)
  show(sw)


  scanDatasetDir(m)

  tmFiltered = GtkTreeModelFilter(GtkTreeModel(m.studyStore))
  G_.set_visible_column(tmFiltered,5)
  m.studyStoreSorted = GtkTreeModelSort(tmFiltered)
  G_.set_model(tv, GtkTreeModel(m.studyStoreSorted))

  m.selectionStudy = G_.get_selection(tv)

  #G_.set_sort_column_id(GtkTreeSortable(m.studyStore),0,GtkSortType.ASCENDING)
  G_.set_sort_column_id(GtkTreeSortable(m.studyStoreSorted),0, Gtk4.SortType_DESCENDING)


  if length(m.studyStore) > 0
    # select first study so that always measurements can be performed
   ### iter = Gtk4.mutable(Gtk4.GtkTreeIter)
   ### Gtk4.get_iter_first( GtkTreeModel(m.studyStoreSorted) , iter)
   ### @idle_add_guarded select!(m.selectionStudy, iter)
  end

  function selectionChanged( widget )
    if !m.updating && hasselection(m.selectionStudy) && !m.clearingStudyStore 
      m.updating = true
      currentIt = selected( m.selectionStudy )

      m.currentStudy = Study(activeDatasetStore(m), 
                             GtkTreeModel(m.studyStoreSorted)[currentIt,2];
                             foldername = GtkTreeModel(m.studyStoreSorted)[currentIt,4],
                             subject = GtkTreeModel(m.studyStoreSorted)[currentIt,3],
                             date = DateTime(string(GtkTreeModel(m.studyStoreSorted)[currentIt,1],"T",
				                           GtkTreeModel(m.studyStoreSorted)[currentIt,5])))

      updateExperimentStore(m, m.currentStudy)

      @debug "Current Study Id: " m.currentStudy.name
      updateAnatomRefStore(m)

      if !isnothing(m.protocolWidget)
        updateStudy(m.protocolWidget, m.currentStudy.name, m.currentStudy.date)
      end
      m.updating = false
    end
  end

  signal_connect(m.selectionStudy, "changed") do widget
    @idle_add_guarded selectionChanged(widget)
  end

  function updateShownStudies( widget )
    if !m.updating
      @idle_add_guarded begin
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
        #@idle_add_guarded delete!(GtkTreeModel(m.studyStoreSorted), currentIt)

        @idle_add_guarded scanDatasetDir(m)
      end
    end
  end


  signal_connect(m["tbAddStudy"], "clicked") do widget
    name = get_gtk_property(m["entSearchStudies"], :text, String)
    study = Study(activeDatasetStore(m), name)
    addStudy(activeDatasetStore(m), study)
    @idle_add_guarded scanDatasetDir(m)

    iter = Gtk4.mutable(Gtk4.GtkTreeIter)
    Gtk4.get_iter_first( GtkTreeModel(m.studyStoreSorted) , iter)
    for l=1:length(m.studyStore)
      if GtkTreeModel(m.studyStoreSorted)[iter,2] == name
        break
      else
        Gtk4.get_iter_next( GtkTreeModel(m.studyStoreSorted) , iter)
      end
    end

    @idle_add_guarded select!(m.selectionStudy, iter)
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

  m.anatomRefStore = GtkListStore(String, String)

  tv = GtkTreeView(GtkTreeModel(m.anatomRefStore))
  r1 = GtkCellRendererText()

  cols = ["Name"]

  for (i,col) in enumerate(cols)
    c = GtkTreeViewColumn(col, r1, Dict("text" => i-1))
    G_.set_sort_column_id(c,i-1)
    G_.set_resizable(c,true)
    G_.set_max_width(c,300)
    push!(tv,c)
  end


  sw = m["swAnatomData"]
  G_.set_child(sw,tv)
  show(sw)

  G_.set_sort_column_id(GtkTreeSortable(m.anatomRefStore),0,Gtk4.SortType_ASCENDING)

  selection = G_.get_selection(tv)
  m.selectionAnatomicRefs = selection

  signal_connect(m["tbAddAnatomicalData"], "clicked") do widget
    diag = open_dialog("Select Anatomic Reference", mpilab[]["mainWindow"], action=Gtk4.FileChooserAction_OPEN) do filename
      if !isfile(filename)
        @warn "$filename * is not a file"
      else
        targetPath = joinpath(activeRecoStore(m).path, "reconstructions", getMDFStudyFolderName(m.currentStudy),
                  "anatomicReferences", last(splitdir(filename)) )
        mkpath(targetPath)
        try_chmod(targetPath, 0o777, recursive=true)
        cp(filename, targetPath, force=true)
        @idle_add_guarded updateAnatomRefStore(m)
      end
    end
    diag.modal = true
  end

  signal_connect(tv, "row-activated") do treeview, path_, col, other...
    try
      if hasselection(selection)
        currentIt = selected( selection )

        name = m.anatomRefStore[currentIt,1]
        filename = m.anatomRefStore[currentIt,2]

        im = loaddata(filename)
        im_ = copyproperties(im,squeeze(data(im)))
        @idle_add_guarded DataViewer(im_)
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

  m.experimentStore = GtkListStore(Int64,String,Int64,String,
                                 Float64,String)
  tmFiltered = nothing

  tv = GtkTreeView(GtkTreeModel(m.experimentStore))
  r1 = GtkCellRendererText()
  r2 = GtkCellRendererText()
  set_gtk_property!(r2, :editable, true)

  cols = ["Num", "Name", "Frames", "DF", "Grad"]

  for (i,col) in enumerate(cols)

    if i==2 #magic number
      c = GtkTreeViewColumn(col, r2, Dict("text" => i-1))
    else
      c = GtkTreeViewColumn(col, r1, Dict("text" => i-1))
    end

    G_.set_sort_column_id(c,i-1)
    G_.set_resizable(c,true)
    G_.set_max_width(c,300)
    push!(tv,c)
  end

  sw = m["swExp"]
  G_.set_child(sw, tv)
  show(sw)

  G_.set_sort_column_id(GtkTreeSortable(m.experimentStore),0,Gtk4.SortType_ASCENDING)

  m.selectionExp = G_.get_selection(tv)
  G_.set_mode(m.selectionExp, Gtk4.SelectionMode_MULTIPLE)


  signal_connect(m["tbReco"], "clicked") do widget
    if hasselection(m.selectionExp)
      @idle_add_guarded begin
        if m.settings["enableRecoStore", true]
          updateData!(m.recoWidget, path(m.currentExperiment), m.currentStudy, m.currentExperiment )
          Gtk4.G_.set_current_page(m["nbView"], 2)
        end
      end
    end
  end

  signal_connect(m["tbOpenExperimentFolder"], "clicked") do widget
    if hasselection(m.selectionStudy)
      @idle_add_guarded begin
        openFileBrowser(path(m.currentStudy))
      end
    end
  end


  signal_connect(tv, "row-activated") do treeview, path_, col, other...
    showRawData()
    false
  end

  signal_connect(m["tbRawData"], "clicked") do widget
    showRawData()
  end

  function showRawData()
    if hasselection(m.selectionExp)
      @idle_add_guarded begin
        selectedRows = Gtk4.selected_rows(m.selectionExp)
        expNums = [m.experimentStore[selectedRows[j],1] for j=1:length(selectedRows)]
        exps = [getExperiment(m.currentStudy, expNums[j]) for j=1:length(selectedRows)]
        paths = path.(exps)

        updateData(m.rawDataWidget, paths)
        Gtk4.G_.set_current_page(m["nbView"], 0)
      end
    end
  end

  signal_connect(m["tbSpectrogramViewer"], "clicked") do widget
    showSpectrogram()
  end

  function showSpectrogram()
    if hasselection(m.selectionExp)
      @idle_add_guarded begin
        selectedRows = Gtk4.selected_rows(m.selectionExp)
        expNums = [m.experimentStore[selectedRows[j],1] for j=1:length(selectedRows)]
        exps = [getExperiment(m.currentStudy, expNums[j]) for j=1:length(selectedRows)]
        paths = path.(exps)

        SpectrogramViewer(paths[1])
      end
    end
  end


  signal_connect(m.selectionExp, "changed") do widget
    if !m.updating && hasselection(m.selectionExp) && !m.clearingStudyStore &&
      m.currentStudy != nothing && !m.clearingExpStore

      selectedRows = Gtk4.selected_rows(m.selectionExp) # can have multiple selections
      currentIt = selectedRows[1] #selected( m.selectionExp )
      
      exp = getExperiment(m.currentStudy, m.experimentStore[currentIt,1])

      if exp != nothing && ispath(path(exp))
         m.currentExperiment = exp

         @idle_add_guarded updateReconstructionStore(m)
         #@idle_add_guarded updateAnatomRefStore(m)

         @idle_add_guarded begin
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

        @idle_add_guarded updateExperimentStore(m, m.currentStudy)
      end
    end
  end

  signal_connect(r2, "edited") do widget, path_, text
    try
    if hasselection(m.selectionExp)
      selectedRows = Gtk4.selected_rows(m.selectionExp) # can have multiple selections
      currentIt = selectedRows[1] #selected( m.selectionExp )
      if splitext(path(m.currentExperiment))[2] == ".mdf"
        @idle_add_guarded m.experimentStore[currentIt,2] = string(text)
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

  @idle_add_guarded begin
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
      GtkListStore(Int64,String,String,String,String,String,String,String, String)

  tv = GtkTreeView(GtkTreeModel(m.reconstructionStore))
  r1 = GtkCellRendererText()
  r2 = GtkCellRendererText()
  set_gtk_property!(r2, :editable, true)

  cols = ["Num","Frames","Description","Solver","Iter", "Lambda", "Averages", "SNRThresh", "User"]

  for (i,col) in enumerate(cols)

    if i==3 #magic number
      c = GtkTreeViewColumn(col, r2, Dict("text" => i-1))
    else
      c = GtkTreeViewColumn(col, r1, Dict("text" => i-1))
    end

    G_.set_max_width(c,100)
    G_.set_resizable(c,true)
    G_.set_sort_column_id(c,i-1)
    push!(tv,c)
  end

  sw = m["swReco"]
  G_.set_child(sw,tv)
  show(sw)

  G_.set_sort_column_id(GtkTreeSortable(m.reconstructionStore),0,Gtk4.SortType_ASCENDING)

  m.selectionReco = G_.get_selection(tv)

  signal_connect(tv, "row-activated") do treeview, path_, col, other...
    if hasselection(m.selectionReco)
      im = loaddata(m.currentReco.path)
      #@idle_add_guarded DataViewer(im)
      @idle_add_guarded begin
         updateData!(m.dataViewerWidget, im)
         Gtk4.G_.set_current_page(m["nbView"], 1)
      end
    end
    false
  end

  signal_connect(r2, "edited") do widget, path_, text
    @debug "" text
    if hasselection(m.selectionReco)
      currentIt = selected( m.selectionReco )

      @idle_add_guarded m.reconstructionStore[currentIt,3] = string(text)
    end
    m.currentReco.params[:description] = string(text)
    save(m.currentReco)
    #@idle_add_guarded updateReconstructionStore(m)
  end

  signal_connect(m.selectionReco, "changed") do widget
    if !m.updating && hasselection(m.selectionReco) && 
        m.currentStudy != nothing && m.currentExperiment != nothing

      currentIt = selected( m.selectionReco )

      recoNum = m.reconstructionStore[currentIt,1]

      m.currentReco = getReco(activeRecoStore(m), m.currentStudy, m.currentExperiment, recoNum)

      if isfile(m.currentReco.path)
        im = loaddata(m.currentReco.path)
        #@idle_add_guarded DataViewer(im)
        #@idle_add_guarded begin
        #   updateData!(m.dataViewerWidget, im)
        #   Gtk4.G_.set_current_page(m["nbView"], 1)
        #end
      end
    end

    @idle_add_guarded updateVisuStore(m)
    return false
  end

  signal_connect(m["tbRemoveReco"], "clicked") do widget
    if hasselection(m.selectionReco)
      remove(m.currentReco)

      @idle_add_guarded updateReconstructionStore(m)
    end
  end

  signal_connect(m["tbOpenFusion"], "clicked") do widget
    openFusion(m)
  end

  signal_connect(m["tbRedoReco"], "clicked") do widget
    if hasselection(m.selectionReco)
      params = m.currentReco.params

      # get absolute path of system matrices
      if haskey(params, :SFPath)
        params[:SFPath] =  MPIFiles.extendPath.([activeRecoStore(m)],params[:SFPath])
      end

      @idle_add_guarded begin
        updateData!(m.recoWidget, path(m.currentExperiment), params, m.currentStudy, m.currentExperiment)
        Gtk4.G_.set_current_page(m["nbView"], 2)
      end
    end
  end

  signal_connect(m["tbExportRecoData"], "clicked") do widget
   try
    if hasselection(m.selectionReco)
      filter = Gtk4.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
      diag = save_dialog("Select Export File", mpilab[]["mainWindow"], (filter, )) do filenameData
        if filenameData != ""
          image = sliceColorDim( loaddata(m.currentReco.path), 1)
          file, ext = splitext(filenameData)
          savedata_analyze(string(file,".nii"), image)
        end
      end
      diag.modal = true
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

        @idle_add_guarded begin
           updateData!(m.dataViewerWidget, imFG, imBG_)
           Gtk4.G_.set_current_page(m["nbView"], 1)
        end
      catch ex
        @show string("Something went wrong!\n", ex, "\n\n", stacktrace(bt))
        #showError(ex)
        showerror(stdout, ex, catch_backtrace())
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
  @idle_add_guarded updateReconstructionStore(m)
end

### Visualization Store ###

function initVisuStore(m::MPILab)

  m.visuStore = GtkListStore(Int64,String,String,String,String,String)

  tv = GtkTreeView(GtkTreeModel(m.visuStore))
  r1 = GtkCellRendererText()
  r2 = GtkCellRendererText()
  set_gtk_property!(r2, :editable, true)

  cols = ["Num","Description","Spatial MIP","Frame Proj", "Cmap", "Fusion"]

  for (i,col) in enumerate(cols)
    if i==2 #magic number
      c = GtkTreeViewColumn(col, r2, Dict("text" => i-1))
    else
      c = GtkTreeViewColumn(col, r1, Dict("text" => i-1))
    end

    G_.set_sort_column_id(c,i-1)
    push!(tv,c)
  end

  sw = m["swVisu"]
  G_.set_child(sw,tv)
  show(sw)

  G_.set_sort_column_id(GtkTreeSortable(m.visuStore),0,Gtk4.SortType_ASCENDING)

  m.selectionVisu = G_.get_selection(tv)

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
        #@idle_add_guarded DataViewer(im, imBG_, params=m.currentVisu.params)

        @idle_add_guarded begin
           updateData!(m.dataViewerWidget, im, imBG_, params=m.currentVisu.params)
           Gtk4.G_.set_current_page(m["nbView"], 1)
        end
      end
    end

    false
  end

  signal_connect(r2, "edited") do widget, path_, text
    if hasselection(m.selectionVisu)
      currentIt = selected( m.selectionVisu )
      m.currentVisu.params[:description] = string(text)
      @idle_add_guarded m.visuStore[currentIt,2] = string(text)
      @idle_add_guarded save(m.currentVisu)
    end
  end

  signal_connect(m["tbRemoveVisu"], "clicked") do widget
    if hasselection(m.selectionVisu)
     remove(m.currentVisu)
     @idle_add_guarded updateVisuStore(m)
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
                             important_cmaps()[params[:coloring][1].cmap+1], anatomicRef))
    end
  end
  return
end

function addVisu(m::MPILab, visuParams)
  if hasselection(m.selectionReco)
    addVisu(activeRecoStore(m), m.currentStudy, m.currentExperiment, m.currentReco, visuParams)
    @idle_add_guarded updateVisuStore(m)
  end
end


### System Function Store ###


function initSFStore(m::MPILab)

  m.sfBrowser = SFBrowserWidget(true)

  boxSFPane = m["boxSF"]
  push!(boxSFPane,m.sfBrowser.box)
###  set_gtk_property!(boxSFPane, :expand, m.sfBrowser.box, true)
  show(boxSFPane)
end

### Scanner Tab ###
function initScannerTab(m::MPILab, offlineMode=false)
  if !offlineMode
    m.scannerBrowser = ScannerBrowser(m.scanner, m["boxScannerTab"])

    boxScannerTab = m["boxScanner"]
    push!(boxScannerTab, m.scannerBrowser)
    ### set_gtk_property!(boxScannerTab, :expand, m.scannerBrowser, true)
    show(boxScannerTab)
  end
end

### Protocol Tab ###

function initProtocolTab(m::MPILab, offlineMode=false)
  if !offlineMode
    m.protocolWidget = ProtocolWidget(m.scanner)

    boxProtoTab = m["boxProtocolTab"]
    push!(boxProtoTab, m.protocolWidget)
    boxProtoTab.vexpand = boxProtoTab.hexpand = true
###    set_gtk_property!(boxProtoTab, :expand, m.protocolWidget, true)
    show(boxProtoTab)
  end
end

### Image Tab ###


function initImageTab(m::MPILab)

  m.dataViewerWidget = DataViewerWidget()

  boxImageTab = m["boxImageTab"]
  push!(boxImageTab,m.dataViewerWidget)
###  set_gtk_property!(boxImageTab, :expand, m.dataViewerWidget, true)
end

### Raw Data Tab ###

function initRawDataTab(m::MPILab)

  m.rawDataWidget = RawDataWidget()
  boxRawViewer = m["boxRawViewer"]
  push!(boxRawViewer,m.rawDataWidget)  
  show(boxRawViewer)
end

### Reco Data Tab ###

function initRecoTab(m::MPILab)

  m.recoWidget = OfflineRecoWidget()

  boxRecoTab = m["boxRecoTab"]
  push!(boxRecoTab,m.recoWidget)
###  set_gtk_property!(boxRecoTab, :expand, m.recoWidget, true)
end

### Raw Data Tab ###

function initSFViewerTab(m::MPILab)

  m.sfViewerWidget = SFViewerWidget()

  boxSFTab = m["boxSFTab"]
  push!(boxSFTab,m.sfViewerWidget)
###  set_gtk_property!(boxSFTab, :expand, m.sfViewerWidget, true)
  show(boxSFTab)
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
    scanner = MPIScanner(settings, robust = true)
  end
  m.scanner = scanner
end

function infoMessage(m::MPILab, message::String, color::String)
  infoMessage(m, """<span foreground="$color" font_weight="bold" size="x-large">$message</span>""")
end

function infoMessage(m::MPILab, message::String)
  @idle_add_guarded set_gtk_property!(m["lbInfo"],:label, message)
end

function progress(m::MPILab, startStop::Bool)
  @idle_add_guarded set_gtk_property!(m["spProgress"],:active, startStop)
end

function scanner(m::MPILab)
  return m.scanner
end

function updateScanner!(m::MPILab, scanner::MPIScanner)
  m.scanner = scanner
  updateScanner!(m.protocolWidget, scanner)
  updateScanner!(m.scannerBrowser, scanner)
end
