mutable struct TemperatureSensorWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  updating::Bool
  sensor::TemperatureSensor
  temperatureLog::TemperatureLog
  canvases::Vector{GtkCanvasLeaf}
  timer::Union{Timer,Nothing}
end

getindex(m::TemperatureSensorWidget, w::AbstractString) = G_.object(m.builder, w)

function TemperatureSensorWidget(sensor::TemperatureSensor)
  uifile = joinpath(@__DIR__,"..","builder","temperatureSensorWidget.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "mainBox")

  numPlots = length(unique(getChannelGroups(sensor)))
  canvases = [Canvas() for i=1:numPlots]

  m = TemperatureSensorWidget(mainBox.handle, b, false, sensor, TemperatureLog(), canvases, nothing)
  Gtk.gobject_move_ref(m, mainBox)

  for (i,c) in enumerate(m.canvases)
    push!(m, c)
    set_gtk_property!(m, :expand, c, true)
  end

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

      colors = ["blue", "red", "green", "yellow", "black", "cyan", "magenta"]
      lines = ["solid", "dashed", "dotted"]

      L = min(m.temperatureLog.numChan,length(colors) * length(lines))

      T = reshape(copy(m.temperatureLog.temperatures),m.temperatureLog.numChan,:)
      timesDT = copy(m.temperatureLog.times) #collect(1:size(T, 2))
      timesDT .-= timesDT[1]
      times = Dates.value.(timesDT) / 1000 # seconds
   
      if maximum(times) > 60*60
        times ./= 60*60
        strTime = "Time / Hours"
      elseif  maximum(times) > 60
        times ./= 60
        strTime = "Time / Minutes"
      else
        strTime = "Time / Seconds"
      end


      @idle_add begin
        try 
          for (i,c) in enumerate(m.canvases)
            idx = findall(d->d==i, getChannelGroups(m.sensor))
            if length(idx) > 0
              p = FramedPlot()
              Winston.plot(T[idx[1],:], colors[1], linewidth=3)


              Winston.setattr(p, "xlabel", strTime)
              Winston.setattr(p, "ylabel", "Temperature / C")

              legendEntries = []
              channelNames = []
              if hasmethod(getChannelNames, (typeof(m.sensor),))
                channelNames = getChannelNames(m.sensor)
              end
              for l=1:length(idx)
                curve = Curve(times, T[idx[l],:], color = colors[mod1(l, length(colors))], linekind=lines[div(l-1, length(colors)) + 1], linewidth=5)
                if !isempty(channelNames) 
                  setattr(curve, label = channelNames[idx[l]])
                  push!(legendEntries, curve)
                end
                add(p, curve)
              end
              # setattr(p, xlim=(-100, size(T, 2))) does not work. Idea was to shift the legend

              legend = Legend(.1, 0.9, legendEntries, halign="right") #size=1
              add(p, legend)
              display(c, p)
              showall(c)
              c.is_sized = true
            end
          end
        catch e
          @warn "Error"
          println(e)
        end
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