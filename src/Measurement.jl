
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
                  "", RawDataWidget(), String[])
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
      if getValidHeadObjects()[ind].name==customPhantom.name
          sObjStr = @sprintf("%.2f x %.2f", ustrip(customPhantom.width),ustrip(customPhantom.height))
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

function infoMessage(m::MeasurementWidget, message::String)
  Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:label,
      """<span foreground="green" font_weight="bold" size="x-large">$message</span>""")
end

function initCallbacks(m::MeasurementWidget)

  println("CAAALLLLBACK")
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
    pos = get.(pos_).*1u"mm"
    moveAbs(getRobot(m.scanner),getRobotSetupUI(m), pos)
    #infoMessage(m, "move to $posString")
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
      #MPIMeasurements.enableSlowDAC(daq, true)
      Gtk.@sigatom setproperty!(m["btnRobotMove",ButtonLeaf],:sensitive,false)

      function update_(::Timer)
        if timerActive

          if daq.params.controlPhase
            MPIMeasurements.controlLoop(daq)
          else
            MPIMeasurements.setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                             zeros(numTxChannels(daq)))
          end

          if length(daq.params.acqFFValues) > 0
            curr1 = daq.params.acqFFValues[1,2]
            curr2 = daq.params.acqFFValues[1,1]
            println("C1=$curr1")
            println("C2=$curr2")
            setSlowDAC(daq, curr1, 0)
            setSlowDAC(daq, curr2, 1)
          end
          sleep(0.5)

          currFr = enableSlowDAC(daq, true)

          uMeas, uRef = readData(daq, 1, currFr+1)
          MPIMeasurements.enableSlowDAC(daq, false)
          MPIMeasurements.setTxParams(daq, daq.params.currTxAmp*0.0, daq.params.currTxPhase*0.0)

          #currFr = MPIMeasurements.currentFrame(daq)
          #uMeas, uRef = readData(daq, 1, currFr+1)

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
    if !isReferenced(getRobot(m.scanner))
      info_dialog("Robot not referenced! Cannot proceed!", mpilab["mainWindow"])
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

        velRobString = getproperty(m["velRob",EntryLeaf], :text, String)
        velRob_ = tryparse.(Float64,split(velRobString,"x"))

        numBGMeas = getproperty(m["adjNumBGMeasurements",AdjustmentLeaf], :value, Int64)

        if any(isnull.(shp_)) || any(isnull.(fov_)) || any(isnull.(center_)) ||
           length(shp_) != 3 || length(fov_) != 3 || length(center_) != 3
          Gtk.@sigatom setproperty!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
          return
        end

        shp = get.(shp_)
        fov = get.(fov_) .*1u"mm"
        ctr = get.(center_) .*1u"mm"
        velRob =get.(velRob_)

        #positions = BreakpointGridPositions(
        #        MeanderingGridPositions( RegularGridPositions(shp,fov,ctr) ),
        #        [1,11], [0.0,0.0,0.0]u"mm" )
        cartGrid = RegularGridPositions(shp,fov,ctr)
        if numBGMeas == 0
          positions = cartGrid
        else
          bgIdx = round.(Int64, linspace(1, length(cartGrid)+numBGMeas, numBGMeas ) )
          bgPos = getGeneralParams(m.scanner)["calibBGPos"]*1u"mm"*1000
          positions = BreakpointGridPositions(cartGrid, bgIdx, bgPos)
        end

        for pos in positions
          isValid = checkCoords(getRobotSetupUI(m), pos)
        end

        setVelocity(getRobot(m.scanner), velRob)

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
              pos = Float64.(ustrip.(uconvert.(u"mm", positions[currPos])))
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
            end
            if currPos > numPos
              stopTx(daq)
              disableACPower(getSurveillanceUnit(m.scanner))
              MPIMeasurements.disconnect(daq)

              setVelocity(getRobot(m.scanner), getDefaultVelocity(getRobot(m.scanner)))
              #moveCenter(getRobot(m.scanner))
              moveAbsUnsafe(getRobot(m.scanner), bgPos)

              Gtk.@sigatom setproperty!(m["lbInfo",LabelLeaf],:label, "")
              currPos = 0
              Gtk.@sigatom setproperty!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)

              if !cancelled
                cancelled = false
                calibNum = getNewCalibNum(m.mdfstore)
                saveasMDF("/tmp/tmp.mdf",
                        calibObj, params)
                saveasMDF(joinpath(calibdir(m.mdfstore),string(calibNum)*".mdf"),
                        MPIFile("/tmp/tmp.mdf"), applyCalibPostprocessing=true)
                updateData!(mpilab.sfBrowser, m.mdfstore)
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


  #@time signal_connect(reinitDAQ, m["adjNumPeriods"], "value_changed", Void, (), false, m)
  @time signal_connect(m["cbSeFo",ComboBoxTextLeaf], :changed) do w
    seq = m.sequences[getproperty(m["cbSeFo",ComboBoxTextLeaf], :active, Int)+1]
    val = readcsv(Pkg.dir("MPIMeasurements","src","Sequences",
                                    seq*".csv"))
    Gtk.@sigatom setproperty!(m["adjNumPeriods",AdjustmentLeaf], :value, size(val,2))
  end

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
  Gtk.@sigatom setproperty!(m["entFramePeriod",EntryLeaf],:text,"$(daq.params.acqFramePeriod) s")
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


  #println(textSeFo)
  #=
  try
    numPatches = getproperty(m["adjNumPatches"], :value, Int64)
    numPeriodsPerPatch = getproperty(m["adjNumPeriods"], :value, Int64)
    txt = "t = (0:($numPatches-1))./($numPatches);"  * textSeFo
    println(txt)
    code = parse(txt)
    println(code)
    currents = eval(code)
    #cat(1,x,reverse(x[2:end-1]))
    println(currents)

    params["acqFFValues"] = repeat(currents, inner=numPeriodsPerPatch)

  catch
    println("Could not parse text")
    params["acqFFValues"] = [0.0]
  end=#
  #params["acqNumPeriodsPerFrame"]=length(params["acqFFValues"])

  return params
end

function setParams(m::MeasurementWidget, params)
  Gtk.@sigatom setproperty!(m["adjNumAverages",AdjustmentLeaf], :value, params["acqNumAverages"])
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
  Gtk.@sigatom setproperty!(m["velRob",EntryLeaf], :text, velRobStr)
  Gtk.@sigatom setproperty!(m["entCurrPos",EntryLeaf], :text, "0.0 x 0.0 x 0.0")
end

function getRobotSetupUI(m::MeasurementWidget)
    coil = getValidHeadScannerGeos()[getproperty(m["cbSafeCoil",ComboBoxTextLeaf], :active, Int)+1]
    obj = getValidHeadObjects()[getproperty(m["cbSafeObject",ComboBoxTextLeaf], :active, Int)+1]
    if obj.name == customPhantom.name
        obj = getCustomPhatom(m)
    end
    setup = RobotSetup("UIRobotSetup",obj,coil,clearance)
    return setup
end

function getCustomPhatom(m::MeasurementWidget)
    cPStr = getproperty(m["entSafetyObj",EntryLeaf],:text,String)
    cP_ = tryparse.(Float64,split(cPStr,"x"))
    cP= get.(cP_) .*1u"mm"
    return Rectangle(cP[1],cP[2], "UI Custom Phantom")
end
