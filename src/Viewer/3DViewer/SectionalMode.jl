
export SectionalMode

mutable struct SectionalMode{P} <: Abstract3DViewerMode
  pop::GtkPopover
  parent::P
  active::Bool
  yzAdj::GtkAdjustment
  xzAdj::GtkAdjustment
  xyAdj::GtkAdjustment     
  yzToggler::GtkCheckButton
  xzToggler::GtkCheckButton
  xyToggler::GtkCheckButton   
end

function SectionalMode(parent::P) where P
  pop = GtkPopover()
  yzAdj = GtkAdjustment(1, 1, 1, 1, 1, 1)
  xzAdj = GtkAdjustment(1, 1, 1, 1, 1, 1)
  xyAdj = GtkAdjustment(1, 1, 1, 1, 1, 1)
  yzToggler = GtkCheckButton("Visible")
  xzToggler = GtkCheckButton("Visible")
  xyToggler = GtkCheckButton("Visible")

  grid = GtkGrid()
  grid[1, 1] = GtkLabel("xy")
  grid[1, 2] = GtkSpinButton(xyAdj, 1, 0)
  grid[1, 3] = xyToggler

  grid[2, 1] = GtkLabel("xz")
  grid[2, 2] = GtkSpinButton(xzAdj, 1, 0)
  grid[2, 3] = xzToggler

  grid[3, 1] = GtkLabel("yz")
  grid[3, 2] = GtkSpinButton(yzAdj, 1, 0)
  grid[3, 3] = yzToggler

  pop.child = grid
  mode = SectionalMode(pop, parent, false, yzAdj, xzAdj, xyAdj, yzToggler, xzToggler, xyToggler)

  initCallbacks!(mode)

  return mode
end

modeName(m::SectionalMode) = "Volume Slices"
popover(m::SectionalMode) = m.pop

function initCallbacks!(mode::SectionalMode)
  signal_connect(mode.yzAdj, "value_changed") do widget
    if mode.active
      showData!(ObservableRedraw(), mode.parent)
    end
  end           
  signal_connect(mode.xzAdj, "value_changed") do widget
    if mode.active
      showData!(ObservableRedraw(), mode.parent)
    end
  end               
  signal_connect(mode.xyAdj, "value_changed") do widget
    if mode.active
      showData!(ObservableRedraw(), mode.parent)
    end
  end    

  signal_connect(mode.yzToggler, "toggled") do widget
    if mode.active
      showData!(ObservableRedraw(), mode.parent)
    end
  end     
  signal_connect(mode.xzToggler, "toggled") do widget
    if mode.active
      showData!(ObservableRedraw(), mode.parent)
    end
  end     
  signal_connect(mode.xyToggler, "toggled") do widget
    if mode.active
      showData!(ObservableRedraw(), mode.parent)
    end
  end
end

function updateData!(m::SectionalMode, data5D::AbstractArray{T, 5}) where T
  m.yzAdj.upper = size(data5D, 2)
  m.xzAdj.upper = size(data5D, 3)
  m.xyAdj.upper = size(data5D, 4)
  m.yzToggler.active = true
  m.xzToggler.active = true
  m.xyToggler.active = true
end

function showData!(re, scene::LScene, mode::SectionalMode, data; kwargs...)
  showData!(re, scene.scene, mode, data; kwargs...)
  return scene
end
function showData!(::WidgetRedraw, scene::Scene, mode::SectionalMode, data; kwargs...)
  plt = volumeslices!(scene, map(i -> 1:i, size(data))..., data; bbox_visible = false)
  plt.heatmap_xy[].visible = Observable{Any}(true)
	plt.heatmap_xz[].visible = Observable{Any}(true)
	plt.heatmap_yz[].visible = Observable{Any}(true)
  return scene
end
function showData!(::ObservableRedraw, scene::Scene, mode::SectionalMode, data; kwargs...)
  # TODO robust plot selection
  plt = scene.plots[2]
  plt[1] = 1:size(data, 1)
  plt[2] = 1:size(data, 2)
  plt[3] = 1:size(data, 3)
  plt[4] = data
  plt.update_xz[](Int64(mode.xzAdj.value))
	plt.update_xy[](Int64(mode.xyAdj.value))
	plt.update_yz[](Int64(mode.yzAdj.value))
  plt.heatmap_xy[].visible[] = mode.xyToggler.active
	plt.heatmap_xz[].visible[] = mode.xzToggler.active
	plt.heatmap_yz[].visible[] = mode.yzToggler.active
  return scene
end