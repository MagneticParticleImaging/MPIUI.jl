export ObliqueSliceMode

# Based on https://discourse.julialang.org/t/oblique-slices-in-makie/83879/12

mutable struct ObliqueSliceMode{P} <: Abstract3DViewerMode
  pop::GtkPopover
  parent::P
  active::Bool
  algBox::GtkComboBoxText
  algorithms::Vector{Symbol}
end
function ObliqueSliceMode(parent::P) where P
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

  mode = ObliqueSliceMode(pop, parent, false, box, algoSymbols)

  initCallbacks!(mode)

  return mode
end

function initCallbacks!(mode::ObliqueSliceMode)
  signal_connect(mode.algBox, "changed") do widget
    if mode.active
      showData!(WidgetRedraw(), mode.parent)
    end
  end
end

modeName(m::ObliqueSliceMode) = "Oblique Slice"
popover(m::ObliqueSliceMode) = m.pop

function showData!(re, scene::LScene, mode::ObliqueSliceMode, data; kwargs...)
  showData!(re, scene.scene, mode, data; kwargs...)
  return scene
end
function showData!(::WidgetRedraw, scene::Scene, mode::ObliqueSliceMode, data; cparams = ColoringParams(extrema(data)..., "viridis"), kwargs...)
  algo = mode.algorithms[mode.algBox.active + 1]
  cmap = to_colormap(Symbol(cparams.cmap))
  cmap[1] = RGBA(0.0, 0.0, 0.0, 0.0)
  volume!(scene, data; algorithm=algo, colormap=cmap, colorrange = (cparams.cmin, cparams.cmax))
  return scene
end
function showData!(::ObservableRedraw, scene::Scene, mode::ObliqueSliceMode, data; cparams = ColoringParams(extrema(data)..., "viridis"), kwargs...)
  # TODO robust
  plt = scene.plots[2]
  cmap = to_colormap(Symbol(cparams.cmap))
  cmap[1] = RGBA(0.0, 0.0, 0.0, 0.0)
  plt.colormap[] = cmap
  plt.colorrange[] = (cparams.cmin, cparams.cmax)
  plt[4][] = data
  return scene
end


function distance_to_plane(P, point, normal)
  return dot(P - point, normal)
end

function isinplane(P, point, normal; rtol=1e-3)
  d = distance_to_plane(P, point, normal)
  return isapprox(1 + d, 1; rtol=rtol)   # more precise when compare to 1
end