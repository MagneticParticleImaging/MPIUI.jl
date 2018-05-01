
type MeasurementWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder
  scanner
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
  sequences
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
    generalParams = getGeneralParams(scanner)
    mdfstore = MDFDatasetStore( generalParams["datasetStore"] )
  else
    scanner = nothing
    generalParams = nothing
    mdfstore = nothing #MDFDatasetStore( "/opt/data/MPS1" )
  end

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxMeasurement")

  m = MeasurementWidget( mainBox.handle, b,
                  scanner, generalParams, nothing, mdfstore, nothing,
                  nothing, nothing, false, false, false, RawDataWidget(), postMeasFunc, nothing)
  Gtk.gobject_move_ref(m, mainBox)

  println("Type constructed")

  println("InvalidateBG")
  invalidateBG(C_NULL, m)

  push!(m["boxMeasTabVisu"],m.rawDataWidget)
  setproperty!(m["boxMeasTabVisu"],:expand,m.rawDataWidget,true)

  Gtk.@sigatom setproperty!(m["lbInfo"],:use_markup,true)

  Gtk.@sigatom empty!(m["cbSeFo"])
  m.sequences = [ splitext(seq)[1] for seq in
            readdir(Pkg.dir("MPIMeasurements","src","Sequences"))]
  for seq in m.sequences
    Gtk.@sigatom push!(m["cbSeFo"], seq)
  end
  Gtk.@sigatom setproperty!(m["cbSeFo"],:active,0)

  if getDAQ(m.scanner) != nothing
    setInfoParams(m)
    setParams(m, merge!(m.generalParams,toDict(getDAQ(m.scanner).params)))
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

function infoMessage(m::MeasurementWidget, message::String)
  Gtk.@sigatom setproperty!(m["lbInfo"],:label,
      """<span foreground="green" font_weight="bold" size="x-large">$message</span>""")
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

  @time signal_connect(m["btnRobotMove"], :clicked) do w
    posString = getproperty(m["entCurrPos"], :text, String)
    pos_ = tryparse.(Float64,split(posString,"x"))

    if any(isnull.(pos_)) || length(pos_) != 3
      return
    end
    pos = get.(pos_).*1u"mm"
    moveAbs(getRobot(m.scanner),getSafety(m.scanner), pos)
    #infoMessage(m, "move to $posString")
  end

  timer = nothing
  timerActive = false
  @time signal_connect(m["tbContinous"], :toggled) do w
    daq = getDAQ(m.scanner)
    if getproperty(m["tbContinous"], :active, Bool)
      params = merge!(m.generalParams,getParams(m))
      MPIMeasurements.updateParams!(daq, params)
      startTx(daq)

      if daq.params.controlPhase
        MPIMeasurements.controlLoop(daq)
      else
        MPIMeasurements.setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                         zeros(numTxChannels(daq)))
      end

      timerActive = true

      function update_(::Timer)
        if timerActive
          uMeas, uRef = readData(daq, 1, MPIMeasurements.currentFrame(daq))
          #showDAQData(daq,vec(uMeas))
          amplitude, phase = MPIMeasurements.calcFieldFromRef(daq,uRef)
          #println("reference amplitude=$amplitude phase=$phase")
          Gtk.@sigatom updateData(m.rawDataWidget, uMeas, 1.0)
        else
          stopTx(daq)
          MPIMeasurements.disconnect(daq)
          close(timer)
        end
      end
      timer = Timer(update_, 0.0, 0.2)
    else
      timerActive = false
    end
  end


  timerCalibration = nothing
  timerCalibrationActive = false
  calibObj = nothing
  numPos = 0
  currPos = 0
  @time signal_connect(m["tbCalibration"], :toggled) do w
    daq = getDAQ(m.scanner)
    if getproperty(m["tbCalibration"], :active, Bool)
      if currPos == 0

        shpString = getproperty(m["entGridShape"], :text, String)
        shp_ = tryparse.(Int64,split(shpString,"x"))
        fovString = getproperty(m["entFOV"], :text, String)
        fov_ = tryparse.(Float64,split(fovString,"x"))
        centerString = getproperty(m["entCenter"], :text, String)
        center_ = tryparse.(Float64,split(centerString,"x"))

        numBGMeas = getproperty(m["adjNumBGMeasurements"], :value, Int64)

        if any(isnull.(shp_)) || any(isnull.(fov_)) || any(isnull.(center_)) ||
           length(shp_) != 3 || length(fov_) != 3 || length(center_) != 3
          Gtk.@sigatom setproperty!(m["tbCalibration"], :active, false)
          return
        end

        shp = get.(shp_)
        fov = get.(fov_) .*1u"mm"
        ctr = get.(center_) .*1u"mm"

        #positions = BreakpointGridPositions(
        #        MeanderingGridPositions( CartesianGridPositions(shp,fov,ctr) ),
        #        [1,11], [0.0,0.0,0.0]u"mm" )
        cartGrid = CartesianGridPositions(shp,fov,ctr)
        if numBGMeas == 0
          positions = cartGrid
        else
          bgIdx = round.(Int64, linspace(1, length(cartGrid)+numBGMeas, numBGMeas ) )
          positions = BreakpointGridPositions(cartGrid, bgIdx, [0.0,0.0,0.0]u"mm")
        end

        for pos in positions
          isValid = checkCoords(getSafety(m.scanner), pos)
        end

        params = merge!(m.generalParams,getParams(m))
        calibObj = SystemMatrixRobotMeas(m.scanner, positions, params)

        timerCalibrationActive = true
        currPos = 1
        numPos = length(positions)


        function update_(::Timer)
          println("Timer active $currPos / $numPos")
          if timerCalibrationActive
            if currPos <= numPos
              pos = Float64.(ustrip.(uconvert.(u"mm", positions[currPos])))
              posStr = @sprintf("%.2f x %.2f x %.2f", pos[1],pos[2],pos[3])
              Gtk.@sigatom setproperty!(m["lbInfo"],:label,
                    """<span foreground="green" font_weight="bold" size="x-large"> $currPos / $numPos ($posStr mm) </span>""")

              moveAbsUnsafe(getRobot(m.scanner), positions[currPos]) # comment for testing
              sleep(0.5)

              uMeas, uRef = postMoveAction(calibObj, positions[currPos], currPos)

              Gtk.@sigatom updateData(m.rawDataWidget, uMeas, 1.0)

              currPos +=1
            end
            if currPos > numPos
              stopTx(daq)
              MPIMeasurements.disconnect(daq)
              moveCenter(getRobot(m.scanner))
              close(timerCalibration)
              Gtk.@sigatom setproperty!(m["lbInfo"],:label, "")
              currPos = 0
              Gtk.@sigatom setproperty!(m["tbCalibration"], :active, false)

              calibNum = getNewCalibNum(m.mdfstore)
              saveasMDF("/tmp/tmp.mdf",
                        calibObj, params)
              saveasMDF(joinpath(calibdir(m.mdfstore),string(calibNum)*".mdf"),
                        MPIFile("/tmp/tmp.mdf"), applyCalibPostprocessing=true)
              updateData!(mpilab.sfBrowser, m.mdfstore)

            end
          else

          end
        end
        timerCalibration = Timer(update_, 0.0, 0.001)
      else
        timerCalibrationActive = true
      end
    else
      timerCalibrationActive = false
    end
  end


  @time signal_connect(invalidateBG, m["adjDFStrength"], "value_changed", Void, (), false, m)
  @time signal_connect(invalidateBG, m["adjNumPatches"], "value_changed", Void, (), false, m)
  @time signal_connect(invalidateBG, m["adjNumPeriods"], "value_changed", Void, (), false, m)

  #@time signal_connect(reinitDAQ, m["adjNumPeriods"], "value_changed", Void, (), false, m)
  @time signal_connect(m["cbSeFo"], :changed) do w
    seq = m.sequences[getproperty(m["cbSeFo"], :active, Int)+1]
    val = readcsv(Pkg.dir("MPIMeasurements","src","Sequences",
                                    seq*".csv"))
    Gtk.@sigatom setproperty!(m["adjNumPeriods"], :value, size(val,2))
  end

end

function invalidateBG(widgetptr::Ptr, m::MeasurementWidget)
  m.dataBGStore = nothing
  Gtk.@sigatom setproperty!(m["cbBGAvailable"],:active,false)
  Gtk.@sigatom setproperty!(m["lbInfo"],:label,
        """<span foreground="red" font_weight="bold" size="x-large"> No BG Measurement Available!</span>""")
  return nothing
end

function setInfoParams(m::MeasurementWidget)
  daq = getDAQ(m.scanner)
  if length(daq.params.dfFreq) > 1
    freqStr = "$(join([ " $(round(x,2)) x" for x in daq.params.dfFreq ])[2:end-2]) Hz"
  else
    freqStr = "$(round(daq.params.dfFreq[1],2)) Hz"
  end
  Gtk.@sigatom setproperty!(m["entDFFreq"],:text,freqStr)
  Gtk.@sigatom setproperty!(m["entDFPeriod"],:text,"$(daq.params.dfCycle*1000) ms")
  Gtk.@sigatom setproperty!(m["entFramePeriod"],:text,"$(daq.params.acqFramePeriod) s")
end


function measurement(widgetptr::Ptr, m::MeasurementWidget)
  Gtk.@sigatom  println("Calling measurement")

  params = merge!(m.generalParams,getParams(m))
  params["acqNumFrames"] = params["acqNumFGFrames"]

  m.filenameExperiment = MPIMeasurements.measurement(getDAQ(m.scanner), params, m.mdfstore,
                         bgdata=m.dataBGStore)

  Gtk.@sigatom updateData(m.rawDataWidget, m.filenameExperiment)

  Gtk.@sigatom m.postMeasFunc()
  return nothing
end

function measurementBG(widgetptr::Ptr, m::MeasurementWidget)
  Gtk.@sigatom println("Calling BG measurement")

  params = merge!(m.generalParams,getParams(m))
  params["acqNumFrames"] = params["acqNumBGFrames"]

  u = MPIMeasurements.measurement(getDAQ(m.scanner), params)
  m.dataBGStore = u
  #updateData(m, u)

  Gtk.@sigatom setproperty!(m["cbBGAvailable"],:active,true)
  Gtk.@sigatom setproperty!(m["lbInfo"],:label,"")
  return nothing
end


function getParams(m::MeasurementWidget)
  params = toDict(getDAQ(m.scanner).params)

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

  params["acqFFSequence"] = m.sequences[getproperty(m["cbSeFo"], :active, Int)+1]
  params["acqFFLinear"] = getproperty(m["cbFFInterpolation"], :active, Bool)


  #println(textSeFo)
  #=
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
  end=#
  #params["acqNumPeriodsPerFrame"]=length(params["acqFFValues"])

  return params
end

function setParams(m::MeasurementWidget, params)
  Gtk.@sigatom setproperty!(m["adjNumAverages"], :value, params["acqNumAverages"])
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

  if haskey(params,"acqFFSequence")
    idx = findfirst(m.sequences, params["acqFFSequence"])
    if idx > 0
      Gtk.@sigatom setproperty!(m["cbSeFo"], :active,idx-1)
    end
  else
      Gtk.@sigatom setproperty!(m["adjNumPeriods"], :value, params["acqNumPeriodsPerFrame"])
  end

  Gtk.@sigatom setproperty!(m["cbFFInterpolation"], :active, params["acqFFLinear"])

  p = getGeneralParams(m.scanner)
  if haskey(p, "calibGridShape") && haskey(p, "calibGridFOV") && haskey(p, "calibGridCenter") &&
     haskey(p, "calibNumBGMeasurements")
    shp = p["calibGridShape"]
    shpStr = @sprintf("%d x %d x %d", shp[1],shp[2],shp[3])
    fov = p["calibGridFOV"]
    fovStr = @sprintf("%.2f x %.2f x %.2f", fov[1],fov[2],fov[3])
    ctr = p["calibGridCenter"]
    ctrStr = @sprintf("%.2f x %.2f x %.2f", ctr[1],ctr[2],ctr[3])
    Gtk.@sigatom setproperty!(m["entGridShape"], :text, shpStr)
    Gtk.@sigatom setproperty!(m["entFOV"], :text, fovStr)
    Gtk.@sigatom setproperty!(m["entCenter"], :text, ctrStr)
    Gtk.@sigatom setproperty!(m["adjNumBGMeasurements"], :value, p["calibNumBGMeasurements"])
  end
  Gtk.@sigatom setproperty!(m["entCurrPos"], :text, "0.0 x 0.0 x 0.0")
end
