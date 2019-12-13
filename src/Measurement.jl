
mutable struct MeasurementWidget{T} <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::Builder
  scanner::T
  dataBGStore::Array{Float32,4}
  mdfstore::MDFDatasetStore
  currStudyName::String
  currStudyDate::DateTime
  filenameExperiment::String
  rawDataWidget::RawDataWidget
  sequences::Vector{String}
  expanded::Bool
  message::String
end

getindex(m::MeasurementWidget, w::AbstractString, T::Type) = object_(m.builder, w, T)

function isMeasurementStore(m::MeasurementWidget, d::DatasetStore)
  if m.mdfstore == nothing
    return false
  else
    return d.path == m.mdfstore.path
  end
end

function MeasurementWidget(filenameConfig="")
  @info "Starting MeasurementWidget"
  uifile = joinpath(@__DIR__,"builder","measurementWidget.ui")

  #filenameConfig=nothing

  if filenameConfig != ""
    scanner = MPIScanner(filenameConfig)
    scanner.params["Robot"]["doReferenceCheck"] = false
    mdfstore = MDFDatasetStore( getGeneralParams(scanner)["datasetStore"] )
  else
    scanner = nothing
    mdfstore = MDFDatasetStore( "Dummy" )
  end

  b = Builder(filename=uifile)
  mainBox = object_(b, "boxMeasurement",BoxLeaf)

  m = MeasurementWidget( mainBox.handle, b,
                  scanner, zeros(Float32,0,0,0,0), mdfstore, "", now(),
                  "", RawDataWidget(), String[], false, "")
  Gtk.gobject_move_ref(m, mainBox)

  @debug "Type constructed"

  @debug "InvalidateBG"
  invalidateBG(C_NULL, m)

  push!(m["boxMeasTabVisu",BoxLeaf],m.rawDataWidget)
  set_gtk_property!(m["boxMeasTabVisu",BoxLeaf],:expand,m.rawDataWidget,true)

  @debug "Read Sequences"
  @idle_add empty!(m["cbSeFo",ComboBoxTextLeaf])
  m.sequences = String[ splitext(seq)[1] for seq in readdir(sequenceDir())]
  for seq in m.sequences
    @idle_add push!(m["cbSeFo",ComboBoxTextLeaf], seq)
  end
  @idle_add set_gtk_property!(m["cbSeFo",ComboBoxTextLeaf],:active,0)
  combo = m["cbSeFo",ComboBoxTextLeaf]
  cells = Gtk.GLib.GList(ccall((:gtk_cell_layout_get_cells, Gtk.libgtk),
               Ptr{Gtk._GList{Gtk.GtkCellRenderer}}, (Ptr{GObject},), combo))
  set_gtk_property!(cells[1],"max_width_chars", 14)
  set_gtk_property!(combo,"wrap_width", 2)
  #set_gtk_property!(cells[1],"ellipsize_set", 2)

  @debug "Read safety parameters"
  @idle_add empty!(m["cbSafeCoil", ComboBoxTextLeaf])
  for coil in getValidHeadScannerGeos()
      @idle_add push!(m["cbSafeCoil",ComboBoxTextLeaf], coil.name)
  end
  @idle_add set_gtk_property!(m["cbSafeCoil",ComboBoxTextLeaf], :active, 0)
  @idle_add empty!(m["cbSafeObject", ComboBoxTextLeaf])
  for obj in getValidHeadObjects()
      @idle_add push!(m["cbSafeObject",ComboBoxTextLeaf], name(obj))
  end
  @idle_add set_gtk_property!(m["cbSafeObject",ComboBoxTextLeaf], :active, 0)

  @idle_add signal_connect(m["cbSafeObject",ComboBoxTextLeaf], :changed) do w
      ind = get_gtk_property(m["cbSafeObject",ComboBoxTextLeaf],:active,Int)+1
      if getValidHeadObjects()[ind].name==customPhantom3D.name
          sObjStr = @sprintf("%.2f x %.2f x %.2f", ustrip(customPhantom3D.length), ustrip(crosssection(customPhantom3D).width),ustrip(crosssection(customPhantom3D).height))
          @idle_add set_gtk_property!(m["entSafetyObj", EntryLeaf],:text, sObjStr)
          @idle_add set_gtk_property!(m["entSafetyObj", EntryLeaf],:sensitive,true)
      else
          @idle_add set_gtk_property!(m["entSafetyObj", EntryLeaf],:sensitive,false)
      end
  end


  @debug "Online / Offline"
  if m.scanner != nothing
    setInfoParams(m)
    setParams(m, merge!(getGeneralParams(m.scanner),toDict(getDAQ(m.scanner).params)))
    @idle_add set_gtk_property!(m["entConfig",EntryLeaf],:text,filenameConfig)
    @idle_add set_gtk_property!(m["btnReferenceDrive",ButtonLeaf],:sensitive,!isReferenced(getRobot(m.scanner)))
    enableRobotMoveButtons(m,isReferenced(getRobot(m.scanner)))

    if isReferenced(getRobot(m.scanner))
      try
        rob = getRobot(m.scanner)
        isValid = checkCoords(getRobotSetupUI(m), getPos(rob), getMinMaxPosX(rob))
      catch
        enableRobotMoveButtons(m,false)
        @idle_add set_gtk_property!(m["btnMovePark",ButtonLeaf],:sensitive,true)
      end
    end

    @idle_add updateCalibTime(C_NULL, m)
  else
    @idle_add set_gtk_property!(m["tbMeasure",ToolButtonLeaf],:sensitive,false)
    @idle_add set_gtk_property!(m["tbMeasureBG",ToolButtonLeaf],:sensitive,false)
    @idle_add set_gtk_property!(m["tbContinous",ToggleToolButtonLeaf],:sensitive,false)
    @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,false)
  end

  @idle_add set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,false)

  @debug "InitCallbacks"

  @time initCallbacks(m)

  @info "Finished starting MeasurementWidget"

  return m
end

function reloadConfig(m::MeasurementWidget)
  if m.scanner != nothing
    finalize(m.scanner)
  end
  m.scanner = MPIScanner(m.scanner.file)
  m.scanner.params["Robot"]["doReferenceCheck"] = false
  m.mdfstore = MDFDatasetStore( getGeneralParams(m.scanner)["datasetStore"] )
end

function initSurveillance(m::MeasurementWidget)
  if !m.expanded
    su = getSurveillanceUnit(m.scanner)

    cTemp = Canvas()
    box = m["boxSurveillance",BoxLeaf]
    push!(box,cTemp)
    set_gtk_property!(box,:expand,cTemp,true)

    showall(box)

    tempInit = getTemperatures(su)
    L = length(tempInit)

    temp = Any[]
    for l=1:L
      push!(temp, zeros(0))
    end

    @guarded function update_(::Timer)
      begin
        te = getTemperatures(su)
        str = join([ @sprintf("%.2f C ",t) for t in te ])
        set_gtk_property!(m["entTemperatures",EntryLeaf], :text, str)

        for l=1:L
          push!(temp[l], te[l])
        end

        if length(temp[1]) > 100
          for l=1:L
            temp[l] = temp[l][2:end]
          end
        end

        p = Winston.plot(temp[1],"b-", linewidth=10)
        for l=2:L
          Winston.plot(p,temp[l],"-",linewidth=10)
        end
        #Winston.ylabel("Harmonic $f")
        #Winston.xlabel("Time")
        display(cTemp ,p)
      end
    end
    timer = Timer(update_, 0.0, interval=1.5)
    m.expanded = true
  end
end

function infoMessage(m::MeasurementWidget, message::String, color::String="green")
  m.message = """<span foreground="$color" font_weight="bold" size="x-large">$message</span>"""
  infoMessage(mpilab[], m.message)
end

function initCallbacks(m::MeasurementWidget)

  @debug "CAAALLLLBACK"

  # TODO This currently does not work!
  @time signal_connect(m["expSurveillance",ExpanderLeaf], :activate) do w
    initSurveillance(m)
  end

  #@time signal_connect(measurement, m["tbMeasure",ToolButtonLeaf], "clicked", Nothing, (), false, m )
  #@time signal_connect(measurementBG, m["tbMeasureBG",ToolButtonLeaf], "clicked", Nothing, (), false, m)


  @time signal_connect(m["tbMeasure",ToolButtonLeaf], :clicked) do w
    measurement(C_NULL, m)
  end

  @time signal_connect(m["tbMeasureBG",ToolButtonLeaf], :clicked) do w
    measurementBG(C_NULL, m)
  end

  @time signal_connect(m["btnReloadConfig",ButtonLeaf], :clicked) do w
    reloadConfig(m)
  end

  @time signal_connect(m["btnRobotMove",ButtonLeaf], :clicked) do w
    if !isReferenced(getRobot(m.scanner))
      info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
      return
    end

    posString = get_gtk_property(m["entCurrPos",EntryLeaf], :text, String)
    pos_ = tryparse.(Float64,split(posString,"x"))

    if any(pos_ .== nothing) || length(pos_) != 3
      return
    end
    pos = get.(pos_).*1Unitful.mm
    try
      setEnabled(getRobot(m.scanner), true)
      moveAbs(getRobot(m.scanner),getRobotSetupUI(m), pos)
    catch ex
      showError(ex)
    end
    #infoMessage(m, "move to $posString")
  end

  @time signal_connect(m["btLoadArbPos",ButtonLeaf],:clicked) do w
      filter = Gtk.GtkFileFilter(pattern=String("*.h5"), mimetype=String("HDF5 File"))
      filename = open_dialog("Select Arbitrary Position File", GtkNullContainer(), (filter, ))
      @idle_add set_gtk_property!(m["entArbitraryPos",EntryLeaf],:text,filename)
  end

  @time signal_connect(m["btnMovePark",ButtonLeaf], :clicked) do w
      if !isReferenced(getRobot(m.scanner))
        info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
        return
      end
      setEnabled(getRobot(m.scanner), true)
      movePark(getRobot(m.scanner))
      enableRobotMoveButtons(m, true)
  end

  @time signal_connect(m["btnMoveAssemblePos",ButtonLeaf], :clicked) do w
      if !isReferenced(getRobot(m.scanner))
        info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
        return
      end
      moveAssemble(getRobot(m.scanner))
      @idle_add set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,false)
      @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,false)
  end

  @time signal_connect(m["btnReferenceDrive",ButtonLeaf], :clicked) do w
    robot = getRobot(m.scanner)
    if !isReferenced(robot)
      message = """IselRobot is NOT referenced and needs to be referenced! \n
             Remove all attached devices from the robot before the robot will be referenced and move around!\n
             Press \"Ok\" if you have done so """
      if ask_dialog(message, "Cancle", "Ok", mpilab[]["mainWindow"])
          message = """Are you sure you have removed everything and the robot can move
            freely without damaging anything? Press \"Ok\" if you want to continue"""
         if ask_dialog(message, "Cancle", "Ok", mpilab[]["mainWindow"])
            prepareRobot(robot)
            message = """The robot is now referenced.
               You can mount your sample. Press \"Ok\" to proceed. """
            info_dialog(message, mpilab[]["mainWindow"])
            enableRobotMoveButtons(m,true)
            @idle_add set_gtk_property!(m["btnReferenceDrive",ButtonLeaf],:sensitive,false)
         end
      end
    end
  end

  timer = nothing
  timerActive = false
  @time signal_connect(m["tbContinous",ToggleToolButtonLeaf], :toggled) do w
    daq = getDAQ(m.scanner)
    if get_gtk_property(m["tbContinous",ToggleToolButtonLeaf], :active, Bool)
      params = merge!(getGeneralParams(m.scanner),getParams(m))
      MPIMeasurements.updateParams!(daq, params)
      enableACPower(getSurveillanceUnit(m.scanner))
      setEnabled(getRobot(m.scanner), false)
      startTx(daq)

      if daq.params.controlPhase
        MPIMeasurements.controlLoop(daq)
      else
        MPIMeasurements.setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                         zeros(numTxChannels(daq)))
      end

      timerActive = true
      #@idle_add set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,false)

      function update_(::Timer)
        if timerActive

          if daq.params.controlPhase
            MPIMeasurements.controlLoop(daq)
          else
            MPIMeasurements.setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                             zeros(numTxChannels(daq)))
          end

          currFr = enableSlowDAC(daq, true, 1,
                  daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

          uMeas, uRef = readData(daq, 1, currFr)
          MPIMeasurements.setTxParams(daq, daq.params.currTxAmp*0.0, daq.params.currTxPhase*0.0)

          deltaT = daq.params.dfCycle / daq.params.numSampPerPeriod

          @idle_add updateData(m.rawDataWidget, uMeas, deltaT)

          sleep(get_gtk_property(m["adjPause",AdjustmentLeaf],:value,Float64))
        else
          MPIMeasurements.enableSlowDAC(daq, false)
          setEnabled(getRobot(m.scanner), true)
          stopTx(daq)
          disableACPower(getSurveillanceUnit(m.scanner))
          MPIMeasurements.disconnect(daq)
          #@idle_add set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,true)
          close(timer)
        end
      end
      timer = Timer(update_, 0.0, interval=0.2)
    else
      timerActive = false
    end
  end

  calibState = nothing

  @time signal_connect(m["tbCancel",ToolButtonLeaf], :clicked) do w
    if calibState != nothing
      cancel(calibState)
    end
  end

  timerCalibration = nothing

  @time signal_connect(m["tbCalibration",ToggleToolButtonLeaf], :toggled) do w
    try
    su = getSurveillanceUnit(m.scanner)

    if !isReferenced(getRobot(m.scanner))
      info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
      @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
      return
    end

    daq = getDAQ(m.scanner)
    if get_gtk_property(m["tbCalibration",ToggleToolButtonLeaf], :active, Bool)

      if calibState == nothing
        shpString = get_gtk_property(m["entGridShape",EntryLeaf], :text, String)
        shp_ = tryparse.(Int64,split(shpString,"x"))
        fovString = get_gtk_property(m["entFOV",EntryLeaf], :text, String)
        fov_ = tryparse.(Float64,split(fovString,"x"))
        centerString = get_gtk_property(m["entCenter",EntryLeaf], :text, String)
        center_ = tryparse.(Float64,split(centerString,"x"))

        velRobString = get_gtk_property(m["entVelRob",EntryLeaf], :text, String)
        velRob_ = tryparse.(Int64,split(velRobString,"x"))

        numBGMeas = get_gtk_property(m["adjNumBGMeasurements",AdjustmentLeaf], :value, Int64)

        if any(shp_ .== nothing) || any(fov_ .== nothing) || any(center_ .== nothing) || any(velRob_ .== nothing) ||
           length(shp_) != 3 || length(fov_) != 3 || length(center_) != 3 || length(velRob_) != 3
          @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
          return
        end

        shp = get.(shp_)
        fov = get.(fov_) .*1Unitful.mm
        ctr = get.(center_) .*1Unitful.mm
        velRob = get.(velRob_)

        if get_gtk_property(m["cbUseArbitraryPos",CheckButtonLeaf], :active, Bool) == false
            cartGrid = RegularGridPositions(shp,fov,ctr)#
        else
            filename = get_gtk_property(m["entArbitraryPos"],EntryLeaf,:text,String)
            if filename != ""
                cartGrid = h5open(filename, "r") do file
                    positions = Positions(file)
                end
            else
              error("Filename Arbitrary Positions empty!")
            end
        end
        if numBGMeas == 0
          positions = cartGrid
        else
          bgIdx = round.(Int64, range(1, stop=length(cartGrid)+numBGMeas, length=numBGMeas ) )
          bgPos = parkPos(getRobot(m.scanner))
          positions = BreakpointGridPositions(cartGrid, bgIdx, bgPos)
        end

        for pos in positions
          isValid = checkCoords(getRobotSetupUI(m), pos, getMinMaxPosX(getRobot(m.scanner)))
        end

        params = merge!(getGeneralParams(m.scanner),getParams(m))
        calibObj = SystemMatrixRobotMeas(m.scanner, getRobotSetupUI(m), positions, params,
                  waitTime = get_gtk_property(m["adjPause",AdjustmentLeaf],:value,Float64))

        # the following spawns a task
        @info "perform calibration"
        calibState = performCalibration(m.scanner, calibObj, m.mdfstore, params)

        @idle_add set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,true)
        @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,false)
        @idle_add set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,false)

        function update_(::Timer)
          try
            if calibState.calibrationActive
              if 1 <= calibState.currPos <= calibState.numPos
                pos = Float64.(ustrip.(uconvert.(Unitful.mm, positions[calibState.currPos])))
                posStr = @sprintf("%.2f x %.2f x %.2f", pos[1],pos[2],pos[3])
                infoMessage(m, "$(calibState.currPos) / $(calibState.numPos) ($posStr mm)", "green")

                deltaT = daq.params.dfCycle / daq.params.numSampPerPeriod
                if !calibState.consumed && !isempty(calibState.currentMeas)
                  uMeas = calibState.currentMeas
                  #@idle_add
                  updateData(m.rawDataWidget, uMeas, deltaT)
                  calibState.consumed = true
                end

                #Lauft nicht

                temp = getTemperatures(su)
                while maximum(temp[1:2]) > params["maxTemperature"]
                 infoMessage(m, "System Cooling Down! $(calibState.currPos) / $(calibState.numPos) ($posStr mm)", "red")
                 sleep(20)
                 temp = getTemperatures(su)
                 @info "Temp = $temp"
                end
              end
              if istaskdone(calibState.task)
                infoMessage(m, "", "red")
                @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)

                close(timerCalibration)
                @idle_add set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,false)
                @idle_add set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,true)

                updateData!(mpilab[].sfBrowser, m.mdfstore)
                updateExperimentStore(mpilab[], mpilab[].currentStudy)
                calibState = nothing
              end
            end
            sleep(0.5)
          catch ex
            showError(ex)
          end
        end
        timerCalibration = Timer(update_, 0.0, interval=0.001)
      end
      calibState.calibrationActive = true
    else
      calibState.calibrationActive = false
    end
    catch ex
      showError(ex)
    end
  end


  #@time signal_connect(invalidateBG, m["adjDFStrength"], "value_changed", Nothing, (), false, m)
  #@time signal_connect(invalidateBG, m["adjNumPatches"], "value_changed", Nothing, (), false, m)
  #@time signal_connect(invalidateBG, m["adjNumPeriods"], , Nothing, (), false, m)

  for adj in ["adjNumPeriods","adjDFStrength", "adjNumSubperiods"]
    @time signal_connect(m[adj,AdjustmentLeaf], "value_changed") do w
      invalidateBG(C_NULL, m)
    end
  end

  for adj in ["adjNumBGMeasurements","adjPause","adjNumPeriods","adjNumAverages"]
    @time signal_connect(m[adj,AdjustmentLeaf], "value_changed") do w
      updateCalibTime(C_NULL, m)
      setInfoParams(m)
    end
  end
  @time signal_connect(m["entGridShape",EntryLeaf], "changed") do w
    updateCalibTime(C_NULL, m)
  end


  #@time signal_connect(reinitDAQ, m["adjNumPeriods"], "value_changed", Nothing, (), false, m)
  @time signal_connect(m["cbSeFo",ComboBoxTextLeaf], :changed) do w
    seq = m.sequences[get_gtk_property(m["cbSeFo",ComboBoxTextLeaf], :active, Int)+1]
    val = readdlm(joinpath(sequenceDir(), seq*".csv"),',')
    @idle_add set_gtk_property!(m["adjNumPeriods",AdjustmentLeaf], :value, size(val,2))
  end

end

function updateCalibTime(widgetptr::Ptr, m::MeasurementWidget)
  daq = getDAQ(m.scanner)

  shpString = get_gtk_property(m["entGridShape",EntryLeaf], :text, String)
  shp_ = tryparse.(Int64,split(shpString,"x"))
  numBGMeas = get_gtk_property(m["adjNumBGMeasurements",AdjustmentLeaf], :value, Int64)

  if any(shp_ .== nothing) length(shp_) != 3
    return
  end

  shp = get.(shp_)

  robotMoveTime = 1.8

  calibTime = (get_gtk_property(m["adjNumAverages",AdjustmentLeaf], :value, Int64) *
              (get_gtk_property(m["adjNumFrameAverages",AdjustmentLeaf], :value, Int64)+1) *
              get_gtk_property(m["adjNumPeriods",AdjustmentLeaf], :value, Int64) *
              daq.params.dfCycle + get_gtk_property(m["adjPause",AdjustmentLeaf],:value,Float64) + robotMoveTime) *
              (prod(shp) + numBGMeas)

  calibTimeMin = calibTime/60

  calibStr = ""
  if calibTimeMin > 60
    calibStr = "$(round(Int,calibTimeMin/60)) h "
    calibTimeMin = rem(calibTimeMin, 60)
  end
  calibStr = string(calibStr,@sprintf("%.1f",calibTime/60)," min")

  @idle_add set_gtk_property!(m["entCalibTime",EntryLeaf],:text, calibStr)
  return
end


function invalidateBG(widgetptr::Ptr, m::MeasurementWidget)
  m.dataBGStore = zeros(Float32,0,0,0,0)
  infoMessage(m, "No BG Measurement Available!", "orange")
  return nothing
end

function setInfoParams(m::MeasurementWidget)
  daq = getDAQ(m.scanner)
  if length(daq.params.dfFreq) > 1
    freqStr = "$(join([ " $(round(x, digits=2)) x" for x in daq.params.dfFreq ])[2:end-2]) Hz"
  else
    freqStr = "$(round(daq.params.dfFreq[1], digits=2)) Hz"
  end
  @idle_add set_gtk_property!(m["entDFFreq",EntryLeaf],:text,freqStr)
  @idle_add set_gtk_property!(m["entDFPeriod",EntryLeaf],:text,"$(daq.params.dfCycle*1000) ms")
  framePeriod = get_gtk_property(m["adjNumAverages",AdjustmentLeaf], :value, Int64) *
              get_gtk_property(m["adjNumPeriods",AdjustmentLeaf], :value, Int64) *
              daq.params.dfCycle
  @idle_add set_gtk_property!(m["entFramePeriod",EntryLeaf],:text,"$(@sprintf("%.5f",framePeriod)) s")
end


function measurement(widgetptr::Ptr, m::MeasurementWidget)
  try
    @idle_add @info "Calling measurement"

    daq = getDAQ(m.scanner)

    params = merge!(getGeneralParams(m.scanner),getParams(m))
    params["acqNumFrames"] = params["acqNumFGFrames"]

    bgdata = length(m.dataBGStore) == 0 ? nothing : m.dataBGStore

    measState = asyncMeasurement(m.scanner, m.mdfstore, params, bgdata)
    deltaT = daq.params.dfCycle / daq.params.numSampPerPeriod

    timerMeas = nothing
    function update_(::Timer)
      try
        if Base.istaskfailed(measState.task)
          close(timerMeas)
          @async showError(measState.task.exception,measState.task.backtrace)
          return
        end
        infoMessage(m, "Frame $(measState.currFrame) / $(measState.numFrames)", "green")
        fr = measState.currFrame
        if fr > 0 && !measState.consumed
          updateData(m.rawDataWidget, measState.buffer[:,:,:,fr:fr], deltaT)
          measState.consumed = true
        end
        if istaskdone(measState.task)
          close(timerMeas)
          infoMessage(m, "", "green")
          m.filenameExperiment = measState.filename
          updateData(m.rawDataWidget, m.filenameExperiment)
          updateExperimentStore(mpilab[], mpilab[].currentStudy)
        end
        sleep(0.1)
      catch ex
        close(timerMeas)
        showError(ex)
      end
      return
    end
    timerMeas = Timer(update_, 0.0, interval=0.1)
  catch ex
   showError(ex)
  end
  return nothing
end

function measurementBG(widgetptr::Ptr, m::MeasurementWidget)
  try
    @idle_add @info "Calling BG measurement"
    params = merge!(getGeneralParams(m.scanner),getParams(m))
    params["acqNumFrames"] = params["acqNumBGFrames"]

    setEnabled(getRobot(m.scanner), false)
    enableACPower(getSurveillanceUnit(m.scanner))
    uMeas, uSlowADC = MPIMeasurements.measurement(getDAQ(m.scanner), params)
    disableACPower(getSurveillanceUnit(m.scanner))
    setEnabled(getRobot(m.scanner), true)

    m.dataBGStore = uMeas
    #updateData(m, u)

    infoMessage(m, "", "green")
  catch ex
   showError(ex)
  end
  return nothing
end


function getParams(m::MeasurementWidget)
  params = toDict(getDAQ(m.scanner).params)

  params["acqNumAverages"] = get_gtk_property(m["adjNumAverages",AdjustmentLeaf], :value, Int64)
  params["acqNumFrameAverages"] = get_gtk_property(m["adjNumFrameAverages",AdjustmentLeaf], :value, Int64)
  params["acqNumSubperiods"] = get_gtk_property(m["adjNumSubperiods",AdjustmentLeaf], :value, Int64)

  params["acqNumFGFrames"] = get_gtk_property(m["adjNumFGFrames",AdjustmentLeaf], :value, Int64)
  params["acqNumBGFrames"] = get_gtk_property(m["adjNumBGFrames",AdjustmentLeaf], :value, Int64)
  params["acqNumPeriodsPerFrame"] = get_gtk_property(m["adjNumPeriods",AdjustmentLeaf], :value, Int64)
  params["studyName"] = m.currStudyName
  params["studyDate"] = m.currStudyDate
  params["studyDescription"] = ""
  params["experimentDescription"] = get_gtk_property(m["entExpDescr",EntryLeaf], :text, String)
  params["experimentName"] = get_gtk_property(m["entExpName",EntryLeaf], :text, String)
  params["scannerOperator"] = get_gtk_property(m["entOperator",EntryLeaf], :text, String)
  params["tracerName"] = [get_gtk_property(m["entTracerName",EntryLeaf], :text, String)]
  params["tracerBatch"] = [get_gtk_property(m["entTracerBatch",EntryLeaf], :text, String)]
  params["tracerVendor"] = [get_gtk_property(m["entTracerVendor",EntryLeaf], :text, String)]
  params["tracerVolume"] = [1e-3*get_gtk_property(m["adjTracerVolume",AdjustmentLeaf], :value, Float64)]
  params["tracerConcentration"] = [1e-3*get_gtk_property(m["adjTracerConcentration",AdjustmentLeaf], :value, Float64)]
  params["tracerSolute"] = [get_gtk_property(m["entTracerSolute",EntryLeaf], :text, String)]

  dfString = get_gtk_property(m["entDFStrength",EntryLeaf], :text, String)
  params["dfStrength"] = parse.(Float64,split(dfString," x "))*1e-3

  params["acqFFSequence"] = m.sequences[get_gtk_property(m["cbSeFo",ComboBoxTextLeaf], :active, Int)+1]
  params["acqFFLinear"] = get_gtk_property(m["cbFFInterpolation",CheckButtonLeaf], :active, Bool)
  params["storeAsSystemMatrix"] = get_gtk_property(m["cbStoreAsSystemMatrix",CheckButtonLeaf],:active, Bool)

  return params
end

function setParams(m::MeasurementWidget, params)
  @idle_add set_gtk_property!(m["adjNumAverages",AdjustmentLeaf], :value, params["acqNumAverages"])
  @idle_add set_gtk_property!(m["adjNumFrameAverages",AdjustmentLeaf], :value, params["acqNumFrameAverages"])
  @idle_add set_gtk_property!(m["adjNumSubperiods",AdjustmentLeaf], :value, get(params,"acqNumSubperiods",1))
  @idle_add set_gtk_property!(m["adjNumFGFrames",AdjustmentLeaf], :value, params["acqNumFrames"])
  @idle_add set_gtk_property!(m["adjNumBGFrames",AdjustmentLeaf], :value, params["acqNumFrames"])
  #@idle_add set_gtk_property!(m["entStudy"], :text, params["studyName"])
  @idle_add set_gtk_property!(m["entExpDescr",EntryLeaf], :text, params["studyDescription"] )
  @idle_add set_gtk_property!(m["entOperator",EntryLeaf], :text, params["scannerOperator"])
  dfString = *([ string(x*1e3," x ") for x in params["dfStrength"] ]...)[1:end-3]
  @idle_add set_gtk_property!(m["entDFStrength",EntryLeaf], :text, dfString)

  @idle_add set_gtk_property!(m["entTracerName",EntryLeaf], :text, params["tracerName"][1])
  @idle_add set_gtk_property!(m["entTracerBatch",EntryLeaf], :text, params["tracerBatch"][1])
  @idle_add set_gtk_property!(m["entTracerVendor",EntryLeaf], :text, params["tracerVendor"][1])
  @idle_add set_gtk_property!(m["adjTracerVolume",AdjustmentLeaf], :value, 1000*params["tracerVolume"][1])
  @idle_add set_gtk_property!(m["adjTracerConcentration",AdjustmentLeaf], :value, 1000*params["tracerConcentration"][1])
  @idle_add set_gtk_property!(m["entTracerSolute",EntryLeaf], :text, params["tracerSolute"][1])

  if haskey(params,"acqFFSequence")
    idx = findfirst_(m.sequences, params["acqFFSequence"])
    if idx > 0
      @idle_add set_gtk_property!(m["cbSeFo",ComboBoxTextLeaf], :active,idx-1)
    end
  else
      @idle_add set_gtk_property!(m["adjNumPeriods",AdjustmentLeaf], :value, params["acqNumPeriodsPerFrame"])
  end

  @idle_add set_gtk_property!(m["cbFFInterpolation",CheckButtonLeaf], :active, params["acqFFLinear"])

  p = getGeneralParams(m.scanner)
  if haskey(p, "calibGridShape") && haskey(p, "calibGridFOV") && haskey(p, "calibGridCenter") &&
     haskey(p, "calibNumBGMeasurements")
    shp = p["calibGridShape"]
    shpStr = @sprintf("%d x %d x %d", shp[1],shp[2],shp[3])
    fov = p["calibGridFOV"]*1000 # convert to mm
    fovStr = @sprintf("%.2f x %.2f x %.2f", fov[1],fov[2],fov[3])
    ctr = p["calibGridCenter"]*1000 # convert to mm
    ctrStr = @sprintf("%.2f x %.2f x %.2f", ctr[1],ctr[2],ctr[3])
    @idle_add set_gtk_property!(m["entGridShape",EntryLeaf], :text, shpStr)
    @idle_add set_gtk_property!(m["entFOV",EntryLeaf], :text, fovStr)
    @idle_add set_gtk_property!(m["entCenter",EntryLeaf], :text, ctrStr)
    @idle_add set_gtk_property!(m["adjNumBGMeasurements",AdjustmentLeaf], :value, p["calibNumBGMeasurements"])
  end
  velRob = getDefaultVelocity(getRobot(m.scanner))
  velRobStr = @sprintf("%.d x %.d x %.d", velRob[1],velRob[2],velRob[3])
  @idle_add set_gtk_property!(m["entVelRob",EntryLeaf], :text, velRobStr)
  @idle_add set_gtk_property!(m["entCurrPos",EntryLeaf], :text, "0.0 x 0.0 x 0.0")

  @idle_add set_gtk_property!(m["adjPause",AdjustmentLeaf], :value, 2.0)
end

function getRobotSetupUI(m::MeasurementWidget)
    coil = getValidHeadScannerGeos()[get_gtk_property(m["cbSafeCoil",ComboBoxTextLeaf], :active, Int)+1]
    obj = getValidHeadObjects()[get_gtk_property(m["cbSafeObject",ComboBoxTextLeaf], :active, Int)+1]
    if obj.name == customPhantom3D.name
        obj = getCustomPhatom(m)
    end
    setup = RobotSetup("UIRobotSetup",obj,coil,clearance)
    return setup
end

function getCustomPhatom(m::MeasurementWidget)
    cPStr = get_gtk_property(m["entSafetyObj",EntryLeaf],:text,String)
    cP_ = tryparse.(Float64,split(cPStr,"x"))
    cP= get.(cP_) .*1Unitful.mm
    return Cuboid(Rectangle(cP[2],cP[3], "UI Custom Phantom"),cP[1],"UI Custom Phantom 3D")
end


function enableRobotMoveButtons(m::MeasurementWidget, enable::Bool)
  @idle_add set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,enable)
  @idle_add set_gtk_property!(m["btnMoveAssemblePos",ButtonLeaf],:sensitive,enable)
  @idle_add set_gtk_property!(m["btnMovePark",ButtonLeaf],:sensitive,enable)
  @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,enable)
end
