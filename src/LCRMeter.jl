import Base: getindex

type LCRMeterUI
  builder
  data
  freq
  c1
  c2
end

getindex(m::LCRMeterUI, w::AbstractString) = G_.object(m.builder, w)

function LCRMeterUI()
  println("Starting LCRMeterUI")
  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","lcrMeter.ui")

  b = Builder(filename=uifile)

  m = LCRMeterUI( b, nothing, nothing, nothing, nothing)

  m.c1 = Canvas()
  m.c2 = Canvas()

  push!(m["boxMain"],m.c1)
  setproperty!(m["boxMain"],:expand,m.c1,true)
  push!(m["boxMain"],m.c2)
  setproperty!(m["boxMain"],:expand,m.c2,true)

  @time signal_connect(m["btnSweep"], :clicked) do w
    sweepAndShow(m)
  end

  showall(m["mainWindow"])

  return m
end



function sweepAndShow(m::LCRMeterUI)
  minFreq = getproperty(m["adjMinFreq"], :value, Float64)
  maxFreq = getproperty(m["adjMaxFreq"], :value, Float64)
  numSamp = getproperty(m["adjNumSamples"], :value, Int64)
  ip = getproperty(m["entIP"], :text, String)

  freq = linspace(minFreq,maxFreq,numSamp)

  data = rand(numSamp)+im*rand(numSamp) #TODO

  p1 = Winston.semilogy(freq,abs.(data),"b-o", linewidth=5)
  Winston.ylabel("?? / DB")
  Winston.xlabel("f / kHz")

  p2 = Winston.plot(freq,angle.(data),"r-o", linewidth=5)
  Winston.ylabel("phase / rad")
  Winston.xlabel("f / kHz")

  #Winston.plot(p,freq,angle.(data),"k-x",
  #               linewidth=2, ylog=true)


  display(m.c1 ,p1)
  display(m.c2 ,p2)

end