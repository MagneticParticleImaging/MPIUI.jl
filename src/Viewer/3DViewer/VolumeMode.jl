export VolumeMode

mutable struct VolumeMode{P} <: Abstract3DViewerMode
  pop::GtkPopover
  parent::P
end
VolumeMode(parent::P) where P = VolumeMode(GtkPopover(), parent)

popover(m::VolumeMode) = m.pop

function showData!(re, scene::LScene, mode::VolumeMode, data; kwargs...)
  showData!(re, scene.scene, mode, data; kwargs...)
  return scene
end
function showData!(::WidgetRedraw, scene::Scene, mode::VolumeMode, data; kwargs...)
  volume!(scene, data)
  return scene
end
function showData!(::ObservableRedraw, scene::Scene, mode::VolumeMode, data; kwargs...)
  # TODO robust
  scene.plots[2][4] = data
  return scene
end
