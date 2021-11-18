mutable struct TemperatureSensorWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  updating::Bool
  sensor::TemperatureSensor
  temperatureLog::TemperatureLog
  canvas::GtkCanvasLeaf
  timer::Union{Timer,Nothing}
end

getindex(m::TemperatureSensorWidget, w::AbstractString) = G_.object(m.builder, w)

function TemperatureSensorWidget(sensor::TemperatureSensor)
  uifile = joinpath(@__DIR__,"..","builder","temperatureSensorWidget.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "mainBox")

  m = TemperatureSensorWidget(mainBox.handle, b, false, sensor, TemperatureLog(), Canvas(), nothing)
  Gtk.gobject_move_ref(m, mainBox)

  push!(m, m.canvas)
  set_gtk_property!(m,:expand, m.canvas, true)

  showall(m)

  tempInit = getTemperatures(sensor)
  L = length(tempInit)

  clear(m.temperatureLog, L)

  initCallbacks(m)

  return m
end

function initCallbacks(m::TemperatureSensorWidget)

  signal_connect(m["tbStartTemp"], :toggled) do w
      if get_gtk_property(m["tbStartTemp"], :active, Bool)
          startSensor(m)
      else
          stopSensor(m)
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
      filter = Gtk.GtkFileFilter(pattern=String("*.toml"), mimetype=String("application/toml"))
      filename = save_dialog("Select Temperature File", GtkNullContainer(), (filter, ))
      if filename != ""
          filenamebase, ext = splitext(filename)
          saveTemperatureLog(filenamebase*".toml", m.temperatureLog)
      end
      m.updating = false
  end  
end


@guarded function updateSensor(timer::Timer, m::TemperatureSensorWidget)
  if !(m.updating) 
    te = ustrip.(getTemperatures(m.sensor))
    if sum(te) > 0.0
      time = Dates.now()
      str = join([ @sprintf("%.2f C ",t) for t in te ])
      set_gtk_property!(m["entTemperatures"], :text, str)

      push!(m.temperatureLog, te, time)

      L = min(m.temperatureLog.numChan,7)

      colors = ["b", "r", "g", "y", "k", "c", "m"]

      T = reshape(copy(m.temperatureLog.temperatures),m.temperatureLog.numChan,:)

      @idle_add begin
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

function startSensor(m::TemperatureSensorWidget)
  m.timer = Timer(timer -> updateSensor(timer, m), 0.0, interval=1.5)
end

function stopSensor(m::TemperatureSensorWidget)
  if m.timer != nothing
      close(m.timer)
      m.timer = nothing
  end
end