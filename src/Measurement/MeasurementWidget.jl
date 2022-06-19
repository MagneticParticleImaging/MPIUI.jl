

mutable struct SystemMatrixRobotMeas
end

function SystemMatrixRobotMeas(scanner, mdfstore)
  return SystemMatrixRobotMeas()
end

mutable struct MeasState
end

mutable struct ProtocolStatus
  waitingOnReply::Union{ProtocolEvent, Nothing}
end

mutable struct MeasurementWidget{T} <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  scanner::T
  protocol::Union{Protocol, Nothing}
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing}
  progress::Union{ProgressEvent, Nothing}
  protocolStatus::ProtocolStatus
  dataBGStore::Array{Float32,4}
  mdfstore::MDFDatasetStore
  currStudyName::String
  currStudyDate::DateTime
  filenameExperiment::String
  rawDataWidget::RawDataWidget
  expanded::Bool
  message::String
  calibState::SystemMatrixRobotMeas
  calibInProgress::Bool
end

include("Measurement.jl")
include("Calibration.jl")
include("SequenceBrowser.jl")



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
    mdfstore = MDFDatasetStore( generalParams(scanner).datasetStore )
    protocol = Protocol(scanner.generalParams.defaultProtocol, scanner)
  else
    scanner = nothing
    mdfstore = MDFDatasetStore( "Dummy" )
    protocol = nothing
  end

  b = GtkBuilder(filename=uifile)
  mainBox = object_(b, "boxMeasurement",BoxLeaf)

  proto = ProtocolStatus(nothing)
  m = MeasurementWidget( mainBox.handle, b,
                  scanner, protocol, nothing, nothing, proto, zeros(Float32,0,0,0,0), mdfstore, "", now(),
                  "", RawDataWidget(), false, "",
                  SystemMatrixRobotMeas(scanner, mdfstore), false)
  Gtk4.GLib.gobject_move_ref(m, mainBox)

  @debug "Type constructed"

  @debug "InvalidateBG"
  invalidateBG(C_NULL, m)

  push!(m["boxMeasTabVisu",BoxLeaf],m.rawDataWidget)
  set_gtk_property!(m["boxMeasTabVisu",BoxLeaf],:expand,m.rawDataWidget,true)

  #= TODO @debug "Read safety parameters"
  @idle_add_guarded begin
    empty!(m["cbSafeCoil", Gtk4.GtkComboBoxTextLeaf])
    for coil in getValidHeadScannerGeos()
        push!(m["cbSafeCoil",Gtk4.GtkComboBoxTextLeaf], coil.name)
    end
    set_gtk_property!(m["cbSafeCoil",Gtk4.GtkComboBoxTextLeaf], :active, 0)
    empty!(m["cbSafeObject", Gtk4.GtkComboBoxTextLeaf])
    for obj in getValidHeadObjects()
        push!(m["cbSafeObject",Gtk4.GtkComboBoxTextLeaf], name(obj))
    end
    set_gtk_property!(m["cbSafeObject",Gtk4.GtkComboBoxTextLeaf], :active, 0)

    signal_connect(m["cbSafeObject",Gtk4.GtkComboBoxTextLeaf], :changed) do w
        ind = get_gtk_property(m["cbSafeObject",Gtk4.GtkComboBoxTextLeaf],:active,Int)+1
        if getValidHeadObjects()[ind].name==customPhantom3D.name
            sObjStr = @sprintf("%.2f x %.2f x %.2f", ustrip(customPhantom3D.length), ustrip(crosssection(customPhantom3D).width),ustrip(crosssection(customPhantom3D).height))
            set_gtk_property!(m["entSafetyObj", GtkEntryLeaf],:text, sObjStr)
            set_gtk_property!(m["entSafetyObj", GtkEntryLeaf],:sensitive,true)
        else
            set_gtk_property!(m["entSafetyObj", GtkEntryLeaf],:sensitive,false)
        end
    end

    @idle_add_guarded begin
      empty!(m["cbWaveform", Gtk4.GtkComboBoxTextLeaf])
      for w in RedPitayaDAQServer.waveforms()
        push!(m["cbWaveform",Gtk4.GtkComboBoxTextLeaf], w)
      end
      set_gtk_property!(m["cbWaveform",Gtk4.GtkComboBoxTextLeaf], :active, 0) 
    end
  end =#

  @debug "Online / Offline"
  if m.scanner != nothing
    isRobRef = isReferenced(getRobot(m.scanner))
    setInfoParams(m)
    # TODO setParams(m, merge!(generalParams(m.scanner),toDict(getDAQ(m.scanner).params)))
    setParams(m, m.scanner)
    @idle_add_guarded set_gtk_property!(m["entConfig",GtkEntryLeaf],:text,filenameConfig)
    #@idle_add_guarded set_gtk_property!(m["btnReferenceDrive",ButtonLeaf],:sensitive,!isRobRef)
    # TODO enableRobotMoveButtons(m,isRobRef)
    # TODO enableDFWaveformControls(m, get(getGeneralParams(m.scanner), "allowDFWaveformChanges", false))

    if isRobRef
      try
        rob = getRobot(m.scanner)
        isValid = checkCoords(getRobotSetupUI(m), getPos(rob), getMinMaxPosX(rob))
      catch
        # TODO enableRobotMoveButtons(m,false)
        #@idle_add_guarded set_gtk_property!(m["btnMovePark",ButtonLeaf],:sensitive,true)
      end
    end

    @idle_add_guarded updateCalibTime(C_NULL, m)
  else
    @idle_add_guarded begin
      set_gtk_property!(m["tbMeasure",ToolButtonLeaf],:sensitive,false)
      set_gtk_property!(m["tbMeasureBG",ToolButtonLeaf],:sensitive,false)
      set_gtk_property!(m["tbContinous",ToggleToolButtonLeaf],:sensitive,false)
      set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,false)
    end
  end

  @idle_add_guarded set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,false)

  @debug "InitCallbacks"

  if m.scanner != nothing
    initCallbacks(m)
  end

  # Dummy plotting for warmstart during measurement
  @idle_add_guarded updateData(m.rawDataWidget, ones(Float32,10,1,1,1), 1.0)

  if !isnothing(m.scanner) && !isnothing(m.protocol.params.sequence)
    @idle_add_guarded begin
      set_gtk_property!(m["adjNumFGFrames", Gtk4.GtkAdjustmentLeaf], :value, acqNumFrames(protocol.params.sequence))
      set_gtk_property!(m["adjNumFrameAverages", Gtk4.GtkAdjustmentLeaf], :value, acqNumFrameAverages(protocol.params.sequence))
      set_gtk_property!(m["adjNumAverages", Gtk4.GtkAdjustmentLeaf], :value, acqNumAverages(protocol.params.sequence))
    end
  end

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

  #signal_connect(measurement, m["tbMeasure",ToolButtonLeaf], "clicked", Nothing, (), false, m )
  #signal_connect(measurementBG, m["tbMeasureBG",ToolButtonLeaf], "clicked", Nothing, (), false, m)


  signal_connect(m["tbMeasure",ToolButtonLeaf], :clicked) do w
    measurement(C_NULL, m)
  end

  signal_connect(m["tbMeasureBG",ToolButtonLeaf], :clicked) do w
    measurementBG(C_NULL, m)
  end

  signal_connect(m["btnReloadConfig",ButtonLeaf], :clicked) do w
    reloadConfig(m)
  end


  signal_connect(m["btLoadArbPos",ButtonLeaf],:clicked) do w
    loadArbPos(m)
  end


  timer = nothing
  timerActive = false
  counter = 0
  signal_connect(m["tbContinous",ToggleToolButtonLeaf], :toggled) do w
    daq = getDAQ(m.scanner)
    if get_gtk_property(m["tbContinous",ToggleToolButtonLeaf], :active, Bool)
      params = merge!(getGeneralParams(m.scanner),getParams(m))
      MPIMeasurements.updateParams!(daq, params)
      enableACPower(getSurveillanceUnit(m.scanner), m.scanner)
      setEnabled(getRobot(m.scanner), false)
      startTx(daq)

      MPIMeasurements.controlLoop(daq)

      timerActive = true
      counter = 0
      #@idle_add_guarded set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,false)

      function update_(::Timer)
        if timerActive

          MPIMeasurements.controlLoop(daq)

          currFr = enableSlowDAC(daq, true, params["acqNumFGFrames"],
                  daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

          uMeas, uRef = readData(daq, params["acqNumFGFrames"], currFr)
          MPIMeasurements.setTxParams(daq, daq.params.currTx*0.0)

          deltaT = daq.params.dfCycle / daq.params.numSampPerPeriod

          @idle_add_guarded updateData(m.rawDataWidget, uMeas, deltaT)

          sleep(get_gtk_property(m["adjPause",Gtk4.GtkAdjustmentLeaf],:value,Float64))

          if mod(counter,20) == 0
            # This is a hack. The RP gets issues when measuring to long (about 30 minutes)
            # it seems to help to restart
            stopTx(daq)
            startTx(daq)
          end

          counter += 1
        else
          MPIMeasurements.enableSlowDAC(daq, false)
          setEnabled(getRobot(m.scanner), true)
          stopTx(daq)
          disableACPower(getSurveillanceUnit(m.scanner), m.scanner)
          MPIMeasurements.disconnect(daq)
          #@idle_add_guarded set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,true)
          close(timer)
        end
      end
      timer = Timer(update_, 0.0, interval=0.2)
    else
      timerActive = false
    end
  end

  signal_connect(m["tbCancel",ToolButtonLeaf], :clicked) do w
    try
       @idle_add_guarded begin
         isnothing(m.biChannel) || !isopen(m.biChannel) || put!(m.biChannel, CancelEvent())
         m.calibInProgress = false
       end
    catch ex
      showError(ex)
    end
  end


  signal_connect(m["tbCalibration",ToggleToolButtonLeaf], :toggled) do w
   try

    if get_gtk_property(m["tbCalibration",ToggleToolButtonLeaf], :active, Bool)
      if m.calibInProgress
        @info "Resume protocol"
        isnothing(m.biChannel) || !isopen(m.biChannel) || isfull(m.biChannel) || put!(m.biChannel, ResumeEvent())
      else
        executeCalibrationProtocol(m)
        if !isnothing(m.biChannel)
          @info "Start event handler"
          timerCalibration = Timer( timer -> calibEventHandler(m, timer), 0.0, interval=0.1)
          m.calibInProgress = true
        else 
          return
        end
      end
      @idle_add_guarded set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,true)
    else
      @info "Stop protocol"
      isnothing(m.biChannel) || !isopen(m.biChannel) || isfull(m.biChannel) || put!(m.biChannel, StopEvent())
    end
    catch ex
     showError(ex)
   end
  end


  #signal_connect(invalidateBG, m["adjDFStrength"], "value_changed", Nothing, (), false, m)
  #signal_connect(invalidateBG, m["adjNumPatches"], "value_changed", Nothing, (), false, m)
  #signal_connect(invalidateBG, m["adjNumPeriods"], , Nothing, (), false, m)

  for adj in ["adjDFStrength", "adjNumSubperiods"]
    signal_connect(m[adj,Gtk4.GtkAdjustmentLeaf], "value_changed") do w
      invalidateBG(C_NULL, m)
    end
  end

  for adj in ["adjNumBGMeasurements","adjPause","adjNumAverages"]
    signal_connect(m[adj,Gtk4.GtkAdjustmentLeaf], "value_changed") do w
      updateCalibTime(C_NULL, m)
      setInfoParams(m)
    end
  end

  for adj in ["adjNumFGFrames","adjNumFrameAverages"]
    signal_connect(m[adj,Gtk4.GtkAdjustmentLeaf], "value_changed") do w
      setInfoParams(m)
    end
  end

  # Update sequence
  signal_connect(m["adjNumFGFrames", Gtk4.GtkAdjustmentLeaf], "value_changed") do w
    if !isnothing(m.protocol.params.sequence)
      acqNumFrames(m.protocol.params.sequence, get_gtk_property(m["adjNumFGFrames",Gtk4.GtkAdjustmentLeaf], :value, Int64))
    end
  end
  signal_connect(m["adjNumFrameAverages",Gtk4.GtkAdjustmentLeaf], "value_changed") do w
    if !isnothing(m.protocol.params.sequence)
      acqNumFrameAverages(m.protocol.params.sequence, get_gtk_property(m["adjNumFrameAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64))
    end

  end
  signal_connect(m["adjNumAverages",Gtk4.GtkAdjustmentLeaf], "value_changed") do w
    if !isnothing(m.protocol.params.sequence)
      acqNumAverages(m.protocol.params.sequence, get_gtk_property(m["adjNumAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64))
    end
  end

  signal_connect(m["entGridShape",GtkEntryLeaf], "changed") do w
    updateCalibTime(C_NULL, m)
  end


  signal_connect(m["btnSelectSequence",ButtonLeaf], :clicked) do w
    @info "Moin"
    @info getParams(m)
    dlg = SequenceSelectionDialog(m.scanner, getParams(m))
    ret = run(dlg)
    if ret == GtkResponseType.ACCEPT
      if hasselection(dlg.selection)
        seq = getSelectedSequence(dlg)
        updateSequence(m, seq)
      end
    end
    destroy(dlg)
  end


  
  


  signal_connect(m["cbWaveform",Gtk4.GtkComboBoxTextLeaf], :changed) do w
    invalidateBG(C_NULL, m)
  end

end

function updateSequence(m::MeasurementWidget, seq::AbstractString)
  s = m.protocol.params.sequence = Sequence(m.scanner, seq)
  dfString = *([ string(x*1e3," x ") for x in diag(ustrip.(dfStrength(s)[1,:,:])) ]...)[1:end-3]
  dfDividerStr = *([ string(x," x ") for x in unique(vec(dfDivider(s))) ]...)[1:end-3]

  @idle_add_guarded begin
    set_gtk_property!(m["entSequenceName",GtkEntryLeaf], :text, seq)

    set_gtk_property!(m["entNumPeriods",GtkEntryLeaf], :text, "$(acqNumPeriodsPerFrame(s))")
    set_gtk_property!(m["entNumPatches",GtkEntryLeaf], :text, "$(acqNumPatches(s))")

    set_gtk_property!(m["adjNumFGFrames", Gtk4.GtkAdjustmentLeaf], :value, acqNumFrames(s))
    set_gtk_property!(m["adjNumFrameAverages", Gtk4.GtkAdjustmentLeaf], :value, acqNumFrameAverages(s))
    set_gtk_property!(m["adjNumAverages", Gtk4.GtkAdjustmentLeaf], :value, acqNumAverages(s))

    set_gtk_property!(m["entDFStrength",GtkEntryLeaf], :text, dfString)
    set_gtk_property!(m["entDFDivider",GtkEntryLeaf], :text, dfDividerStr)

    setInfoParams(m)
  end

end

function updateCalibTime(widgetptr::Ptr, m::MeasurementWidget)
  daq = getDAQ(m.scanner)

  shpString = get_gtk_property(m["entGridShape",GtkEntryLeaf], :text, String)
  shp = tryparse.(Int64,split(shpString,"x"))
  numBGMeas = get_gtk_property(m["adjNumBGMeasurements",Gtk4.GtkAdjustmentLeaf], :value, Int64)
  numBGFrames = get_gtk_property(m["adjNumBGFrames",Gtk4.GtkAdjustmentLeaf], :value, Int64)

  if any(shp .== nothing) length(shp) != 3
    return
  end

  robotMoveTime = 0.8
  robotMoveTimePark = 13.8

  numPeriods = tryparse(Int64, get_gtk_property(m["entNumPeriods", GtkEntryLeaf], :text, String))
  numPeriods = numPeriods == nothing ? 1 : numPeriods

  daqTime_ = get_gtk_property(m["adjNumAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64) *
                     numPeriods * ustrip.(dfCycle(m.protocol.params.sequence))

  daqTime = daqTime_ * (get_gtk_property(m["adjNumFrameAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64)+1)

  daqTimeBG = daqTime_ * (numBGFrames + 1)

  pauseTime = get_gtk_property(m["adjPause",Gtk4.GtkAdjustmentLeaf],:value,Float64)

  calibTime = (daqTime + pauseTime + robotMoveTime) * prod(shp) +
              (daqTimeBG + pauseTime + robotMoveTimePark) * numBGMeas

  calibTimeMin = calibTime/60

  calibStr = ""
  if calibTimeMin > 60
    calibStr = "$(round(Int,calibTimeMin/60)) h "
    calibTimeMin = rem(calibTimeMin, 60)
  end
  calibStr = string(calibStr,@sprintf("%.1f",calibTime/60)," min")

  @idle_add_guarded set_gtk_property!(m["entCalibTime",GtkEntryLeaf],:text, calibStr)
  return
end


function invalidateBG(widgetptr::Ptr, m::MeasurementWidget)
  m.dataBGStore = zeros(Float32,0,0,0,0)
  infoMessage(m, "No BG Measurement Available!", "orange")
  return nothing
end

function setInfoParams(m::MeasurementWidget)
  daq = getDAQ(m.scanner)
  #if length(daq.params.dfFreq) > 1
  #  freqStr = "$(join([ " $(round(x, digits=2)) x" for x in daq.params.dfFreq ])[2:end-2]) Hz"
  #else
  #  freqStr = "$(round(daq.params.dfFreq[1], digits=2)) Hz"
  #end
  #@idle_add_guarded set_gtk_property!(m["entDFFreq",GtkEntryLeaf],:text,freqStr)
  #@idle_add_guarded set_gtk_property!(m["entDFPeriod",GtkEntryLeaf],:text,"$(daq.params.dfCycle*1000) ms")
  numPeriods = tryparse(Int64, get_gtk_property(m["entNumPeriods", GtkEntryLeaf], :text, String))

  framePeriod = get_gtk_property(m["adjNumAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64) *
                  (numPeriods == nothing ? 1 : numPeriods)  *
                  ustrip(dfCycle(m.protocol.params.sequence))

  totalPeriod = framePeriod * get_gtk_property(m["adjNumFrameAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64) *
                              get_gtk_property(m["adjNumFGFrames",Gtk4.GtkAdjustmentLeaf], :value, Int64)

  @idle_add_guarded begin
    set_gtk_property!(m["entFramePeriod",GtkEntryLeaf],:text,"$(@sprintf("%.5f",framePeriod)) s")

    set_gtk_property!(m["entTotalPeriod",GtkEntryLeaf],:text,"$(@sprintf("%.2f",totalPeriod)) s")
  end
end


function getParams(m::MeasurementWidget)
  params = Dict{String,Any}() # TODO toDict(getDAQ(m.scanner).params)

  params["acqNumAverages"] = get_gtk_property(m["adjNumAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64)
  params["acqNumFrameAverages"] = get_gtk_property(m["adjNumFrameAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64)
  params["acqNumSubperiods"] = get_gtk_property(m["adjNumSubperiods",Gtk4.GtkAdjustmentLeaf], :value, Int64)

  params["acqNumFGFrames"] = get_gtk_property(m["adjNumFGFrames",Gtk4.GtkAdjustmentLeaf], :value, Int64)
  params["acqNumBGFrames"] = get_gtk_property(m["adjNumBGFrames",Gtk4.GtkAdjustmentLeaf], :value, Int64)
  #TODO params["acqNumPeriodsPerFrame"] = parse(Int64, get_gtk_property(m["entNumPeriods", GtkEntryLeaf], :text, String))
  params["studyName"] = m.currStudyName
  params["studyDate"] = m.currStudyDate
  params["studyDescription"] = ""
  params["experimentDescription"] = get_gtk_property(m["entExpDescr",GtkEntryLeaf], :text, String)
  params["experimentName"] = get_gtk_property(m["entExpName",GtkEntryLeaf], :text, String)
  params["scannerOperator"] = get_gtk_property(m["entOperator",GtkEntryLeaf], :text, String)
  params["tracerName"] = [get_gtk_property(m["entTracerName",GtkEntryLeaf], :text, String)]
  params["tracerBatch"] = [get_gtk_property(m["entTracerBatch",GtkEntryLeaf], :text, String)]
  params["tracerVendor"] = [get_gtk_property(m["entTracerVendor",GtkEntryLeaf], :text, String)]
  params["tracerVolume"] = [1e-3*get_gtk_property(m["adjTracerVolume",Gtk4.GtkAdjustmentLeaf], :value, Float64)]
  params["tracerConcentration"] = [1e-3*get_gtk_property(m["adjTracerConcentration",Gtk4.GtkAdjustmentLeaf], :value, Float64)]
  params["tracerSolute"] = [get_gtk_property(m["entTracerSolute",GtkEntryLeaf], :text, String)]

  dfString = get_gtk_property(m["entDFStrength",GtkEntryLeaf], :text, String)
  params["dfStrength"] = parse.(Float64,split(dfString," x "))*1e-3
  dfDividerStr = get_gtk_property(m["entDFDivider",GtkEntryLeaf], :text, String)
  params["dfDivider"] = parse.(Int64,split(dfDividerStr," x "))

  params["acqFFSequence"] = get_gtk_property(m["entSequenceName",GtkEntryLeaf], :text, String)
  #params["dfWaveform"] = RedPitayaDAQServer.waveforms()[get_gtk_property(m["cbWaveform",Gtk4.GtkComboBoxTextLeaf], :active, Int)+1]

  #jump = get_gtk_property(m["entDFJumpSharpness",GtkEntryLeaf], :text, String)
  #params["jumpSharpness"] = parse(Float64, jump)

  params["storeAsSystemMatrix"] = get_gtk_property(m["cbStoreAsSystemMatrix",CheckButtonLeaf],:active, Bool)

  return params
end

function setParams(m::MeasurementWidget, scanner::MPIScanner)
  seq = m.protocol.params.sequence
  gen = scanner.generalParams 

  @idle_add_guarded set_gtk_property!(m["adjNumAverages",Gtk4.GtkAdjustmentLeaf], :value, 1 ) # TODO params["acqNumAverages"])
  @idle_add_guarded set_gtk_property!(m["adjNumFrameAverages",Gtk4.GtkAdjustmentLeaf], :value, 1 ) # TODO params["acqNumFrameAverages"])
  @idle_add_guarded set_gtk_property!(m["adjNumSubperiods",Gtk4.GtkAdjustmentLeaf], :value, 1 ) # TODO get(params,"acqNumSubperiods",1))
  @idle_add_guarded set_gtk_property!(m["adjNumFGFrames",Gtk4.GtkAdjustmentLeaf], :value, 1 ) # TODO params["acqNumFrames"])
  @idle_add_guarded set_gtk_property!(m["adjNumBGFrames",Gtk4.GtkAdjustmentLeaf], :value, 1 ) # TODO params["acqNumFrames"])
  #@idle_add_guarded set_gtk_property!(m["entStudy"], :text, params["studyName"])
  @idle_add_guarded set_gtk_property!(m["entExpDescr",GtkEntryLeaf], :text, "" ) # TODO params["studyDescription"] )
  @idle_add_guarded set_gtk_property!(m["entOperator",GtkEntryLeaf], :text, "default" ) # gp.operator)
  dfString = *([ string(x*1e3," x ") for x in diag(ustrip.(dfStrength(seq)[1,:,:])) ]...)[1:end-3]
  @idle_add_guarded set_gtk_property!(m["entDFStrength",GtkEntryLeaf], :text, dfString)
  dfDividerStr = *([ string(x," x ") for x in unique(vec(dfDivider(seq))) ]...)[1:end-3]
  @idle_add_guarded set_gtk_property!(m["entDFDivider",GtkEntryLeaf], :text, dfDividerStr)
  @idle_add_guarded set_gtk_property!(m["entSequenceName", GtkEntryLeaf], :text, MPIFiles.name(seq))

  #TODO @idle_add_guarded set_gtk_property!(m["entDFJumpSharpness",GtkEntryLeaf], :text, "$(get(params,"jumpSharpness", 0.1))")

  #= TODO @idle_add_guarded set_gtk_property!(m["entTracerName",GtkEntryLeaf], :text, params["tracerName"][1])
  @idle_add_guarded set_gtk_property!(m["entTracerBatch",GtkEntryLeaf], :text, params["tracerBatch"][1])
  @idle_add_guarded set_gtk_property!(m["entTracerVendor",GtkEntryLeaf], :text, params["tracerVendor"][1])
  @idle_add_guarded set_gtk_property!(m["adjTracerVolume",Gtk4.GtkAdjustmentLeaf], :value, 1000*params["tracerVolume"][1])
  @idle_add_guarded set_gtk_property!(m["adjTracerConcentration",Gtk4.GtkAdjustmentLeaf], :value, 1000*params["tracerConcentration"][1])
  @idle_add_guarded set_gtk_property!(m["entTracerSolute",GtkEntryLeaf], :text, params["tracerSolute"][1])
  =#

  #=if haskey(params,"acqFFSequence")
    seq = params["acqFFSequence"]
    if seq in sequenceList()
      updateSequence(m, seq)
    end
  else
      @idle_add_guarded set_gtk_property!(m["entNumPeriods",GtkEntryLeaf], :text, params["acqNumPeriodsPerFrame"])
      @idle_add_guarded set_gtk_property!(m["entNumPatches",GtkEntryLeaf], :text, "1")
  end=#
  @idle_add_guarded set_gtk_property!(m["entNumPeriods",GtkEntryLeaf], :text, acqNumPeriodsPerFrame(seq))
  @idle_add_guarded set_gtk_property!(m["entNumPatches",GtkEntryLeaf], :text, acqNumPatches(seq))

  #= TODO if haskey(params,"dfWaveform")
    idx = findfirst_(RedPitayaDAQServer.waveforms(), params["dfWaveform"])
    if idx > 0
      @idle_add_guarded set_gtk_property!(m["cbWaveform",Gtk4.GtkComboBoxTextLeaf], :active, idx-1)
    end
  else
      @idle_add_guarded set_gtk_property!(m["cbWaveform",Gtk4.GtkComboBoxTextLeaf], :active, 0)
  end  =#

  calibProtocol = Protocol("RobotBasedSystemMatrix", m.scanner)
  if calibProtocol.params.positions != nothing
    shp = MPIFiles.shape(calibProtocol.params.positions)
    shpStr = @sprintf("%d x %d x %d", shp[1],shp[2],shp[3])
    fov = Float64.(ustrip.(uconvert.(Unitful.mm,MPIFiles.fieldOfView(calibProtocol.params.positions)))) # convert to mm
    fovStr = @sprintf("%.2f x %.2f x %.2f", fov[1],fov[2],fov[3])
    ctr = Float64.(ustrip.(uconvert.(Unitful.mm,MPIFiles.fieldOfViewCenter( calibProtocol.params.positions)))) # convert to mm
    ctrStr = @sprintf("%.2f x %.2f x %.2f", ctr[1],ctr[2],ctr[3])
    @idle_add_guarded set_gtk_property!(m["entGridShape",GtkEntryLeaf], :text, shpStr)
    @idle_add_guarded set_gtk_property!(m["entFOV",GtkEntryLeaf], :text, fovStr)
    @idle_add_guarded set_gtk_property!(m["entCenter",GtkEntryLeaf], :text, ctrStr)
    # TODO @idle_add_guarded set_gtk_property!(m["adjNumBGMeasurements",Gtk4.GtkAdjustmentLeaf], :value, p["calibNumBGMeasurements"])
  end
  #=velRob = getDefaultVelocity(getRobot(m.scanner))
  velRobStr = @sprintf("%.d x %.d x %.d", velRob[1],velRob[2],velRob[3])
  @idle_add_guarded set_gtk_property!(m["entVelRob",GtkEntryLeaf], :text, velRobStr)
  @idle_add_guarded set_gtk_property!(m["entCurrPos",GtkEntryLeaf], :text, "0.0 x 0.0 x 0.0")=#

  @idle_add_guarded set_gtk_property!(m["adjPause",Gtk4.GtkAdjustmentLeaf], :value, calibProtocol.params.waitTime )
end

function getRobotSetupUI(m::MeasurementWidget)
    coil = getValidHeadScannerGeos()[get_gtk_property(m["cbSafeCoil",Gtk4.GtkComboBoxTextLeaf], :active, Int)+1]
    obj = getValidHeadObjects()[get_gtk_property(m["cbSafeObject",Gtk4.GtkComboBoxTextLeaf], :active, Int)+1]
    if obj.name == customPhantom3D.name
        obj = getCustomPhantom(m)
    end
    setup = RobotSetup("UIRobotSetup",obj,coil,clearance)
    return setup
end

function getCustomPhantom(m::MeasurementWidget)
    cPStr = get_gtk_property(m["entSafetyObj",GtkEntryLeaf],:text,String)
    cP_ = tryparse.(Float64,split(cPStr,"x"))
    cP= cP_ .*1Unitful.mm
    return Cuboid(Rectangle(cP[2],cP[3], "UI Custom Phantom"),cP[1],"UI Custom Phantom 3D")
end



function enableDFWaveformControls(m::MeasurementWidget, enable::Bool)
  @idle_add_guarded begin
    set_gtk_property!(m["cbWaveform",Gtk4.GtkComboBoxTextLeaf],:sensitive,enable)
    set_gtk_property!(m["entDFDivider",GtkEntryLeaf],:sensitive,enable)
  end
end


function loadArbPos(m::MeasurementWidget)
      filter = Gtk4.GtkFileFilter(pattern=String("*.h5"), mimetype=String("HDF5 File"))
      filename = open_dialog("Select Arbitrary Position File", GtkNullContainer(), (filter, ))
      @idle_add_guarded set_gtk_property!(m["entArbitraryPos",GtkEntryLeaf],:text,filename)
end

function clear(proto::ProtocolStatus)
  proto.waitingOnReply = nothing
end