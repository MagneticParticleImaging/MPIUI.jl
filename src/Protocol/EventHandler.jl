function initProtocol(pw::ProtocolWidget)
  try 
    @info "Setting protocol parameters"
    for parameterObj in pw["boxProtocolParameter", BoxLeaf]
      setProtocolParameter(parameterObj, pw.protocol.params)
    end
    @info "Init protocol"
    MPIMeasurements.init(pw.protocol)
    for handler in pw.dataHandler
      init(handler, pw.protocol)
    end
    return true
  catch e
    @error e
    showError(e)
    return false
  end
end

function startProtocol(pw::ProtocolWidget)
  try 
    @info "Executing protocol"
    pw.biChannel = execute(pw.scanner, pw.protocol)
    pw.protocolState = PS_INIT
    @info "Starting event handler"
    pw.eventQueue = AbstractDataHandler[]
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

    if MPIMeasurements.isready(channel)
      event = take!(channel)
      @debug "GUI event handler received event of type $(typeof(event)) and is now dispatching it."
      finished = handleEvent(pw, pw.protocol, event)
      @debug "Handled event of type $(typeof(event))."
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
    pw.protocolState = PS_FAILED
    close(timer)
    @error ex
    showError(ex)
  end
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::UndefinedEvent)
  @warn "Protocol $(typeof(protocol)) send undefined event in response to $(typeof(event.event))"
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::ProtocolEvent)
  @warn "No handler defined for event $(typeof(event)) and protocol $(typeof(protocol))"
  return false
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::IllegaleStateEvent)
  @idle_add_guarded info_dialog(event.message, mpilab[]["mainWindow"])
  pw.protocolState = PS_FAILED
  return true
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::ExceptionEvent)
  currExceptions = current_exceptions(protocol.executeTask)
  @error "Protocol exception" exception = (currExceptions[end][:exception], stacktrace(currExceptions[end][:backtrace]))
  for i in 1:length(currExceptions) - 1
    stack = currExceptions[i]
    @error stack[:exception] trace = stacktrace(stack[:backtrace])
  end
  showError(currExceptions[end][:exception])
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
  @idle_add_guarded begin
    pw.updating = true
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :active, true)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :label, "Unpause")
    pw.updating = false
  end
end

function denyPauseProtocol(pw::ProtocolWidget)
  @idle_add_guarded begin
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
  @idle_add_guarded begin
    pw.updating = true
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :active, false)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :label, "Pause")
    pw.updating = false
  end
end

function denyResumeProtocol(pw::ProtocolWidget)
  @idle_add_guarded begin
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

function confirmFinishedProtocol(pw::ProtocolWidget)
  @idle_add_guarded begin
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

### Protocols and Data Handlers ###
defaultDataHandler(protocol::Protocol) = [RawDataHandler, SpectrogramHandler, OnlineRecoHandler]

function handleNewProgress(pw::ProtocolWidget, protocol::Protocol, event::ProgressEvent)
  if !informNewProgress(pw, protocol, event)
    progressQuery = ProgressQueryEvent()
    put!(pw.biChannel, progressQuery)  
  end
  return false
end
function informNewProgress(pw::ProtocolWidget, protocol::Protocol, event::ProgressEvent)
  querySent = false
  for handler in pw.dataHandler
    if isready(handler)
      query = handleProgress(handler, protocol, event)
      if !isnothing(query)
        querySent = true
        put!(pw.biChannel, query)
        push!(pw.eventQueue, handler)
      end
    end
  end
  return querySent
end

function handleFinished(pw::ProtocolWidget, protocol::Protocol)
  if !informFinished(pw, protocol)
    put!(pw.biChannel, FinishedAckEvent())
    return true
  end
  return false
end

function informFinished(pw::ProtocolWidget, protocol::Protocol)
  querySent = false
  for handler in pw.dataHandler
    query = handleFinished(handler, protocol)
    if !isnothing(query)
      querySent = true
      put!(pw.biChannel, query)
      push!(pw.eventQueue, handler)
    end
  end
  return querySent
end

function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::DataAnswerEvent)
  handler = popfirst!(pw.eventQueue)
  handleData(handler, protocol, event)
  channel = pw.biChannel
  if isempty(pw.eventQueue) && isopen(channel)
    if pw.protocolState == PS_RUNNING 
      put!(channel, ProgressQueryEvent())
    elseif pw.protocolState == PS_FINISHED
      put!(channel, FinishedAckEvent())
      return true
    end
  end
  return false
end


function handleEvent(pw::ProtocolWidget, protocol::Protocol, event::StorageSuccessEvent)
  handler = popfirst!(pw.eventQueue)
  handleStorage(handler, protocol, event)
  channel = pw.biChannel
  if isempty(pw.eventQueue) && isopen(channel)
    if pw.protocolState == PS_RUNNING 
      put!(channel, ProgressQueryEvent())
    elseif pw.protocolState == PS_FINISHED
      cleanup(protocol)
      put!(channel, FinishedAckEvent())
      return true
    end
  end
  return false
end