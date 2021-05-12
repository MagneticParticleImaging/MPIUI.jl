


function measurement(widgetptr::Ptr, m::MeasurementWidget)
  try
    @idle_add @info "Calling measurement"

    params = merge!(getGeneralParams(m.scanner),getParams(m))
    params["acqNumFrames"] = params["acqNumFGFrames"]

    bgdata = length(m.dataBGStore) == 0 ? nothing : m.dataBGStore

    # start measuremnt thread
    m.measState = asyncMeasurement(m.scanner, m.mdfstore, params, bgdata)

    # start display thread
    #g_timeout_add( ()->displayMeasurement(m), 1)
    #@tspawnat 1 displayMeasurement(m)

    timerMeas = Timer( timer -> displayMeasurement(m, timer), 0.0, interval=0.001)
  catch ex
    showError(ex)
  end
  return nothing
end



function displayMeasurement(m::MeasurementWidget, timerMeas::Timer)
  try
    measState = m.measState

    daq = getDAQ(m.scanner)
    deltaT = daq.params.dfCycle / daq.params.numSampPerPeriod

      if Base.istaskfailed(measState.task)
        @info "Task Failed"
        close(timerMeas)
        @async showError(measState.task.exception,measState.task.backtrace)
        return
      end
      #
      #@info "Frame $(measState.currFrame) / $(measState.numFrames)"
      fr = measState.currFrame
      if fr > 0 && !measState.consumed
        if get_gtk_property(m["cbOnlinePlotting",CheckButtonLeaf],:active, Bool)
          infoMessage(m, "Frame $(measState.currFrame) / $(measState.numFrames)", "green")
          updateData(m.rawDataWidget, measState.buffer[:,:,:,fr:fr], deltaT)
        end
        measState.consumed = true
      end
      if istaskdone(measState.task)
        close(timerMeas)
        infoMessage(m, "", "green")
        m.filenameExperiment = measState.filename
        updateData(m.rawDataWidget, m.filenameExperiment)
        updateExperimentStore(mpilab[], mpilab[].currentStudy)
      end
      #sleep(0.1)
    catch ex
      close(timerMeas)
      showError(ex)
    end
end


function measurementBG(widgetptr::Ptr, m::MeasurementWidget)
  try
    @idle_add @info "Calling BG measurement"
    params = merge!(getGeneralParams(m.scanner),getParams(m))
    params["acqNumFrames"] = params["acqNumBGFrames"]

    setEnabled(getRobot(m.scanner), false)
    enableACPower(getSurveillanceUnit(m.scanner), m.scanner)
    uMeas = MPIMeasurements.measurement(getDAQ(m.scanner), params)
    sleep(2)
    disableACPower(getSurveillanceUnit(m.scanner), m.scanner)
    setEnabled(getRobot(m.scanner), true)

    m.dataBGStore = uMeas
    #updateData(m, u)

    infoMessage(m, "", "green")
  catch ex
   showError(ex)
  end
  return nothing
end
