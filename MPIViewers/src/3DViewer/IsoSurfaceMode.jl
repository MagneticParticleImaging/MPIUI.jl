export IsoSurfaceMode


mutable struct IsoSurfaceMode{P} <: Abstract3DViewerMode
  pop::GtkPopover
  parent::P
  active::Bool
  isoAdj::GtkAdjustment
  isoMin::GtkLabel
  isoMax::GtkLabel
  isorange::GtkEntry
end
function IsoSurfaceMode(parent::P) where P  
  pop = GtkPopover()
  grid = GtkGrid()
  grid[1, 1] = GtkLabel("Iso Value:")
  minLabel = GtkLabel("0.0")
  maxLabel = GtkLabel("1.0")
  adj = GtkAdjustment(0.5, 0.0, 1.0, 0.05, 0.05, 0.05)
  scale = GtkScale(:h, adj)
  scale.hexpand = true
  grid[2, 1] = minLabel
  grid[3, 1] = scale
  grid[4, 1] = maxLabel

  grid[1, 2] = GtkLabel("Iso Range:")
  range = GtkEntry()
  range.text = "0.05"
  grid[2:4, 2] = range


  pop.child = grid

  mode = IsoSurfaceMode(pop, parent, false, adj, minLabel, maxLabel, range)

  initCallbacks!(mode)

  return mode
end

function initCallbacks!(mode::IsoSurfaceMode)
  signal_connect(mode.isoAdj, "value_changed") do widget
    if mode.active
      showData!(WidgetRedraw(), mode.parent)
    end
  end
  signal_connect(mode.isorange, "changed") do widget
    if mode.active
      showData!(WidgetRedraw(), mode.parent)
    end
  end
end

modeName(m::IsoSurfaceMode) = "Iso Surface"
popover(m::IsoSurfaceMode) = m.pop
redrawType(::IsoSurfaceMode) = WidgetRedraw()


function updateData!(m::IsoSurfaceMode, data)
  min, max = extrema(data)
  m.isoAdj.upper = max
  m.isoAdj.lower = min
  m.isoAdj.step_increment = (max - min) / 100
  m.isoMin.label = string(min)
  m.isoMax.label = string(max)
end

function showData!(re, scene::LScene, mode::IsoSurfaceMode, data; kwargs...)
  showData!(re, scene.scene, mode, data; kwargs...)
  return scene
end
function showData!(::WidgetRedraw, scene::Scene, mode::IsoSurfaceMode, data; kwargs...)
  isovalue = mode.isoAdj.value
  isoRange = parse(Float64, mode.isorange.text)
  volume!(scene, data; algorithm=:iso, isovalue=isovalue, isorange=isoRange)
  return scene
end
