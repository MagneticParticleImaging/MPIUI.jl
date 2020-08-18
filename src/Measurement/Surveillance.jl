

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

  append!(log.temperatures, temp)
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

const _tempTimer = Ref{Timer}()
const _updatingTimer = Ref{Bool}(false)

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

    signal_connect(m["btnResetTemp",ButtonLeaf], :clicked) do w
      _updatingTimer[] = true
      sleep(2.0)
      clear(m.temperatureLog, L)
      _updatingTimer[] = false
    end

    signal_connect(m["btnSaveTemp",ButtonLeaf], :clicked) do w
      _updatingTimer[] = true
      filter = Gtk.GtkFileFilter(pattern=String("*.toml"), mimetype=String("application/toml"))
      filename = save_dialog("Select Temperature File", GtkNullContainer(), (filter, ))
      if filename != ""
        filenamebase, ext = splitext(filename)
        saveTemperatureLog(filenamebase*".toml", m.temperatureLog)
      end
      _updatingTimer[] = false
    end    

    @guarded function update_(timer::Timer)

      if !(_updatingTimer[]) 
        te = getTemperatures(su)
        time = Dates.now()
        str = join([ @sprintf("%.2f C ",t) for t in te ])
        set_gtk_property!(m["entTemperatures",EntryLeaf], :text, str)

        push!(m.temperatureLog, te, time)

        L = min(L,7)

        colors = ["b", "r", "g", "y", "k", "c", "m"]

        T = reshape(copy(m.temperatureLog.temperatures),m.temperatureLog.numChan,:)

        @idle_add begin
          p = Winston.plot(T[1,:], colors[1], linewidth=10)
          for l=2:L
            Winston.plot(p, T[l,:], colors[l], linewidth=10)
          end
          #Winston.xlabel("Time")
          display(cTemp ,p)
        end
      end
    end
    _tempTimer[] = Timer(update_, 0.0, interval=1.5)
    m.expanded = true
  end
end
