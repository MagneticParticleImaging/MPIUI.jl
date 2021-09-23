
function executeCalibrationProtocol(m::MeasurementWidget)
  @info "Gettomg positions"
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

  shp = shp_
  fov = fov_ .*1Unitful.mm
  ctr = center_ .*1Unitful.mm
  velRob = velRob_

  if get_gtk_property(m["cbUseArbitraryPos",CheckButtonLeaf], :active, Bool) == false
      cartGrid = RegularGridPositions(shp,fov,ctr)#
  else
      filename = get_gtk_property(m["entArbitraryPos",EntryLeaf],:text,String)
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

  #for pos in positions
  #  isValid = checkCoords(getRobotSetupUI(m), uconvert.(Unitful.mm,pos), getMinMaxPosX(getRobot(m.scanner)))
  #end

  protocol = Protocol("RobotBasedSystemMatrix", m.scanner)
  clear(m.protocolStatus)
  m.scanner.currentProtocol = protocol

  protocol.params.positions = positions
  protocol.params.bgFrames = numBGMeas
  @info "Init protocol"
  m.biChannel = MPIMeasurements.init(protocol)
  @show m.biChannel
  @info "Execute protocol"
  @tspawnat 4 execute(protocol)
  @info "Return channel"
  return m.biChannel
end

function displayCalibration(m::MeasurementWidget, timerCalibration::Timer)
  try
    channel = m.biChannel
    finished = false

    if isnothing(channel)
      return
    end

    if isready(channel)
      event = take!(channel)
      finished = handleCalibEvent(m, event, EventType(m, event))
    end

    if isnothing(m.protocolStatus.waitingOnReply) && !finished
      @info "Asking for first progress"
      progressQuery = ProgressQueryEvent()
      put!(channel, progressQuery)
      m.protocolStatus.waitingOnReply = progressQuery
    end

    if finished 
      m.calibInProgress = false
      close(timerCalibration)
      @idle_add begin
        set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
        set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,false)
        #set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,true)
      end
    end

  catch ex
    close(timerCalibration)
    @idle_add begin
      set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
      set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,false)
      #set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,true)
    end
    showError(ex)
  end
end

function handleCalibEvent(m::MeasurementWidget, event::ExceptionEvent, ::UnwantedEvent)
  @idle_add info_dialog(event.message, mpilab[]["mainWindow"])
  return true
end

function handleCalibEvent(m::MeasurementWidget, event::ProgressEvent, ::WantedEvent)
  channel = m.biChannel
  # New Progress noticed
  if isnothing(m.progress) || m.progress != event
    @info "New progress, asking for frame $(event.done)"
    m.progress = event
    dataQuery = DataQueryEvent("SIGNAL")
    put!(channel, dataQuery)
    m.protocolStatus.waitingOnReply = dataQuery
  else
    # Ask for next progress
    progressQuery = ProgressQueryEvent()
    put!(channel, progressQuery)
    m.protocolStatus.waitingOnReply = progressQuery
  end
  return false
end

function handleCalibEvent(m::MeasurementWidget, event::DataAnswerEvent, ::WantedEvent)
  channel = m.biChannel
  if event.query.message == "SIGNAL"
    @info "Received current signal"
    frame = event.data
    if !isnothing(frame)
      infoMessage(m, "$(m.progress.unit) $(m.progress.done) / $(m.progress.total)", "green")
      if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf], :active, Bool)
        seq = m.scanner.currentSequence
        deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
        updateData(m.rawDataWidget, frame, deltaT)
      end
    end
    # Ask for next progress
    progressQuery = ProgressQueryEvent()
    put!(channel, progressQuery)
    m.protocolStatus.waitingOnReply = progressQuery
  end
  return false
end

function handleCalibEvent(m::MeasurementWidget, event::ProtocolEvent, ::UnwantedEvent)
  @info "Discard event $(typeof(event))"
  return false
end

function handleCalibEvent(m::MeasurementWidget, event::FinishedNotificationEvent, ::UnwantedEvent)
  channel = m.biChannel
  # We noticed end and overwrite the query we are waiting for
  @info "Received finish notification, normally ask for storage but we just finish in this version"
  #bufferRequest = DataQueryEvent("BUFFER")
  #put!(channel, bufferRequest)
  #m.protocolStatus.waitingOnReply = bufferRequest
  put!(channel, FinishedAckEvent())
  return true
end