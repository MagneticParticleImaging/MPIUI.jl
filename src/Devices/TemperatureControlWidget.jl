mutable struct TemperatureControllerWidget <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  updating::Bool
  cont::TemperatureController
  temperatureLog::TemperatureLog
  canvases::Vector{Gtk4.GtkCanvasLeaf}
  timer::Union{Timer,Nothing}
end

getindex(m::TemperatureControllerWidget, w::AbstractString) =  G_.get_object(m.builder, w)

function TemperatureControllerWidget(tempCont::TemperatureController)
  uifile = joinpath(@__DIR__,"..","builder","temperatureControllerWidget.ui")

  b = GtkBuilder(filename=uifile)
  mainBox = G_.get_object(b, "mainBox")

  numPlots = length(unique(getChannelGroups(tempCont)))
  canvases = [GtkCanvas() for i=1:numPlots]

  m = TemperatureControllerWidget(mainBox.handle, b, false, tempCont, TemperatureLog(), canvases, nothing)
  Gtk4.GLib.gobject_move_ref(m, mainBox)

  for (i,c) in enumerate(m.canvases)
    push!(m, c)
    ### set_gtk_property!(m, :expand, c, true)
  end


  #push!(m, m.canvas)
  #set_gtk_property!(m,:expand, m.canvas, true)

  showall(m)

  updateTarget(m)
  updateMaximum(m)

  tempInit = getTemperatures(tempCont)
  L = length(tempInit)

  clear(m.temperatureLog, L)

  initCallbacks(m)

  return m
end

function initCallbacks(m::TemperatureControllerWidget)

  signal_connect(m["btnEnable"], :clicked) do w
    if ask_dialog("Confirm that you want to enable temperature control", "Cancel", "Confirm", mpilab[]["mainWindow"])
      enableControl(m.cont)
    end
  end

  signal_connect(m["btnDisable"], :clicked) do w
    if ask_dialog("Confirm that you want to disable temperature control", "Cancel", "Confirm", mpilab[]["mainWindow"])
      disableControl(m.cont)
    end
  end

  signal_connect(m["btnGetTarget"], :clicked) do w
    updateTarget(m)
  end
  
  signal_connect(m["btnSetTarget"], :clicked) do w
    if ask_dialog("Confirm that you want to set new target temperatures", "Cancel", "Confirm", mpilab[]["mainWindow"])
      setTarget(m)
    end
  end
  
  signal_connect(m["btnGetMaximum"], :clicked) do w
    updateMaximum(m)
  end
  
  signal_connect(m["btnSetMaximum"], :clicked) do w
    if ask_dialog("Confirm that you want to set new maximum temperatures", "Cancel", "Confirm", mpilab[]["mainWindow"])
      setMaximum(m)
    end
  end

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
    filter = Gtk4.GtkFileFilter(pattern=String("*.toml, *.mdf"), mimetype=String("application/toml"))
    diag = open_dialog("Select Temperature File", mpilab[]["mainWindow"], (filter, )) do filename
      m.updating = true
      if filename != ""
        filenamebase, ext = splitext(filename)
        m.temperatureLog = TemperatureLog(filename)
        @idle_add showData(m)
      end
      m.updating = false  #
    end
    diag.modal = true
  end  


end

function updateTarget(m::TemperatureControllerWidget)
  @idle_add_guarded begin
    entryString = join(getTargetTemps(m.cont), ", ")
    set_gtk_property!(m["entGetTarget"], :text, entryString)
  end
end

function setTarget(m::TemperatureControllerWidget)
  @idle_add_guarded begin
    entry = get_gtk_property(m["entSetTarget"], :text, String)
    result = tryparse.(Int64,split(entry,","))
    ack = setTargetTemps(m.cont, result)
    if !ack
      d = info_dialog(()-> nothing, "Could not set new target temps")
      d.modal = true
    end
  end
end

function updateMaximum(m::TemperatureControllerWidget)
  @idle_add_guarded begin
    entryString = join(getMaximumTemps(m.cont), ", ")
    set_gtk_property!(m["entGetMaximum"], :text, entryString)
  end
end

function setMaximum(m::TemperatureControllerWidget)
  @idle_add_guarded begin
    entry = get_gtk_property(m["entSetMaximum"], :text, String)
    result = tryparse.(Int64,split(entry,","))
    ack = setMaximumTemps(m.cont, result)
    if !ack
      d = info_dialog(()-> nothing, "Could not set new target temps")
      d.modal = true
    end
  end
end



@guarded function updateSensor(timer::Timer, m::TemperatureControllerWidget)
  if !(m.updating) 
    te = ustrip.(getTemperatures(m.cont))
    if sum(te) > -1
      time = Dates.now()
      str = join([ @sprintf("%.2f C ",t) for t in te ])
      set_gtk_property!(m["entTemperatures"], :text, str)

      push!(m.temperatureLog, te, time)

      @idle_add showData(m)
    end
  end
end

@guarded function showData(m::TemperatureControllerWidget)
  showTemperatureData(m.canvases, m.temperatureLog, m.cont) # implemented in TemperatureSensorWidget.jl
end

function startSensor(m::TemperatureControllerWidget)
  m.timer = Timer(timer -> updateSensor(timer, m), 0.0, interval=4)
end

function stopSensor(m::TemperatureControllerWidget)
  if m.timer != nothing
      close(m.timer)
      m.timer = nothing
  end
end