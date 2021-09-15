


function measurement(widgetptr::Ptr, m::MeasurementWidget)
    try
      @idle_add @info "Calling measurement"

        #params = merge!(getGeneralParams(m.scanner), getParams(m))
        #params["acqNumFrames"] = params["acqNumFGFrames"]

      bgdata = length(m.dataBGStore) == 0 ? nothing : m.dataBGStore

      # start measuremnt thread
      if !isnothing(m.measController)
       asyncMeasurement(m.measController, m.scanner.currentSequence)
        # m.measState = asyncMeasurement(m.scanner, params, bgdata, store = m.mdfstore)
      end
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
    measController = m.measController

    seq = m.scanner.currentSequence
    deltaT = dfCycle(seq) / rxNumSamplesPerPeriod(seq)

    if Base.istaskfailed(measController.producer)
      @info "Producer failed"
      close(measController.state.channel)
      close(timerMeas)
      stack = Base.catch_stack(measController.producer)[1]
      @error stack[1]
      @error stacktrace(stack[2])
        return
    end
    if Base.istaskfailed(measController.consumer)
      @info "Consumer failed"
      close(measController.measState.channel)
      close(timerMeas)
      stack = Base.catch_stack(measController.consumer)[1]
      @error stack[1]
      @error stacktrace(stack[2])
        return
    end
    #
    # @info "Frame $(measState.currFrame) / $(measState.numFrames)"
    fr = measController.measState.currFrame
    if fr > 0 && !measController.measState.consumed
      infoMessage(m, "Frame $(measController.measState.currFrame) / $(measController.measState.numFrames)", "green")
      if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf], :active, Bool)
        updateData(m.rawDataWidget, measController.measState.buffer[:,:,:,fr:fr], deltaT)
      end
      measController.measState.consumed = true
    end
    if istaskdone(measController.consumer)
      close(timerMeas)
      infoMessage(m, "", "green")
      # TODO update storage
      #m.filenameExperiment = measController.filename
      updateData(m.rawDataWidget, m.filenameExperiment)
      #updateExperimentStore(mpilab[], mpilab[].currentStudy)
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
      uMeas = MPIMeasurements.measurement(m.measController, m.scanner.currentSequence)

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
