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
  println("Starting LCRMeterUI")
  uifile = joinpath(@__DIR__,"builder","lcrMeter.ui")

  b = Builder(filename=uifile)

  m = LCRMeterUI( b, nothing, nothing, nothing, nothing)

  m.c1 = Canvas()
  m.c2 = Canvas()

  push!(m["boxMain"],m.c1)
  set_gtk_property!(m["boxMain"],:expand,m.c1,true)
  push!(m["boxMain"],m.c2)
  set_gtk_property!(m["boxMain"],:expand,m.c2,true)

  @time signal_connect(m["btnSweep"], :clicked) do w
    sweepAndShow(m)
  end

  showall(m["mainWindow"])

  return m
end



function sweepAndShow(m::LCRMeterUI)
  minFreq = get_gtk_property(m["adjMinFreq"], :value, Float64)
  maxFreq = get_gtk_property(m["adjMaxFreq"], :value, Float64)
  numSamp = get_gtk_property(m["adjNumSamples"], :value, Int64)
  ip = get_gtk_property(m["entIP"], :text, String)

  freq = range(minFreq, stop=maxFreq, length=numSamp)

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
