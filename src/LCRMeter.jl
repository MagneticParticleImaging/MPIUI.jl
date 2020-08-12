import Base: getindex

mutable struct LCRMeterUI
  builder
  data
  freq
  c1
  c2
end

getindex(m::LCRMeterUI, w::AbstractString) = G_.object(m.builder, w)

function LCRMeterUI()
  @info "Starting LCRMeterUI"
  uifile = joinpath(@__DIR__,"builder","lcrMeter.ui")

  b = Builder(filename=uifile)

  m = LCRMeterUI( b, nothing, nothing, nothing, nothing)

  m.c1 = Canvas()
  m.c2 = Canvas()

  push!(m["boxMain"],m.c1)
  set_gtk_property!(m["boxMain"],:expand,m.c1,true)
  push!(m["boxMain"],m.c2)
  set_gtk_property!(m["boxMain"],:expand,m.c2,true)

  choicesFunction = ["LsRs", "CsRs", "ZTD"]
  for c in choicesFunction
    push!(m["cbFunction"], c)
  end
  set_gtk_property!(m["cbFunction"],:active,0)

  signal_connect(m["btnSweep"], :clicked) do w
    @info "start sweep"
    sweepAndShow(m)
  end

  #signal_connect(m["btnSave"], :clicked) do w
  #  save(m)
  #end

  showall(m["mainWindow"])

  @info "Finished starting LCRMeterUI"
  return m
end



function setFunction(varFunc)
    if varFunc == 0
        measFunction="LSRS"
        ylab1="LS / H"
        ylab2="RS / Ohm"
    elseif varFunc == 1
        measFunction="CSRS"
        ylab1="CS / F"
        ylab2="RS / Ohm"
    elseif varFunc == 2
        measFunction="ZTD"
        ylab1="Z / Ohm"
        ylab2="Angle / deg"
    else
        @error "Wrong setting"
    end
    return measFunction, ylab1, ylab2
end

function sweepAndShow(m::LCRMeterUI)
  @info "start sweep function"

  minFreq = get_gtk_property(m["adjMinFreq"], :value, Float64)
  maxFreq = get_gtk_property(m["adjMaxFreq"], :value, Float64)
  numSamp = get_gtk_property(m["adjNumSamples"], :value, Int64)
  func = get_gtk_property(m["cbFunction"], :active, Int64)
  numAverages = get_gtk_property(m["adjNumAverages"], :value, Int64)
  voltage = get_gtk_property(m["adjVoltage"], :value, Float64)


  port = 5024
  global x_list = Float64[]
  global y_list = Float64[]

  measFunc, ylabel1, ylabel2 = setFunction(func)

  ip = get_gtk_property(m["entIP"], :text, String)
  #@info "params:" minFreq maxFreq numSamp measFunc numAverages voltage

  instr = connect(ip, port)

  #instr = connect("10.167.6.187", 5024)

  sleep(0.005)

  readline(instr)
  readline(instr)

  freqs = collect(range(minFreq, stop=maxFreq, length=numSamp))
  @info "Starting a frequency sweep from ", freqs[1] ," - ",freqs[end]
  write(instr, ":VOLTage:LEVel $voltage\r")
  sleep(0.005)
  @info "Voltage set to: " , voltage
  duration=numSamp*(numAverages*4*0.043+0.005)
  @info "Measurementtime will be abaut $(duration) seconds"
  readline(instr)

  write(instr, ":FUNCtion:IMPedance:TYPE $(measFunc)\r")
  sleep(0.005)
  readline(instr)
  for freq in freqs
    global x_samples = []
    global y_samples = []
    write(instr, ":FREQuency:CW $freq\r")
    sleep(0.005)
    readline(instr)
    for i=1:numAverages
        write(instr, ":TRIGger:IMMediate\r")
        sleep(0.005)
        readline(instr)
        global rawdata = write(instr, ":FETCh:IMPedance:FORMatted?\r")
        sleep(0.005)
        readline(instr)
        global rawdata = readline(instr)
        global n = split(rawdata, ',')
        global z_str = n[1]
        global  z = parse(Float64,z_str)
        global d_str = n[2]
        global d = parse(Float64,d_str)
        global x_samples=[x_samples;z]
        global y_samples = [y_samples;d]
        sleep(0.005)
    end

    global x_list = [x_list;mean(x_samples)]
    global y_list = [y_list;mean(y_samples)]

    sleep(0.005)
  end

  close(instr)


  freq=freqs
  data = x_list
  m.data = data
  m.freq = freq
  @info m.freq
  @info m.data


 p1 = Winston.plot(freq,x_list,"b-o", linewidth=2)
  Winston.ylabel(ylabel1)
  Winston.xlabel("f / kHz")

  p2 = Winston.plot(freq,y_list,"r-o", linewidth=2)
  Winston.ylabel(ylabel2)
  Winston.xlabel("f / kHz")

  #Winston.plot(p,freq,angle.(data),"k-x",
  #               linewidth=2, ylog=true)


  display(m.c1 ,p1)
  display(m.c2 ,p2)

end
