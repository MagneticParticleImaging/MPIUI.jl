mutable struct TemperatureSensorWidget <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  updating::Bool
  sensor::TemperatureSensor
  temperatureLog::TemperatureLog
  canvases::Vector{Gtk4.GtkCanvasLeaf}
  timer::Union{Timer,Nothing}
end

getindex(m::TemperatureSensorWidget, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)

function TemperatureSensorWidget(sensor::TemperatureSensor)
  uifile = joinpath(@__DIR__,"..","builder","temperatureSensorWidget.ui")

  b = GtkBuilder(filename=uifile)
  mainBox = Gtk4.G_.get_object(b, "mainBox")

  numPlots = length(unique(getChannelGroups(sensor)))
  canvases = [GtkCanvas() for i=1:numPlots]

  m = TemperatureSensorWidget(mainBox.handle, b, false, sensor, TemperatureLog(), canvases, nothing)
  Gtk4.GLib.gobject_move_ref(m, mainBox)

  for (i,c) in enumerate(m.canvases)
    push!(m, c)
    show(c)
    c.hexpand = c.vexpand = true
  end

  show(m)

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
      filter = Gtk4.GtkFileFilter(pattern=String("*.toml"), mimetype=String("application/toml"))
      diag = save_dialog("Select Temperature File", mpilab[]["mainWindow"], (filter, )) do filename
        m.updating = true
        if filename != ""
            filenamebase, ext = splitext(filename)
            saveTemperatureLog(filenamebase*".toml", m.temperatureLog)
        end
        m.updating = false
      end
      diag.modal = true
  end  

  signal_connect(m["btnLoadTemp"], :clicked) do w
    filter = Gtk.GtkFileFilter(pattern=String("*.toml, *.mdf"), mimetype=String("application/toml"))
    diag = open_dialog("Select Temperature File", mpilab[]["mainWindow"], (filter, )) do filename
      m.updating = true
      if filename != ""
          filenamebase, ext = splitext(filename)
          m.temperatureLog = TemperatureLog(filename)
          @idle_add showData(m)
      end
      m.updating = false
    end
    diag.modal = true
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

      @idle_add showData(m)
    end
  end
end

@guarded function showData(m::TemperatureSensorWidget)
  showTemperatureData(m.canvases, m.temperatureLog, m.sensor)
end

@guarded function showTemperatureData(canvases, temperatureLog, sensor)
  #colors = ["blue", "red", "green", "yellow", "black", "cyan", "magenta"]
  lines = ["solid", "dashed", "dotted"]

  L = min(temperatureLog.numChan,length(colors) * length(lines))

  T = reshape(copy(temperatureLog.temperatures), temperatureLog.numChan,:)
  timesDT = copy(temperatureLog.times) 
  timesDT .-= timesDT[1]
  times = Dates.value.(timesDT) / 1000 # seconds

  if maximum(times) > 2*60*60*24
    times ./= 60*60*24
    strTime = "t / d"
  elseif maximum(times) > 2*60*60
    times ./= 60*60
    strTime = "t / h"
  elseif  maximum(times) > 2*60
    times ./= 60
    strTime = "t / min"
  else
    strTime = "t / s"
  end

  for (i,c) in enumerate(canvases)
    idx = findall(d->d==i, getChannelGroups(sensor))
    if length(idx) > 0

      f = CairoMakie.Figure(figure_padding=0)
      ax = CairoMakie.Axis(f[1, 1], alignmode = CairoMakie.Outside(),
          xlabel = strTime,
          ylabel = "T / °C"
      )
      
      legendEntries = []
      channelNames = []
      if hasmethod(getChannelNames, (typeof(sensor),))
        channelNames = getChannelNames(sensor)
      end
      for l=1:length(idx)
        CairoMakie.lines!(ax, times, T[idx[l],:], 
                      color = CairoMakie.RGBf(colors[mod1(l, length(colors))]...),
                      label = channelNames[idx[l]]) 
      end
      CairoMakie.axislegend()
      CairoMakie.autolimits!(ax)
      if times[end] > times[1]
        CairoMakie.xlims!(ax, times[1], times[end])
      end
      drawonto(c, f)
    end
  end
end


function startSensor(m::TemperatureSensorWidget)
  m.timer = Timer(timer -> updateSensor(timer, m), 0.0, interval=4)
end

function stopSensor(m::TemperatureSensorWidget)
  if m.timer != nothing
      close(m.timer)
      m.timer = nothing
  end
end