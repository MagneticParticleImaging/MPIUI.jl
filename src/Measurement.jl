
type MeasurementWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder
  daq
  generalParams
  dataBGStore
  mdfstore
  currStudyName
  currExpNum
  filenameExperiment
  updatingStudies
  updatingExperiments
  loadingData
  rawDataWidget
  postMeasFunc
end

getindex(m::MeasurementWidget, w::AbstractString) = G_.object(m.builder, w)

function isMeasurementStore(m::MeasurementWidget, d::DatasetStore)
  if m.mdfstore == nothing
    return false
  else
    return d.path == m.mdfstore.path
  end
end

function MeasurementWidget(postMeasFunc::Function = ()->nothing, filenameConfig="")
  println("Starting MeasurementWidget")
  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","measurementWidget.ui")

  #filenameConfig=nothing

  generalParams = nothing
  if filenameConfig != ""
    scanner = MPIScanner(filenameConfig)
    daq = getDAQ(scanner)
    generalParams = getGeneralParams(scanner)
    mdfstore = MDFDatasetStore( generalParams["datasetStore"] )
  else
    daq = nothing
    mdfstore = nothing #MDFDatasetStore( "/opt/data/MPS1" )
  end

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxMeasurement")

  m = MeasurementWidget( mainBox.handle, b,
                  daq, generalParams, nothing, mdfstore, nothing,
                  nothing, nothing, false, false, false, RawDataWidget(), postMeasFunc)
  Gtk.gobject_move_ref(m, mainBox)

  println("Type constructed")

  println("InvalidateBG")
  invalidateBG(C_NULL, m)

  push!(m["boxMeasTabVisu"],m.rawDataWidget)
  setproperty!(m["boxMeasTabVisu"],:expand,m.rawDataWidget,true)

  Gtk.@sigatom setproperty!(m["lbInfo"],:use_markup,true)


  if m.daq != nothing
    setInfoParams(m)
    setParams(m, merge!(m.generalParams,toDict(m.daq.params)))
    Gtk.@sigatom setproperty!(m["entConfig"],:text,filenameConfig)
  else
    Gtk.@sigatom setproperty!(m["tbMeasure"],:sensitive,false)
    Gtk.@sigatom setproperty!(m["tbMeasureBG"],:sensitive,false)
  end

  println("InitCallbacks")

  @time initCallbacks(m)

  println("Finished")


  return m
end



function initCallbacks(m::MeasurementWidget)

  #@time signal_connect(measurement, m["tbMeasure"], "clicked", Void, (), false, m )
  #@time signal_connect(measurementBG, m["tbMeasureBG"], "clicked", Void, (), false, m)

  @time signal_connect(m["tbMeasure"], :clicked) do w
    measurement(C_NULL, m)
  end

  @time signal_connect(m["tbMeasureBG"], :clicked) do w
    measurementBG(C_NULL, m)
  end

  timer = nothing
  timerActive = false
  @time signal_connect(m["tbContinous"], :toggled) do w
    daq = m.daq
    if getproperty(m["tbContinous"], :active, Bool)
      params = merge!(m.generalParams,getParams(m))
      MPIMeasurements.updateParams!(daq, params)
      startTx(daq)
      MPIMeasurements.controlLoop(daq)
      timerActive = true

      function update_(::Timer)
        if timerActive
          uMeas, uRef = readData(daq, 1, MPIMeasurements.currentFrame(daq))
          #showDAQData(daq,vec(uMeas))
          amplitude, phase = MPIMeasurements.calcFieldFromRef(daq,uRef)
          println("reference amplitude=$amplitude phase=$phase")
          updateData(m.rawDataWidget, uMeas, 1.0)
        end
      end
      timer = Timer(update_, 0.0, 0.2)
    else
      timerActive = false
      sleep(2.8)
      close(timer)
      sleep(0.2)
      stopTx(daq)
      MPIMeasurements.disconnect(daq)
    end
  end


  @time signal_connect(invalidateBG, m["adjDFStrength"], "value_changed", Void, (), false, m)
  @time signal_connect(invalidateBG, m["adjNumPatches"], "value_changed", Void, (), false, m)
  @time signal_connect(invalidateBG, m["adjNumPeriods"], "value_changed", Void, (), false, m)
  #@time signal_connect(reinitDAQ, m["adjNumPeriods"], "value_changed", Void, (), false, m)

end


function invalidateBG(widgetptr::Ptr, m::MeasurementWidget)
  m.dataBGStore = nothing
  Gtk.@sigatom setproperty!(m["cbBGAvailable"],:active,false)
  Gtk.@sigatom setproperty!(m["lbInfo"],:label,
        """<span foreground="red" font_weight="bold" size="x-large"> Warning: No BG Measurement Available!</span>""")
  return nothing
end

function setInfoParams(m::MeasurementWidget)

  if length(m.daq.params.dfFreq) > 1
    freqStr = "$(join([ " $(round(x,2)) x" for x in m.daq.params.dfFreq ])[2:end-2]) Hz"
  else
    freqStr = "$(round(m.daq.params.dfFreq[1],2)) Hz"
  end
  Gtk.@sigatom setproperty!(m["entDFFreq"],:text,freqStr)
  Gtk.@sigatom setproperty!(m["entDFPeriod"],:text,"$(m.daq.params.dfCycle*1000) ms")
  Gtk.@sigatom setproperty!(m["entFramePeriod"],:text,"$(m.daq.params.acqFramePeriod) s")
end


function measurement(widgetptr::Ptr, m::MeasurementWidget)
  Gtk.@sigatom  println("Calling measurement")

  params = merge!(m.generalParams,getParams(m))
  params["acqNumFrames"] = params["acqNumFGFrames"]

  m.filenameExperiment = MPIMeasurements.measurement(m.daq, params, m.mdfstore,
                        controlPhase=true, bgdata=m.dataBGStore)

  Gtk.@sigatom updateData(m.rawDataWidget, m.filenameExperiment)

  Gtk.@sigatom m.postMeasFunc()
  return nothing
end

function measurementBG(widgetptr::Ptr, m::MeasurementWidget)
  Gtk.@sigatom println("Calling BG measurement")

  params = merge!(m.generalParams,getParams(m))
  params["acqNumFrames"] = params["acqNumBGFrames"]

  u = MPIMeasurements.measurement(m.daq, params, controlPhase=true)
  m.dataBGStore = u
  #updateData(m, u)

  Gtk.@sigatom setproperty!(m["cbBGAvailable"],:active,true)
  Gtk.@sigatom setproperty!(m["lbInfo"],:label,"")
  return nothing
end


function getParams(m::MeasurementWidget)
  params = toDict(m.daq.params)

  params["acqNumAverages"] = getproperty(m["adjNumAverages"], :value, Int64)
  params["acqNumFGFrames"] = getproperty(m["adjNumFGFrames"], :value, Int64)
  params["acqNumBGFrames"] = getproperty(m["adjNumBGFrames"], :value, Int64)
  #params["acqNumPeriods"] = getproperty(m["adjNumPeriods"], :value, Int64)
  params["studyName"] = m.currStudyName
  params["studyDescription"] = ""
  params["experimentDescription"] = getproperty(m["entExpDescr"], :text, String)
  params["experimentName"] = getproperty(m["entExpName"], :text, String)
  params["scannerOperator"] = getproperty(m["entOperator"], :text, String)
  params["tracerName"] = [getproperty(m["entTracerName"], :text, String)]
  params["tracerBatch"] = [getproperty(m["entTracerBatch"], :text, String)]
  params["tracerVendor"] = [getproperty(m["entTracerVendor"], :text, String)]
  params["tracerVolume"] = [getproperty(m["adjTracerVolume"], :value, Float64)]
  params["tracerConcentration"] = [getproperty(m["adjTracerConcentration"], :value, Float64)]
  params["tracerSolute"] = [getproperty(m["entTracerSolute"], :text, String)]

  dfString = getproperty(m["entDFStrength"], :text, String)
  params["dfStrength"] = parse.(Float64,split(dfString," x "))*1e-3
  println("DF strength = $(params["dfStrength"])")

  textSeFo = getproperty(m["textBuffSeFo"],:text,String)
  println(textSeFo)
  try
    numPatches = getproperty(m["adjNumPatches"], :value, Int64)
    numPeriodsPerPatch = getproperty(m["adjNumPeriods"], :value, Int64)
    txt = "t = (0:($numPatches-1))./($numPatches);"  * textSeFo
    println(txt)
    code = parse(txt)
    println(code)
    currents = eval(code)
    #cat(1,x,reverse(x[2:end-1]))
    println(currents)

    params["acqFFValues"] = repeat(currents, inner=numPeriodsPerPatch)

  catch
    println("Could not parse text")
    params["acqFFValues"] = [0.0]
  end
  params["acqNumPeriodsPerFrame"]=length(params["acqFFValues"])

  return params
end

function setParams(m::MeasurementWidget, params)
  Gtk.@sigatom setproperty!(m["adjNumAverages"], :value, params["acqNumAverages"])
  Gtk.@sigatom setproperty!(m["adjNumPeriods"], :value, params["acqNumPeriodsPerFrame"])
  Gtk.@sigatom setproperty!(m["adjNumFGFrames"], :value, params["acqNumFrames"])
  Gtk.@sigatom setproperty!(m["adjNumBGFrames"], :value, params["acqNumFrames"])
  #Gtk.@sigatom setproperty!(m["entStudy"], :text, params["studyName"])
  Gtk.@sigatom setproperty!(m["entExpDescr"], :text, params["studyDescription"] )
  Gtk.@sigatom setproperty!(m["entOperator"], :text, params["scannerOperator"])
  dfString = *([ string(x*1e3," x ") for x in params["dfStrength"] ]...)[1:end-3]
  Gtk.@sigatom setproperty!(m["entDFStrength"], :text, dfString)

  Gtk.@sigatom setproperty!(m["entTracerName"], :text, params["tracerName"][1])
  Gtk.@sigatom setproperty!(m["entTracerBatch"], :text, params["tracerBatch"][1])
  Gtk.@sigatom setproperty!(m["entTracerVendor"], :text, params["tracerVendor"][1])
  Gtk.@sigatom setproperty!(m["adjTracerVolume"], :value, params["tracerVolume"][1])
  Gtk.@sigatom setproperty!(m["adjTracerConcentration"], :value, params["tracerConcentration"][1])
  Gtk.@sigatom setproperty!(m["entTracerSolute"], :text, params["tracerSolute"][1])
end
