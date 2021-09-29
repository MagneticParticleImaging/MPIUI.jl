abstract type EventType end
struct UnwantedEvent <: EventType end
struct WantedEvent <: EventType end
EventType(m::MeasurementWidget, event::ProtocolEvent) = UnwantedEvent()
EventType(m::MeasurementWidget, event::ProgressEvent) = m.protocolStatus.waitingOnReply isa ProgressQueryEvent ? WantedEvent() : UnwantedEvent()
EventType(m::MeasurementWidget, event::DataAnswerEvent) = event.query == m.protocolStatus.waitingOnReply ? WantedEvent() : UnwantedEvent()
EventType(m::MeasurementWidget, event::StorageSuccessEvent) = m.protocolStatus.waitingOnReply isa StorageRequestEvent ? WantedEvent() : UnwantedEvent()

function measurement(widgetptr::Ptr, m::MeasurementWidget)
    try
      @idle_add @info "Calling measurement"

      params = getParams(m)
      acqNumFrames(m.protocol.params.sequence, params["acqNumFGFrames"])
      acqNumFrameAverages(m.protocol.params.sequence, params["acqNumFrameAverages"])
      
      protocol = setProtocol(m.scanner, "AsyncMeasurement")
      clear(m.protocolStatus)

      # Override protocol default sequence, not very nice solution but will vanish with protocol widget
      protocol.params.sequence = m.protocol.params.sequence 
      m.protocol = protocol
      m.biChannel = MPIMeasurements.init(protocol)
      execute(m.scanner)

      #bgdata = length(m.dataBGStore) == 0 ? nothing : m.dataBGStore

      timerMeas = Timer(timer -> displayMeasurement(m, timer), 0.0, interval=0.01)
  catch ex
    showError(ex)
  end
  return nothing
end



function displayMeasurement(m::MeasurementWidget, timerMeas::Timer)
  try
    channel = m.biChannel
    finished = false

    if isready(channel)
      event = take!(channel)
      finished = handleAsyncEvent(m, event, EventType(m, event))
    end

    if isnothing(m.protocolStatus.waitingOnReply)
      @info "Asking for first progress"
      progressQuery = ProgressQueryEvent()
      put!(channel, progressQuery)
      m.protocolStatus.waitingOnReply = progressQuery
    end

    if finished 
      close(timerMeas)
    end

  catch ex
    close(timerMeas)
    showError(ex)
  end
end

function handleAsyncEvent(m::MeasurementWidget, event::FinishedNotificationEvent, ::UnwantedEvent)
  channel = m.biChannel
  # We noticed end and overwrite the query we are waiting for
  @info "Received finish notification"
  bufferRequest = DataQueryEvent("BUFFER")
  put!(channel, bufferRequest)
  m.protocolStatus.waitingOnReply = bufferRequest
  return false
end

function handleAsyncEvent(m::MeasurementWidget, event::DataAnswerEvent, ::WantedEvent)
  channel = m.biChannel
  # We were waiting on the last buffer request
  if event.query.message == "BUFFER"
    @info "Finishing measurement"
    infoMessage(m, "", "green")    
    params = getParams(m)
    bgdata = length(m.dataBGStore) == 0 ? nothing : m.dataBGStore 
    buffer = event.data
    m.filenameExperiment = MPIFiles.saveasMDF(m.mdfstore, m.scanner, m.protocol.params.sequence, buffer, params; bgdata=bgdata)
    updateData(m.rawDataWidget, m.filenameExperiment)
    updateExperimentStore(mpilab[], mpilab[].currentStudy)
    put!(channel, FinishedAckEvent())
    return true
  # We were waiting on a new frame
  elseif startswith(event.query.message, "FRAME")
    @info "Received frame"
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

function handleAsyncEvent(m::MeasurementWidget, event::ProgressEvent, ::WantedEvent)
  channel = m.biChannel
  # New Progress noticed
  if isnothing(m.progress) || m.progress != event
    @info "New progress, asking for frame $(event.done)"
    m.progress = event
    dataQuery = DataQueryEvent("FRAME:$(event.done)")
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

function handleAsyncEvent(m::MeasurementWidget, event::ProtocolEvent, ::UnwantedEvent)
  @info "Discard event $(typeof(event))"
  return false
end



function measurementBG(widgetptr::Ptr, m::MeasurementWidget)
  try
    @idle_add @info "Calling BG measurement"

    # TODO add background paramter/triggers
    if !isnothing(m.measController)

      params = getParams(m)
      m.scanner.currentSequence.acquisition.numFrames = params["acqNumBGFrames"]
      m.scanner.currentSequence.acquisition.numFrameAverages = params["acqNumFrameAverages"]

      # Get Acquisition Protocol
      protocol = Protocol("MPIMeasurement", m.scanner)
      m.scanner.currentProtocol = protocol
      channel = MPIMeasurements.init(protocol)
      @tspawnat 1 execute(protocol)

      uMeas = nothing
      while isopen(channel) || isready(channel)
        while isready(channel)
          event = take!(channel)
          if event isa FinishedNotificationEvent
            query = DataQueryEvent("This string is not used atm")
            put!(channel, query)
            ackEvent = FinishedAckEvent()
            put!(channel, ackEvent)
          elseif event isa DataAnswerEvent
            @info "Received data answer"
            uMeas = event.data
          else
            @info "Unexpected event $event"
          end
        end
        sleep(0.01)
      end

      cleanup(protocol)

      #uMeas = MPIMeasurements.measurement(m.scanner)

      if !isnothing(uMeas)
        m.dataBGStore = uMeas
        # TODO comment out later
        updateData(m.rawDataWidget, uMeas)
      end
    end

    infoMessage(m, "", "green")
  catch ex
   showError(ex)
  end
  return nothing
end
