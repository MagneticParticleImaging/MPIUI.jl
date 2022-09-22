mutable struct TemperatureControllerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  updating::Bool
  cont::TemperatureController
  #temperatureLog::TemperatureLog
  #canvases::Vector{GtkCanvasLeaf}
  #timer::Union{Timer,Nothing}
end

getindex(m::TemperatureControllerWidget, w::AbstractString) =  G_.object(m.builder, w)

function TemperatureControllerWidget(tempCont::TemperatureControllerWidget)
  uifile = joinpath(@__DIR__,"..","builder","temperatureControllerWidget.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "mainBox")

  m = TemperatureControllerWidget(mainBox.handle, b, false, tempCont)
  Gtk.gobject_move_ref(m, mainBox)

  #push!(m, m.canvas)
  #set_gtk_property!(m,:expand, m.canvas, true)

  showall(m)

  #tempInit = getTemperatures(su)
  #L = length(tempInit)

  #clear(m.temperatureLog, L)

  initCallbacks(m)

  return m
end

function initCallbacks(m::SurveillanceWidget)

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
end