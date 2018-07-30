
mutable struct MeasurementWidget{T} <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::Builder
  scanner::T
  dataBGStore::Array{Float32,4}
  mdfstore::MDFDatasetStore
  currStudyName::String
  filenameExperiment::String
  rawDataWidget::RawDataWidget
  sequences::Vector{String}
  expanded::Bool
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
  println("Starting MeasurementWidget")
  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","measurementWidget.ui")

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
                  scanner, zeros(Float32,0,0,0,0), mdfstore, "",
                  "", RawDataWidget(), String[], false)
  Gtk.gobject_move_ref(m, mainBox)

  println("Type constructed")

  println("InvalidateBG")
  invalidateBG(C_NULL, m)

  push!(m["boxMeasTabVisu",BoxLeaf],m.rawDataWidget)
  setproperty!(m["boxMeasTabVisu",BoxLeaf],:expand,m.rawDataWidget,true)

  Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:use_markup,true)

  println("Read Sequences")
  Gtk.@sigatom empty!(m["cbSeFo",ComboBoxTextLeaf])
  m.sequences = String[ splitext(seq)[1] for seq in
            readdir(Pkg.dir("MPIMeasurements","src","Sequences"))]
  for seq in m.sequences
    Gtk.@sigatom push!(m["cbSeFo",ComboBoxTextLeaf], seq)
  end
  Gtk.@sigatom setproperty!(m["cbSeFo",ComboBoxTextLeaf],:active,0)

  println("Read safety parameters")
  Gtk.@sigatom empty!(m["cbSafeCoil", ComboBoxTextLeaf])
  for coil in getValidHeadScannerGeos()
      Gtk.@sigatom push!(m["cbSafeCoil",ComboBoxTextLeaf], coil.name)
  end
  Gtk.@sigatom setproperty!(m["cbSafeCoil",ComboBoxTextLeaf], :active, 0)
  Gtk.@sigatom empty!(m["cbSafeObject", ComboBoxTextLeaf])
  for obj in getValidHeadObjects()
      Gtk.@sigatom push!(m["cbSafeObject",ComboBoxTextLeaf], name(obj))
  end
  Gtk.@sigatom setproperty!(m["cbSafeObject",ComboBoxTextLeaf], :active, 0)

  Gtk.@sigatom signal_connect(m["cbSafeObject",ComboBoxTextLeaf], :changed) do w
      ind = getproperty(m["cbSafeObject",ComboBoxTextLeaf],:active,Int)+1
      if getValidHeadObjects()[ind].name==customPhantom3D.name
          sObjStr = @sprintf("%.2f x %.2f x %.2f", ustrip(customPhantom3D.length), ustrip(crosssection(customPhantom3D).width),ustrip(crosssection(customPhantom3D).height))
          Gtk.@sigatom setproperty!(m["entSafetyObj", EntryLeaf],:text, sObjStr)
          Gtk.@sigatom setproperty!(m["entSafetyObj", EntryLeaf],:sensitive,true)
      else
          Gtk.@sigatom setproperty!(m["entSafetyObj", EntryLeaf],:sensitive,false)
      end
  end


  println("Online / Offline")
  if m.scanner != nothing
    setInfoParams(m)
    setParams(m, merge!(getGeneralParams(m.scanner),toDict(getDAQ(m.scanner).params)))
    Gtk.@sigatom setproperty!(m["entConfig",EntryLeaf],:text,filenameConfig)
    Gtk.@sigatom setproperty!(m["btnReferenceDrive",ButtonLeaf],:sensitive,!isReferenced(getRobot(m.scanner)))
    Gtk.@sigatom updateCalibTime(C_NULL, m)
  else
    Gtk.@sigatom setproperty!(m["tbMeasure",ToolButtonLeaf],:sensitive,false)
    Gtk.@sigatom setproperty!(m["tbMeasureBG",ToolButtonLeaf],:sensitive,false)
    Gtk.@sigatom setproperty!(m["tbContinous",ToggleToolButtonLeaf],:sensitive,false)
    Gtk.@sigatom setproperty!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,false)
  end

  Gtk.@sigatom setproperty!(m["tbCancel",ToolButtonLeaf],:sensitive,false)

  println("InitCallbacks")

  @time initCallbacks(m)

  println("Finished")

  return m
end

function initSurveillance(m::MeasurementWidget)
  if !m.expanded
    su = getSurveillanceUnit(m.scanner)
    cTemp = Canvas()
    box = m["boxSurveillance",BoxLeaf]
    push!(box,cTemp)
    setproperty!(box,:expand,cTemp,true)

    showall(box)

    temp1 = zeros(0)
    temp2 = zeros(0)

    function update_(::Timer)
      Gtk.@sigatom begin
        temp = getTemperatures(su)
        str = join([ @sprintf("%.2f C ",t) for t in temp ])
        setproperty!(m["entTemperatures",EntryLeaf], :text, str)

        push!(temp1, temp[1])
        push!(temp2, temp[2])

        if length(temp1) > 100
          temp1 = temp1[2:end]
          temp2 = temp2[2:end]
        end

        p = Winston.plot(temp1,"b-", linewidth=10)
        Winston.plot(p,temp2,"r-",linewidth=10)
        #Winston.ylabel("Harmonic $f")
        #Winston.xlabel("Time")
        display(cTemp ,p)
      end
    end
    timer = Timer(update_, 0.0, 1.5)
    m.expanded = true
  end
end


function infoMessage(m::MeasurementWidget, message::String)
  Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:label,
      """<span foreground="green" font_weight="bold" size="x-large">$message</span>""")
end

function initCallbacks(m::MeasurementWidget)

  println("CAAALLLLBACK")

  # TODO This currently does not work!
  #@time signal_connect(m["expSurveillance",ExpanderLeaf], :activate) do w
  #  initSurveillance(m)
  #end

  #@time signal_connect(measurement, m["tbMeasure",ToolButtonLeaf], "clicked", Void, (), false, m )
  #@time signal_connect(measurementBG, m["tbMeasureBG",ToolButtonLeaf], "clicked", Void, (), false, m)


  @time signal_connect(m["tbMeasure",ToolButtonLeaf], :clicked) do w
    measurement(C_NULL, m)
  end

  @time signal_connect(m["tbMeasureBG",ToolButtonLeaf], :clicked) do w
    measurementBG(C_NULL, m)
  end

  @time signal_connect(m["btnRobotMove",ButtonLeaf], :clicked) do w
    if !isReferenced(getRobot(m.scanner))
      info_dialog("Robot not referenced! Cannot proceed!", mpilab["mainWindow"])
      return
    end

    posString = getproperty(m["entCurrPos",EntryLeaf], :text, String)
    pos_ = tryparse.(Float64,split(posString,"x"))

    if any(isnull.(pos_)) || length(pos_) != 3
      return
    end
    pos = get.(pos_).*1Unitful.mm
    moveAbs(getRobot(m.scanner),getRobotSetupUI(m), pos)
    #infoMessage(m, "move to $posString")
  end

  @time signal_connect(m["btLoadArbPos",ButtonLeaf],:clicked) do w
      filter = Gtk.GtkFileFilter(pattern=String("*.h5"), mimetype=String("HDF5 File"))
      filename = open_dialog("Select Arbitrary Position File", GtkNullContainer(), (filter, ))
      Gtk.@sigatom setproperty!(m["entArbitraryPos",EntryLeaf],:text,filename)
  end

  @time signal_connect(m["bt_MovePark",ButtonLeaf], :clicked) do w
      if !isReferenced(getRobot(m.scanner))
        info_dialog("Robot not referenced! Cannot proceed!", mpilab["mainWindow"])
        return
      end
      movePark(getRobot(m.scanner))
  end

  @time signal_connect(m["btnReferenceDrive",ButtonLeaf], :clicked) do w
    robot = getRobot(m.scanner)
    if !isReferenced(robot)
      message = """IselRobot is NOT referenced and needs to be referenced! \n
             Remove all attached devices from the robot before the robot will be referenced and move around!\n
             Press \"Ok\" if you have done so """
      if ask_dialog(message, "Cancle", "Ok", mpilab["mainWindow"])
          message = """Are you sure you have removed everything and the robot can move
            freely without damaging anything? Press \"Ok\" if you want to continue"""
         if ask_dialog(message, "Cancle", "Ok", mpilab["mainWindow"])
            prepareRobot(robot)
            message = """The robot is now referenced.
               You can mount your sample. Press \"Ok\" to proceed. """
            info_dialog(message, mpilab["mainWindow"])
         end
      end
    end
  end

  timer = nothing
  timerActive = false
  @time signal_connect(m["tbContinous",ToggleToolButtonLeaf], :toggled) do w
    daq = getDAQ(m.scanner)
    if getproperty(m["tbContinous",ToggleToolButtonLeaf], :active, Bool)
      params = merge!(getGeneralParams(m.scanner),getParams(m))
      MPIMeasurements.updateParams!(daq, params)
      enableACPower(getSurveillanceUnit(m.scanner))
      startTx(daq)

      if daq.params.controlPhase
        MPIMeasurements.controlLoop(daq)
      else
        MPIMeasurements.setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                         zeros(numTxChannels(daq)))
      end

      timerActive = true
      Gtk.@sigatom setproperty!(m["btnRobotMove",ButtonLeaf],:sensitive,false)

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

          Gtk.@sigatom updateData(m.rawDataWidget, uMeas, deltaT)

          sleep(getproperty(m["adjPause",AdjustmentLeaf],:value,Float64))
        else
          MPIMeasurements.enableSlowDAC(daq, false)
          stopTx(daq)
          disableACPower(getSurveillanceUnit(m.scanner))
          MPIMeasurements.disconnect(daq)
          Gtk.@sigatom setproperty!(m["btnRobotMove",ButtonLeaf],:sensitive,true)
          close(timer)
        end
      end
      timer = Timer(update_, 0.0, 0.2)
    else
      timerActive = false
    end
  end


  timerCalibration = nothing
  timerCalibrationActive = false
  calibObj = nothing
  numPos = 0
  currPos = 0
  cancelled = false
  @time signal_connect(m["tbCancel",ToolButtonLeaf], :clicked) do w
    cancelled = true
    currPos = numPos
    timerCalibrationActive = true
  end

  @time signal_connect(m["tbCalibration",ToggleToolButtonLeaf], :toggled) do w
    su = getSurveillanceUnit(m.scanner)

    if !isReferenced(getRobot(m.scanner))
      info_dialog("Robot not referenced! Cannot proceed!", mpilab["mainWindow"])
      Gtk.@sigatom setproperty!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
      return
    end

    daq = getDAQ(m.scanner)
    if getproperty(m["tbCalibration",ToggleToolButtonLeaf], :active, Bool)
      if currPos == 0

        shpString = getproperty(m["entGridShape",EntryLeaf], :text, String)
        shp_ = tryparse.(Int64,split(shpString,"x"))
        fovString = getproperty(m["entFOV",EntryLeaf], :text, String)
        fov_ = tryparse.(Float64,split(fovString,"x"))
        centerString = getproperty(m["entCenter",EntryLeaf], :text, String)
        center_ = tryparse.(Float64,split(centerString,"x"))

        velRobString = getproperty(m["entVelRob",EntryLeaf], :text, String)
        velRob_ = tryparse.(Int64,split(velRobString,"x"))

        numBGMeas = getproperty(m["adjNumBGMeasurements",AdjustmentLeaf], :value, Int64)

        if any(isnull.(shp_)) || any(isnull.(fov_)) || any(isnull.(center_)) || any(isnull.(velRob_)) ||
           length(shp_) != 3 || length(fov_) != 3 || length(center_) != 3 || length(velRob_) != 3
          Gtk.@sigatom setproperty!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
          return
        end

        shp = get.(shp_)
        fov = get.(fov_) .*1Unitful.mm
        ctr = get.(center_) .*1Unitful.mm
        velRob = get.(velRob_)

        if getproperty(m["cbUseArbitraryPos",CheckButtonLeaf], :active, Bool) == false
            cartGrid = RegularGridPositions(shp,fov,ctr)#
        else
            filename = getproperty(m["entArbitraryPos"],EntryLeaf,:text,String)
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
          bgIdx = round.(Int64, linspace(1, length(cartGrid)+numBGMeas, numBGMeas ) )
          bgPos = parkPos(getRobot(m.scanner))
          positions = BreakpointGridPositions(cartGrid, bgIdx, bgPos)
        end

        for pos in positions
          isValid = checkCoords(getRobotSetupUI(m), pos, getMinMaxPosX(getRobot(m.scanner)))
        end

        params = merge!(getGeneralParams(m.scanner),getParams(m))
        calibObj = SystemMatrixRobotMeas(m.scanner, getRobotSetupUI(m), positions, params)

        timerCalibrationActive = true
        currPos = 1
        numPos = length(positions)

        Gtk.@sigatom setproperty!(m["tbCancel",ToolButtonLeaf],:sensitive,true)
        cancelled = false
        function update_(::Timer)
          println("Timer active $currPos / $numPos")
          if timerCalibrationActive
            if currPos <= numPos
              pos = Float64.(ustrip.(uconvert.(Unitful.mm, positions[currPos])))
              posStr = @sprintf("%.2f x %.2f x %.2f", pos[1],pos[2],pos[3])
              Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:label,
                    """<span foreground="green" font_weight="bold" size="x-large"> $currPos / $numPos ($posStr mm) </span>""")

              moveAbsUnsafe(getRobot(m.scanner), positions[currPos]) # comment for testing
              sleep(0.5)

              uMeas, uRef = postMoveAction(calibObj, positions[currPos], currPos)

              deltaT = daq.params.dfCycle / daq.params.numSampPerPeriod

              Gtk.@sigatom updateData(m.rawDataWidget, uMeas, deltaT)

              currPos +=1
              sleep(getproperty(m["adjPause",AdjustmentLeaf],:value,Float64))

              temp = getTemperatures(su)
              while maximum(temp) > params["maxTemperature"]
                Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:label,
                      """<span foreground="red" font_weight="bold" size="x-large"> System Cooling Down! </span>""")
                sleep(20)
                temp[:] = getTemperatures(su)
              end
            end
            if currPos > numPos
              stopTx(daq)
              disableACPower(getSurveillanceUnit(m.scanner))
              MPIMeasurements.disconnect(daq)

              movePark(getRobot(m.scanner))

              Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:label, "")
              currPos = 0
              Gtk.@sigatom setproperty!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)

              if !cancelled
                cancelled = false
                calibNum = getNewCalibNum(m.mdfstore)
                if getproperty(m["cbStoreAsSystemMatrix",CheckButtonLeaf],:active, Bool)
                  saveasMDF("/tmp/tmp.mdf",
                        calibObj, params)
                  saveasMDF(joinpath(calibdir(m.mdfstore),string(calibNum)*".mdf"),
                        MPIFile("/tmp/tmp.mdf"), applyCalibPostprocessing=true)
                  updateData!(mpilab.sfBrowser, m.mdfstore)
                else

                  name = params["studyName"]
                  path = joinpath( studydir(m.mdfstore), name)
                  subject = ""
                  date = ""

                  newStudy = Study(path,name,subject,date)

                  addStudy(m.mdfstore, newStudy)
                  expNum = getNewExperimentNum(m.mdfstore, newStudy)
                  params["experimentNumber"] = expNum

                  filename = joinpath(studydir(m.mdfstore),newStudy.name,string(expNum)*".mdf")

                  saveasMDF(filename, calibObj, params)
                  updateExperimentStore(mpilab, mpilab.currentStudy)
                end
              end
              close(timerCalibration)
              Gtk.@sigatom setproperty!(m["tbCancel",ToolButtonLeaf],:sensitive,false)
            end
          else

          end
        end
        timerCalibration = Timer(update_, 0.0, 0.001)
      else
        timerCalibrationActive = true
      end
    else
      timerCalibrationActive = false
    end
  end


  #@time signal_connect(invalidateBG, m["adjDFStrength"], "value_changed", Void, (), false, m)
  #@time signal_connect(invalidateBG, m["adjNumPatches"], "value_changed", Void, (), false, m)
  #@time signal_connect(invalidateBG, m["adjNumPeriods"], , Void, (), false, m)

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


  #@time signal_connect(reinitDAQ, m["adjNumPeriods"], "value_changed", Void, (), false, m)
  @time signal_connect(m["cbSeFo",ComboBoxTextLeaf], :changed) do w
    seq = m.sequences[getproperty(m["cbSeFo",ComboBoxTextLeaf], :active, Int)+1]
    val = readcsv(Pkg.dir("MPIMeasurements","src","Sequences",
                                    seq*".csv"))
    Gtk.@sigatom setproperty!(m["adjNumPeriods",AdjustmentLeaf], :value, size(val,2))
  end

end

function updateCalibTime(widgetptr::Ptr, m::MeasurementWidget)
  daq = getDAQ(m.scanner)

  shpString = getproperty(m["entGridShape",EntryLeaf], :text, String)
  shp_ = tryparse.(Int64,split(shpString,"x"))
  numBGMeas = getproperty(m["adjNumBGMeasurements",AdjustmentLeaf], :value, Int64)

  if any(isnull.(shp_)) length(shp_) != 3
    return
  end

  shp = get.(shp_)

  robotMoveTime = 1.8

  calibTime = (getproperty(m["adjNumAverages",AdjustmentLeaf], :value, Int64) *
              (getproperty(m["adjNumFrameAverages",AdjustmentLeaf], :value, Int64)+1) *
              getproperty(m["adjNumPeriods",AdjustmentLeaf], :value, Int64) *
              daq.params.dfCycle + getproperty(m["adjPause",AdjustmentLeaf],:value,Float64) + robotMoveTime) *
              (prod(shp) + numBGMeas)

  calibTimeMin = calibTime/60

  calibStr = ""
  if calibTimeMin > 60
    calibStr = "$(round(Int,calibTimeMin/60)) h "
    calibTimeMin = rem(calibTimeMin, 60)
  end
  calibStr = string(calibStr,@sprintf("%.1f",calibTime/60)," min")

  Gtk.@sigatom setproperty!(m["entCalibTime",EntryLeaf],:text, calibStr)
  return
end


function invalidateBG(widgetptr::Ptr, m::MeasurementWidget)
  m.dataBGStore = zeros(Float32,0,0,0,0)
  Gtk.@sigatom setproperty!(m["cbBGAvailable",CheckButtonLeaf],:active,false)
  Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:label,
        """<span foreground="red" font_weight="bold" size="x-large"> No BG Measurement Available!</span>""")
  return nothing
end

function setInfoParams(m::MeasurementWidget)
  daq = getDAQ(m.scanner)
  if length(daq.params.dfFreq) > 1
    freqStr = "$(join([ " $(round(x,2)) x" for x in daq.params.dfFreq ])[2:end-2]) Hz"
  else
    freqStr = "$(round(daq.params.dfFreq[1],2)) Hz"
  end
  Gtk.@sigatom setproperty!(m["entDFFreq",EntryLeaf],:text,freqStr)
  Gtk.@sigatom setproperty!(m["entDFPeriod",EntryLeaf],:text,"$(daq.params.dfCycle*1000) ms")
  framePeriod = getproperty(m["adjNumAverages",AdjustmentLeaf], :value, Int64) *
              getproperty(m["adjNumPeriods",AdjustmentLeaf], :value, Int64) *
              daq.params.dfCycle
  Gtk.@sigatom setproperty!(m["entFramePeriod",EntryLeaf],:text,"$(@sprintf("%.5f",framePeriod)) s")
end


function measurement(widgetptr::Ptr, m::MeasurementWidget)
  Gtk.@sigatom  println("Calling measurement")

  params = merge!(getGeneralParams(m.scanner),getParams(m))
  params["acqNumFrames"] = params["acqNumFGFrames"]

  bgdata = length(m.dataBGStore) == 0 ? nothing : m.dataBGStore
  enableACPower(getSurveillanceUnit(m.scanner))
  m.filenameExperiment = MPIMeasurements.measurement(getDAQ(m.scanner), params, m.mdfstore,
                         bgdata=bgdata)
  disableACPower(getSurveillanceUnit(m.scanner))

  Gtk.@sigatom updateData(m.rawDataWidget, m.filenameExperiment)

  updateExperimentStore(mpilab, mpilab.currentStudy)
  return nothing
end

function measurementBG(widgetptr::Ptr, m::MeasurementWidget)
  Gtk.@sigatom println("Calling BG measurement")

  params = merge!(getGeneralParams(m.scanner),getParams(m))
  params["acqNumFrames"] = params["acqNumBGFrames"]

  enableACPower(getSurveillanceUnit(m.scanner))
  u = MPIMeasurements.measurement(getDAQ(m.scanner), params)
  disableACPower(getSurveillanceUnit(m.scanner))

  m.dataBGStore = u
  #updateData(m, u)

  Gtk.@sigatom setproperty!(m["cbBGAvailable",CheckButtonLeaf],:active,true)
  Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:label,"")
  return nothing
end


function getParams(m::MeasurementWidget)
  params = toDict(getDAQ(m.scanner).params)

  params["acqNumAverages"] = getproperty(m["adjNumAverages",AdjustmentLeaf], :value, Int64)
  params["acqNumFrameAverages"] = getproperty(m["adjNumFrameAverages",AdjustmentLeaf], :value, Int64)
  params["acqNumSubperiods"] = getproperty(m["adjNumSubperiods",AdjustmentLeaf], :value, Int64)

  params["acqNumFGFrames"] = getproperty(m["adjNumFGFrames",AdjustmentLeaf], :value, Int64)
  params["acqNumBGFrames"] = getproperty(m["adjNumBGFrames",AdjustmentLeaf], :value, Int64)
  #params["acqNumPeriods"] = getproperty(m["adjNumPeriods"], :value, Int64)
  params["studyName"] = m.currStudyName
  params["studyDescription"] = ""
  params["experimentDescription"] = getproperty(m["entExpDescr",EntryLeaf], :text, String)
  params["experimentName"] = getproperty(m["entExpName",EntryLeaf], :text, String)
  params["scannerOperator"] = getproperty(m["entOperator",EntryLeaf], :text, String)
  params["tracerName"] = [getproperty(m["entTracerName",EntryLeaf], :text, String)]
  params["tracerBatch"] = [getproperty(m["entTracerBatch",EntryLeaf], :text, String)]
  params["tracerVendor"] = [getproperty(m["entTracerVendor",EntryLeaf], :text, String)]
  params["tracerVolume"] = [1e-3*getproperty(m["adjTracerVolume",AdjustmentLeaf], :value, Float64)]
  params["tracerConcentration"] = [1e-3*getproperty(m["adjTracerConcentration",AdjustmentLeaf], :value, Float64)]
  params["tracerSolute"] = [getproperty(m["entTracerSolute",EntryLeaf], :text, String)]

  dfString = getproperty(m["entDFStrength",EntryLeaf], :text, String)
  params["dfStrength"] = parse.(Float64,split(dfString," x "))*1e-3
  println("DF strength = $(params["dfStrength"])")

  params["acqFFSequence"] = m.sequences[getproperty(m["cbSeFo",ComboBoxTextLeaf], :active, Int)+1]
  params["acqFFLinear"] = getproperty(m["cbFFInterpolation",CheckButtonLeaf], :active, Bool)

  return params
end

function setParams(m::MeasurementWidget, params)
  Gtk.@sigatom setproperty!(m["adjNumAverages",AdjustmentLeaf], :value, params["acqNumAverages"])
  Gtk.@sigatom setproperty!(m["adjNumFrameAverages",AdjustmentLeaf], :value, params["acqNumFrameAverages"])
  Gtk.@sigatom setproperty!(m["adjNumSubperiods",AdjustmentLeaf], :value, get(params,"acqNumSubperiods",1))
  Gtk.@sigatom setproperty!(m["adjNumFGFrames",AdjustmentLeaf], :value, params["acqNumFrames"])
  Gtk.@sigatom setproperty!(m["adjNumBGFrames",AdjustmentLeaf], :value, params["acqNumFrames"])
  #Gtk.@sigatom setproperty!(m["entStudy"], :text, params["studyName"])
  Gtk.@sigatom setproperty!(m["entExpDescr",EntryLeaf], :text, params["studyDescription"] )
  Gtk.@sigatom setproperty!(m["entOperator",EntryLeaf], :text, params["scannerOperator"])
  dfString = *([ string(x*1e3," x ") for x in params["dfStrength"] ]...)[1:end-3]
  Gtk.@sigatom setproperty!(m["entDFStrength",EntryLeaf], :text, dfString)

  Gtk.@sigatom setproperty!(m["entTracerName",EntryLeaf], :text, params["tracerName"][1])
  Gtk.@sigatom setproperty!(m["entTracerBatch",EntryLeaf], :text, params["tracerBatch"][1])
  Gtk.@sigatom setproperty!(m["entTracerVendor",EntryLeaf], :text, params["tracerVendor"][1])
  Gtk.@sigatom setproperty!(m["adjTracerVolume",AdjustmentLeaf], :value, 1000*params["tracerVolume"][1])
  Gtk.@sigatom setproperty!(m["adjTracerConcentration",AdjustmentLeaf], :value, 1000*params["tracerConcentration"][1])
  Gtk.@sigatom setproperty!(m["entTracerSolute",EntryLeaf], :text, params["tracerSolute"][1])

  if haskey(params,"acqFFSequence")
    idx = findfirst(m.sequences, params["acqFFSequence"])
    if idx > 0
      Gtk.@sigatom setproperty!(m["cbSeFo",ComboBoxTextLeaf], :active,idx-1)
    end
  else
      Gtk.@sigatom setproperty!(m["adjNumPeriods",AdjustmentLeaf], :value, params["acqNumPeriodsPerFrame"])
  end

  Gtk.@sigatom setproperty!(m["cbFFInterpolation",CheckButtonLeaf], :active, params["acqFFLinear"])

  p = getGeneralParams(m.scanner)
  if haskey(p, "calibGridShape") && haskey(p, "calibGridFOV") && haskey(p, "calibGridCenter") &&
     haskey(p, "calibNumBGMeasurements")
    shp = p["calibGridShape"]
    shpStr = @sprintf("%d x %d x %d", shp[1],shp[2],shp[3])
    fov = p["calibGridFOV"]*1000 # convert to mm
    fovStr = @sprintf("%.2f x %.2f x %.2f", fov[1],fov[2],fov[3])
    ctr = p["calibGridCenter"]*1000 # convert to mm
    ctrStr = @sprintf("%.2f x %.2f x %.2f", ctr[1],ctr[2],ctr[3])
    Gtk.@sigatom setproperty!(m["entGridShape",EntryLeaf], :text, shpStr)
    Gtk.@sigatom setproperty!(m["entFOV",EntryLeaf], :text, fovStr)
    Gtk.@sigatom setproperty!(m["entCenter",EntryLeaf], :text, ctrStr)
    Gtk.@sigatom setproperty!(m["adjNumBGMeasurements",AdjustmentLeaf], :value, p["calibNumBGMeasurements"])
  end
  velRob = getDefaultVelocity(getRobot(m.scanner))
  velRobStr = @sprintf("%.d x %.d x %.d", velRob[1],velRob[2],velRob[3])
  Gtk.@sigatom setproperty!(m["entVelRob",EntryLeaf], :text, velRobStr)
  Gtk.@sigatom setproperty!(m["entCurrPos",EntryLeaf], :text, "0.0 x 0.0 x 0.0")

  Gtk.@sigatom setproperty!(m["adjPause",AdjustmentLeaf], :value, 2.0)
end

function getRobotSetupUI(m::MeasurementWidget)
    coil = getValidHeadScannerGeos()[getproperty(m["cbSafeCoil",ComboBoxTextLeaf], :active, Int)+1]
    obj = getValidHeadObjects()[getproperty(m["cbSafeObject",ComboBoxTextLeaf], :active, Int)+1]
    if obj.name == customPhantom3D.name
        obj = getCustomPhatom(m)
    end
    setup = RobotSetup("UIRobotSetup",obj,coil,clearance)
    return setup
end

function getCustomPhatom(m::MeasurementWidget)
    cPStr = getproperty(m["entSafetyObj",EntryLeaf],:text,String)
    cP_ = tryparse.(Float64,split(cPStr,"x"))
    cP= get.(cP_) .*1Unitful.mm
    return Cuboid(Rectangle(cP[2],cP[3], "UI Custom Phantom"),cP[1],"UI Custom Phantom 3D")
end
