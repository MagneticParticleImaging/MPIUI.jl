
function executeCalibrationProtocol(m::MeasurementWidget)
  @info "Getting positions"
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
    @warn "Mismatch dimension for positions"
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
    bgPos = namedPosition(getRobot(m.scanner),"park")
    positions = BreakpointGridPositions(cartGrid, bgIdx, bgPos)
  end

  #for pos in positions
  #  isValid = checkCoords(getRobotSetupUI(m), uconvert.(Unitful.mm,pos), getMinMaxPosX(getRobot(m.scanner)))
  #end

  clear(m.protocolStatus)
  @info "Set protocol"
  protocol = setProtocol(m.scanner, "RobotBasedSystemMatrix")
  protocol.params.positions = positions
  protocol.params.bgFrames = numBGMeas
  @info "Init"
  m.biChannel = MPIMeasurements.init(protocol)
  @info "Execute"
  execute(m.scanner)
  return m.biChannel
end

function calibEventHandler(m::MeasurementWidget, timerCalibration::Timer)
  try
    channel = m.biChannel
    finished = false

    if isnothing(channel)
      return
    end

    if isready(channel)
      event = take!(channel)
      finished = handleCalibEvent(m, event, EventType(m, event))
    elseif !isopen(channel)
      finished = true
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

function handleCalibEvent(m::MeasurementWidget, event::IllegaleStateEvent, ::UnwantedEvent)
  @idle_add info_dialog(event.message, mpilab[]["mainWindow"])
  return true
end

function handleCalibEvent(m::MeasurementWidget, event::ExceptionEvent, ::UnwantedEvent)
  @error "Protocol error"
  stack = Base.catch_stack(m.scanner.currentProtocol.executeTask)[1]
  @error stack[1]
  @error stacktrace(stack[2])
  return true
end

function handleCalibEvent(m::MeasurementWidget, event::ProgressEvent, ::WantedEvent)
  channel = m.biChannel
  # New Progress noticed
  if isopen(channel)
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
    isopen(channel) && begin 
      put!(channel, progressQuery)
      m.protocolStatus.waitingOnReply = progressQuery
    end
  end
  return false
end

function handleCalibEvent(m::MeasurementWidget, event::ProtocolEvent, ::UnwantedEvent)
  @info "Discard event $(typeof(event))"
  return false
end

function handleCalibEvent(m::MeasurementWidget, event::DecisionEvent, ::UnwantedEvent)
  reply = ask_dialog(event.message, "No", "Yes", mpilab[]["mainWindow"])
  answerEvent = AnswerEvent(reply, event)
  put!(m.biChannel, answerEvent)
  return false
end

function handleCalibEvent(m::MeasurementWidget, event::FinishedNotificationEvent, ::UnwantedEvent)
  channel = m.biChannel
  # We noticed end and overwrite the query we are waiting for
  request = DatasetStoreStorageRequestEvent(m.mdfstore, getParams(m))
  put!(channel, request)
  m.protocolStatus.waitingOnReply = request
  return false
end

function handleCalibEvent(m::MeasurementWidget, event::StorageSuccessEvent, ::WantedEvent)
  channel = m.biChannel
  @info "Received storage success event"
  put!(channel, FinishedAckEvent())
  cleanup(m.scanner.currentProtocol)
  return true
end