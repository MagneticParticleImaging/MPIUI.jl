
mutable struct TemperatureLog
  temperatures::Vector{Float64}
  times::Vector{DateTime}
  numChan::Int64
end

function TemperatureLog(numChan::Int=1)
  TemperatureLog(Float64[], DateTime[], numChan)
end

function TemperatureLog(filename::String)
  p = TOML.parsefile(filename)
  return TemperatureLog(p["temperatures"], p["times"], p["numChan"])
end

function clear(log::TemperatureLog, numChan)
  log.temperatures = Float64[]
  log.times = DateTime[]
  log.numChan = numChan
end

function Base.push!(log::TemperatureLog, temp, t)
  if length(temp) != log.numChan
    error("Num Temperature sensors is not correct!")
  end

  push!(log.temperatures, temp)
  push!(log.times, t)
end




function saveTemperatureLog(filename::String, log::TemperatureLog)
  p = Dict{String,Any}()
  p["temperatures"] = log.temperatures
  p["times"] = log.times
  p["numChan"] = log.numChan

  open(filename, "w") do f
    TOML.print(f, p)
  end
end

function initSurveillance(m::MeasurementWidget)
  if !m.expanded
    su = getSurveillanceUnit(m.scanner)

    cTemp = Canvas()
    box = m["boxSurveillance",BoxLeaf]
    push!(box,cTemp)
    set_gtk_property!(box,:expand,cTemp,true)

    showall(box)

    tempInit = getTemperatures(su)
    L = length(tempInit)

    clear(m.temperatureLog, L)

    @guarded function update_(::Timer)
      begin
        te = getTemperatures(su)
        time = Dates.now()
        str = join([ @sprintf("%.2f C ",t) for t in te ])
        set_gtk_property!(m["entTemperatures",EntryLeaf], :text, str)

        push!(m.temperatureLog, te, time)

        #=if length(temp[1]) > 100
          for l=1:L
            temp[l] = temp[l][2:end]
          end
        end=#

        L = min(L,7)

        colors = ["b", "r", "g", "y", "k", "c", "m"]

        @idle_add begin
          p = Winston.plot(m.temperatureLog.temperatures[1,:], colors[1], linewidth=10)
          for l=2:L
            Winston.plot(p, m.temperatureLog.temperatures[l,:], colors[l], linewidth=10)
          end
          #Winston.ylabel("Harmonic $f")
          #Winston.xlabel("Time")
          display(cTemp ,p)
        end
      end
    end
    timer = Timer(update_, 0.0, interval=1.5)
    m.expanded = true
  end
end
