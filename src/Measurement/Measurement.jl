


function measurement(widgetptr::Ptr, m::MeasurementWidget)
    try
      @idle_add @info "Calling measurement"

      params = getParams(m)
      m.scanner.currentSequence.acquisition.numFrames = params["acqNumFGFrames"]
      m.scanner.currentSequence.acquisition.numFrameAverages = params["acqNumFrameAverages"]

      bgdata = length(m.dataBGStore) == 0 ? nothing : m.dataBGStore

      # start measuremnt thread
      asyncMeasurement(m.scanner)
        # m.measState = asyncMeasurement(m.scanner, params, bgdata, store = m.mdfstore)
    # start display thread
    # g_timeout_add( ()->displayMeasurement(m), 1)
    # @tspawnat 1 displayMeasurement(m)

    timerMeas = Timer(timer -> displayMeasurement(m, timer), 0.0, interval=0.001)
  catch ex
    showError(ex)
  end
  return nothing
end



function displayMeasurement(m::MeasurementWidget, timerMeas::Timer)
  try
    seq = m.scanner.currentSequence
    deltaT = dfCycle(seq) / rxNumSamplesPerPeriod(seq)

    if Base.istaskfailed(m.scanner.seqMeasState.producer)
      @info "Producer failed"
      close(m.scanner.seqMeasState.channel)
      close(timerMeas)
      stack = Base.catch_stack(m.scanner.seqMeasState.producer)[1]
      @error stack[1]
      @error stacktrace(stack[2])
        return
    end
    if Base.istaskfailed(m.scanner.seqMeasState.consumer)
      @info "Consumer failed"
      close(m.scanner.seqMeasState.channel)
      close(timerMeas)
      stack = Base.catch_stack(m.scanner.seqMeasState.consumer)[1]
      @error stack[1]
      @error stacktrace(stack[2])
        return
    end
    #
    # @info "Frame $(measState.currFrame) / $(measState.numFrames)"
    #fr = measController.measState.currFrame TODO implement live update
    fr = 0
    if fr > 0 
      #&& !measController.measState.consumed
      #infoMessage(m, "Frame $(measController.measState.currFrame) / $(measController.measState.numFrames)", "green")
      if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf], :active, Bool)
        updateData(m.rawDataWidget, m.scanner.seqMeasState.buffer[:,:,:,fr:fr], deltaT)
      end
      #measController.measState.consumed = true
    end
    if istaskdone(m.scanner.seqMeasState.consumer)
      close(timerMeas)
      infoMessage(m, "", "green")

      params = getParams(m)
      bgdata = length(m.dataBGStore) == 0 ? nothing : m.dataBGStore 

      m.filenameExperiment = MPIFiles.saveasMDF(m.mdfstore, m.scanner, 
                                  m.scanner.seqMeasState.buffer, params; bgdata=bgdata)

      updateData(m.rawDataWidget, m.filenameExperiment)
      updateExperimentStore(mpilab[], mpilab[].currentStudy)
    end
    # sleep(0.1)
  catch ex
    close(timerMeas)
    showError(ex)
  end
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
      channel = init(protocol) # Atm init sets protocol.sequence, but we want to overwrite it to the current sequence
      protocol.sequence = m.scanner.currentSequence
      @tspawnat m.scanner.generalParams.consumerThreadID execute(protocol)

      uMeas = nothing
      while isopen(channel) || isready(channel)
        while isready(channel)
          event = take!(channel)
          if event isa DecisionEvent
            @info "Received question from protocol"
            reply = ask_dialog(event.message, "No", "Yes", mpilab[]["mainWindow"])
            # We ask for result before we answer as the protocol blocks atm
            query = DataQueryEvent("This string is not used atm")
            put!(channel, query)
            answerEvent = AnswerEvent(reply, event)
            put!(channel, answerEvent)
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
