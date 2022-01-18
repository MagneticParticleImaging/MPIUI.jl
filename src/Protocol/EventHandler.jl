function initProtocol(pw::ProtocolWidget)
  try 
    @info "Setting protocol parameters"
    for parameterObj in pw["boxProtocolParameter", BoxLeaf]
      setProtocolParameter(parameterObj, pw.protocol.params)
    end
    @info "Init protocol"
    MPIMeasurements.init(pw.protocol)
    return true
  catch e
    @error e
    showError(e)
    return false
  end
end

function startProtocol(pw::ProtocolWidget)
  try 
    @info "Execute protocol"
    pw.biChannel = execute(pw.scanner, pw.protocol)
    pw.protocolState = PS_INIT
    @info "Start event handler"
    pw.eventHandler = Timer(timer -> eventHandler(pw, timer), 0.0, interval=0.05)
    return true
  catch e
    @error e
    showError(e)
    return false
  end
end

function endProtocol(pw::ProtocolWidget)
  if isopen(pw.biChannel)
    put!(pw.biChannel, FinishedAckEvent())
  end
  if isopen(pw.eventHandler)
    close(pw.eventHandler)
  end
  confirmFinishedProtocol(pw)
end

function eventHandler(pw::ProtocolWidget, timer::Timer)
  try
    channel = pw.biChannel
    finished = false

    if isnothing(channel)
      return
    end

    if isready(channel)
      event = take!(channel)
      finished = handleEvent(pw, pw.protocol, event)
    elseif !isopen(channel)
      finished = true
    end

    if pw.protocolState == PS_INIT && !finished
      @info "Init query"
      progressQuery = ProgressQueryEvent()
      put!(channel, progressQuery)
      pw.protocolState = PS_RUNNING
    end

    if finished
      @info "Finished event handler"
      confirmFinishedProtocol(pw)
      close(timer)
    end

  catch ex
    confirmFinishedProtocol(pw)
    close(timer)
    showError(ex)
  end
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::ProtocolEvent)
  @warn "No handler defined for event $(typeof(event)) and protocol $(typeof(protocol))"
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::IllegaleStateEvent)
  @idle_add info_dialog(event.message, mpilab[]["mainWindow"])
  pw.protocolState = PS_FAILED
  return true
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::ExceptionEvent)
  @error "Protocol exception"
  stack = Base.catch_stack(protocol.executeTask)[1]
  @error stack[1]
  @error stacktrace(stack[2])
  showError(stack[1])
  pw.protocolState = PS_FAILED
  return true
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::ProgressEvent)
  channel = pw.biChannel
  # New Progress noticed
  if isopen(channel) && pw.protocolState == PS_RUNNING
    if isnothing(pw.progress) || pw.progress != event
      @info "New progress detected"
      handleNewProgress(pw, protocol, event)
      pw.progress = event
      displayProgress(pw)
    else
      # Ask for next progress
      sleep(0.01)
      progressQuery = ProgressQueryEvent()
      put!(channel, progressQuery)
      #m.protocolStatus.waitingOnReply = progressQuery
    end
  end
  return false
end

function handleNewProgress(pw::ProtocolWidget, protocol::Protocol, event::ProgressEvent)
  progressQuery = ProgressQueryEvent()
  put!(pw.biChannel, progressQuery)
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::DecisionEvent)
  reply = ask_dialog(event.message, "No", "Yes", mpilab[]["mainWindow"])
  answerEvent = AnswerEvent(reply, event)
  put!(pw.biChannel, answerEvent)
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::MultipleChoiceEvent)
  buttons = [(choice, i) for (i, choice) in enumerate(event.choices)]
  parent = mpilab[]["mainWindow"]
  widget = GtkMessageDialog(event.message, buttons, GtkDialogFlags.DESTROY_WITH_PARENT, GtkMessageType.INFO, parent)
  showall(widget)
  reply = run(widget)
  destroy(widget)
  @show reply
  put!(pw.biChannel, ChoiceAnswerEvent(reply, event))
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::OperationSuccessfulEvent)
  return handleSuccessfulOperation(pw, protocol, event.operation)
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::OperationNotSupportedEvent)
  return handleUnsupportedOperation(pw, protocol, event.operation)
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::OperationUnsuccessfulEvent)
  return handleUnsuccessfulOperation(pw, protocol, event.operation)
end

### Pausing/Stopping Default ###
function tryPauseProtocol(pw::ProtocolWidget)
  put!(pw.biChannel, StopEvent())
end

function handleSuccessfulOperation(pw::ProtocolWidget, protocol::Protocol, event::StopEvent)
  @info "Protocol stopped"
  pw.protocolState = PS_PAUSED
  confirmPauseProtocol(pw)
  return false
end

function handleUnsupportedOperation(pw::ProtocolWidget, protocol::Protocol, event::StopEvent)
  @info "Protocol can not be stopped"
  denyPauseProtocol(pw)
  return false
end

function handleUnsuccessfulOperation(pw::ProtocolWidget, protocol::Protocol, event::StopEvent)
  @info "Protocol failed to be stopped"
  denyPauseProtocol(pw)
  return false
end

function confirmPauseProtocol(pw::ProtocolWidget)
  @idle_add begin
    pw.updating = true
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :active, true)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :label, "Unpause")
    pw.updating = false
  end
end

function denyPauseProtocol(pw::ProtocolWidget)
  @idle_add begin
    pw.updating = true
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :active, false)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
    pw.updating = false
  end
end

### Resume/Unpause Default ###
function tryResumeProtocol(pw::ProtocolWidget)
  put!(pw.biChannel, ResumeEvent())
end

function handleSuccessfulOperation(pw::ProtocolWidget, protocol::Protocol, event::ResumeEvent)
  @info "Protocol resumed"
  pw.protocolState = PS_RUNNING
  confirmResumeProtocol(pw)
  put!(pw.biChannel, ProgressQueryEvent()) # Restart "Main" loop
  return false
end

function handleUnsupportedOperation(pw::ProtocolWidget, protocol::Protocol, event::ResumeEvent)
  @info "Protocol can not be resumed"
  denyResumeProtocol(pw)
  return false
end

function handleUnsuccessfulOperation(pw::ProtocolWidget, protocol::Protocol, event::ResumeEvent)
  @info "Protocol failed to be resumed"
  denyResumeProtocol(pw)
  return false
end

function confirmResumeProtocol(pw::ProtocolWidget)
  @idle_add begin
    pw.updating = true
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :active, false)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :label, "Pause")
    pw.updating = false
  end
end

function denyResumeProtocol(pw::ProtocolWidget)
  @idle_add begin
    pw.updating = true
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :active, true)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
    pw.updating = false
  end
end

### Cancel Default ###
function tryCancelProtocol(pw::ProtocolWidget)
  put!(pw.biChannel, CancelEvent())
end

function handleSuccessfulOperation(pw::ProtocolWidget, protocol::Protocol, event::CancelEvent)
  @info "Protocol cancelled"
  pw.protocolState = PS_FAILED
  return true
end

function handleUnsupportedOperation(pw::ProtocolWidget, protocol::Protocol, event::CancelEvent)
  @warn "Protocol can not be cancelled"
  return false
end

function handleUnsuccessfulOperation(pw::ProtocolWidget, protocol::Protocol, event::CancelEvent)
  @warn "Protocol failed to be cancelled"
  return false
end

### Finish Default ###
function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::FinishedNotificationEvent)
  pw.protocolState = PS_FINISHED
  displayProgress(pw)
  return handleFinished(pw, protocol)
end

function handleFinished(pw::ProtocolWidget, protocol::Protocol)
  put!(pw.biChannel, FinishedAckEvent())
  return true
end

function confirmFinishedProtocol(pw::ProtocolWidget)
  @idle_add begin
    pw.updating = true
    # Sensitive
    set_gtk_property!(pw["tbInit",ToolButtonLeaf], :sensitive, true)
    if pw.protocolState != PS_FAILED
      set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :sensitive, true)
    end
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, false)
    set_gtk_property!(pw["tbCancel",ToolButtonLeaf], :sensitive, false)
    set_gtk_property!(pw["btnPickProtocol", ButtonLeaf], :sensitive, true)
    # Active
    set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :active, false)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :active, false)
    # Text
    set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :label, "Execute")
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :label, "Pause")
    pw.updating = false
  end
end

### RobotBasedSystemMatrixProtocol ###
function handleNewProgress(pw::ProtocolWidget, protocol::RobotBasedSystemMatrixProtocol, event::ProgressEvent)
  dataQuery = DataQueryEvent("SIGNAL")
  put!(pw.biChannel, dataQuery)
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::RobotBasedSystemMatrixProtocol, event::DataAnswerEvent)
  channel = pw.biChannel
  if event.query.message == "SIGNAL"
    @info "Received current signal"
    frame = event.data
    if !isnothing(frame)
      #if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf], :active, Bool)
        seq = pw.protocol.params.sequence
        deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
        updateData(pw.rawDataWidget, frame, deltaT)
      #end
    end
    # Ask for next progress
    progressQuery = ProgressQueryEvent()
    isopen(channel) && pw.protocolState == PS_RUNNING && put!(channel, progressQuery)
  end
  return false
end

function handleFinished(pw::ProtocolWidget, protocol::RobotBasedSystemMatrixProtocol)
  request = DatasetStoreStorageRequestEvent(pw.mdfstore, getStorageParams(pw))
  put!(pw.biChannel, request)
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::RobotBasedSystemMatrixProtocol, event::StorageSuccessEvent)
  @info "Received storage success event"
  put!(pw.biChannel, FinishedAckEvent())
  updateData!(mpilab[].sfBrowser, pw.mdfstore)
  updateExperimentStore(mpilab[], mpilab[].currentStudy)
  cleanup(protocol)
  return true
end


### MPIMeasurementProtocol ###
function handleNewProgress(pw::ProtocolWidget, protocol::MPIMeasurementProtocol, event::ProgressEvent)
  @info "Asking for new frame $(event.done)"
  dataQuery = DataQueryEvent("FRAME:$(event.done)")
  put!(pw.biChannel, dataQuery)
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::MPIMeasurementProtocol, event::DataAnswerEvent)
  channel = pw.biChannel
  # We were waiting on the last buffer request
  if startswith(event.query.message, "FRAME") && pw.protocolState == PS_RUNNING
    frame = event.data
    if !isnothing(frame)
      @info "Received frame"
      #infoMessage(m, "$(m.progress.unit) $(m.progress.done) / $(m.progress.total)", "green")
      #if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf], :active, Bool)
      seq = pw.protocol.params.sequence
      deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
      updateData(pw.rawDataWidget, frame, deltaT)
      #end
    end
    # Ask for next progress
    progressQuery = ProgressQueryEvent()
    put!(channel, progressQuery)
  end
  return false
end

function handleFinished(pw::ProtocolWidget, protocol::MPIMeasurementProtocol)
  request = DatasetStoreStorageRequestEvent(pw.mdfstore, getStorageParams(pw))
  put!(pw.biChannel, request)
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::MPIMeasurementProtocol, event::StorageSuccessEvent)
  @info "Received storage success event"
  put!(pw.biChannel, FinishedAckEvent())
  updateData(pw.rawDataWidget, event.filename)
  updateExperimentStore(mpilab[], mpilab[].currentStudy)
  return true
end

### ContinousMeasurementProtocol ###
function handleNewProgress(pw::ProtocolWidget, protocol::ContinousMeasurementProtocol, event::ProgressEvent)
  @info "Asking for new measurement $(event.done)"
  dataQuery = DataQueryEvent("")
  put!(pw.biChannel, dataQuery)
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::ContinousMeasurementProtocol, event::DataAnswerEvent)
  channel = pw.biChannel
  meas = event.data
  if !isnothing(meas)
    seq = pw.protocol.params.sequence
    deltaT = ustrip(u"s", dfCycle(seq) / rxNumSamplesPerPeriod(seq))
    updateData(pw.rawDataWidget, meas, deltaT)
  end
  progressQuery = ProgressQueryEvent()
  put!(channel, progressQuery)
  return false
end