export VolumeMode


mutable struct VolumeMode{P} <: Abstract3DViewerMode
  pop::GtkPopover
  parent::P
  active::Bool
  algBox::GtkComboBoxText
  algorithms::Vector{Symbol}
end
function VolumeMode(parent::P) where P
  algoStrings = ["Absorption", "Additive RGBA", "Absorption RGBA", "MIP"]
  algoSymbols = [:absorption, :additive, :absorptionrgba, :mip]
  box = GtkComboBoxText()
  foreach(algo -> push!(box, algo), algoStrings)
  box.active = 3
  
  pop = GtkPopover()
  grid = GtkGrid()
  grid[1, 1] = GtkLabel("Algorithm")
  grid[1, 2] = box

  pop.child = grid

  mode = VolumeMode(pop, parent, false, box, algoSymbols)

  initCallbacks!(mode)

  return mode
end

function initCallbacks!(mode::VolumeMode)
  signal_connect(mode.algBox, "changed") do widget
    if mode.active
      showData!(WidgetRedraw(), mode.parent)
    end
  end
end

modeName(m::VolumeMode) = "Volume"
popover(m::VolumeMode) = m.pop

function showData!(re, scene::LScene, mode::VolumeMode, data; kwargs...)
  showData!(re, scene.scene, mode, data; kwargs...)
  return scene
end
function showData!(::WidgetRedraw, scene::Scene, mode::VolumeMode, data; kwargs...)
  algo = mode.algorithms[mode.algBox.active + 1]
  volume!(scene, data; algorithm=algo)
  return scene
end
function showData!(::ObservableRedraw, scene::Scene, mode::VolumeMode, data; kwargs...)
  # TODO robust
  scene.plots[2][4] = data
  return scene
end
