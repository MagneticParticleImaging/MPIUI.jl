mutable struct TemperatureLog
    temperatures::Vector{Float64}
    times::Vector{DateTime}
    numChan::Int64
end


function TemperatureLog(numChan::Int=1)
    TemperatureLog(Float64[], DateTime[], numChan)
end

function TemperatureLog(filename::String)
  filenamebase, ext = splitext(filename)
  if ext == ".toml"
    p = TOML.parsefile(filename)
    return TemperatureLog(p["temperatures"], p["times"], p["numChan"])
  elseif ext == ".mdf"
    temps = h5read(filename, "/measurement/_temperatures")
    times = [DateTime(0)+Dates.Second(1)*j for j=1:size(temps,2)]
    return TemperatureLog(vec(temps), times, size(temps,1))
  else
    error("File extension $(ext) not supported!")
  end
end

function clear(log::TemperatureLog, numChan=log.numChan)
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
  
mutable struct SurveillanceWidget <: Gtk.GtkBox
    handle::Ptr{Gtk.GObject}
    builder::GtkBuilder
    updating::Bool
    su::SurveillanceUnit
    temperatureLog::TemperatureLog
    canvas::GtkCanvasLeaf
    timer::Union{Timer,Nothing}
end
  
getindex(m::SurveillanceWidget, w::AbstractString) = G_.object(m.builder, w)

function SurveillanceWidget(su::SurveillanceUnit)
    uifile = joinpath(@__DIR__,"..","builder","surveillanceWidget.ui")

    b = Builder(filename=uifile)
    mainBox = G_.object(b, "mainBox")

    m = SurveillanceWidget(mainBox.handle, b, false, su, TemperatureLog(), Canvas(), nothing)
    Gtk.gobject_move_ref(m, mainBox)
  
    push!(m, m.canvas)
    set_gtk_property!(m,:expand, m.canvas, true)
  
    showall(m)
  
    tempInit = getTemperatures(su)
    L = length(tempInit)
  
    clear(m.temperatureLog, L)

    initCallbacks(m)

    return m
end
  
function initCallbacks(m::SurveillanceWidget)

    signal_connect(m["tbStartTemp"], :toggled) do w
        if get_gtk_property(m["tbStartTemp"], :active, Bool)
            startSurveillanceUnit(m)
        else
            stopSurveillanceUnit(m)
        end
    end

    signal_connect(m["btnResetTemp"], :clicked) do w
        m.updating = true
        sleep(1.0)
        clear(m.temperatureLog)
        m.updating = false
      end
    
    signal_connect(m["btnSaveTemp"], :clicked) do w
        m.updating = true
        filter = Gtk.GtkFileFilter(pattern=String("*.toml, *.mdf"), mimetype=String("application/toml"))
        filename = save_dialog("Select Temperature File", GtkNullContainer(), (filter, ))
        if filename != ""
            filenamebase, ext = splitext(filename)
            saveTemperatureLog(filenamebase*".toml", m.temperatureLog)
        end
        m.updating = false
    end  
end

  
function startSurveillanceUnit(m::SurveillanceWidget)
  
    @guarded function update_(timer::Timer)
      if !(m.updating) 
        te = ustrip.(getTemperatures(m.su))
        if sum(te) > 0.0
          time = Dates.now()
          str = join([ @sprintf("%.2f C ",t) for t in te ])
          set_gtk_property!(m["entTemperatures"], :text, str)
  
          push!(m.temperatureLog, te, time)
  
          L = min(m.temperatureLog.numChan,7)
  
          colors = ["b", "r", "g", "y", "k", "c", "m"]
  
          T = reshape(copy(m.temperatureLog.temperatures),m.temperatureLog.numChan,:)
  
          @idle_add_guarded begin
            p = Winston.plot(T[1,:], colors[1], linewidth=3)
            for l=2:L
              Winston.plot(p, T[l,:], colors[l], linewidth=3)
            end
            #Winston.xlabel("Time")
            display(m.canvas ,p)
            m.canvas.is_sized = true
          end
        end
      end
    end
    m.timer = Timer(update_, 0.0, interval=1.5)
end
  
function stopSurveillanceUnit(m::SurveillanceWidget)
    if m.timer != nothing
        close(m.timer)
        m.timer = nothing
    end
end