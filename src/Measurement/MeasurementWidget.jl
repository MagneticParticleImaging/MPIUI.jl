
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
  calibState::CalibState
  measState::MeasState
end

include("Measurement.jl")
include("Calibration.jl")
include("Surveillance.jl")
include("Robot.jl")




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
  uifile = joinpath(@__DIR__,"..","builder","measurementWidget.ui")
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
                  "", RawDataWidget(), String[], false, "", CalibState(), MeasState())
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
    isRobRef = isReferenced(getRobot(m.scanner))
    setInfoParams(m)
    setParams(m, merge!(getGeneralParams(m.scanner),toDict(getDAQ(m.scanner).params)))
    @idle_add set_gtk_property!(m["entConfig",EntryLeaf],:text,filenameConfig)
    @idle_add set_gtk_property!(m["btnReferenceDrive",ButtonLeaf],:sensitive,!isRobRef)
    enableRobotMoveButtons(m,isRobRef)

    if isRobRef
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
    @idle_add begin
      set_gtk_property!(m["tbMeasure",ToolButtonLeaf],:sensitive,false)
      set_gtk_property!(m["tbMeasureBG",ToolButtonLeaf],:sensitive,false)
      set_gtk_property!(m["tbContinous",ToggleToolButtonLeaf],:sensitive,false)
      set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,false)
    end
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


function infoMessage(m::MeasurementWidget, message::String, color::String="green")
  m.message = """<span foreground="$color" font_weight="bold" size="x-large">$message</span>"""
  infoMessage(mpilab[], m.message)
end

function initCallbacks(m::MeasurementWidget)

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
    robotMove(m)
  end

  @time signal_connect(m["btLoadArbPos",ButtonLeaf],:clicked) do w
    loadArbPos(m)
  end

  @time signal_connect(m["btnMovePark",ButtonLeaf], :clicked) do w
      try
        movePark(m)
      catch ex
       showError(ex)
      end
  end

  @time signal_connect(m["btnMoveAssemblePos",ButtonLeaf], :clicked) do w
    moveAssemblePos(m)
  end

  @time signal_connect(m["btnReferenceDrive",ButtonLeaf], :clicked) do w
    referenceDrive(m)
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

  @time signal_connect(m["tbCancel",ToolButtonLeaf], :clicked) do w
    try
       MPIMeasurements.cancel(m.calibState)
    catch ex
      showError(ex)
    end
  end


  @time signal_connect(m["tbCalibration",ToggleToolButtonLeaf], :toggled) do w
   try
    if !isReferenced(getRobot(m.scanner))
      info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
      @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
      return
    end

    if get_gtk_property(m["tbCalibration",ToggleToolButtonLeaf], :active, Bool)
      if isStarted(m.calibState)
        m.calibState.calibrationActive = true
      else
        # start bg calibration
        doCalibration(m)
        # start display thread
        #g_timeout_add( ()->displayCalibration(m), 1)
        timerCalibration = Timer( timer -> displayCalibration(m, timer), 0.0, interval=0.1)
      end
    else
      m.calibState.calibrationActive = false
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
  shp = tryparse.(Int64,split(shpString,"x"))
  numBGMeas = get_gtk_property(m["adjNumBGMeasurements",AdjustmentLeaf], :value, Int64)
  numBGFrames = get_gtk_property(m["adjNumBGFrames",AdjustmentLeaf], :value, Int64)

  if any(shp .== nothing) length(shp) != 3
    return
  end

  robotMoveTime = 0.8
  robotMoveTimePark = 13.8

  daqTime_ = get_gtk_property(m["adjNumAverages",AdjustmentLeaf], :value, Int64) *
             get_gtk_property(m["adjNumPeriods",AdjustmentLeaf], :value, Int64) *
            daq.params.dfCycle

  daqTime = daqTime_ * (get_gtk_property(m["adjNumFrameAverages",AdjustmentLeaf], :value, Int64)+1)

  daqTimeBG = daqTime_ * (numBGFrames + 1)

  pauseTime = get_gtk_property(m["adjPause",AdjustmentLeaf],:value,Float64)

  calibTime = (daqTime + pauseTime + robotMoveTime) * prod(shp) +
              (daqTimeBG + pauseTime + robotMoveTimePark) * numBGMeas

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
    cP= cP_ .*1Unitful.mm
    return Cuboid(Rectangle(cP[2],cP[3], "UI Custom Phantom"),cP[1],"UI Custom Phantom 3D")
end