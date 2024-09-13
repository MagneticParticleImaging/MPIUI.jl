abstract type Abstract3DViewerMode end
modeName(m::Abstract3DViewerMode) = string(typeof(m))

#=
 At the moment it is not possible to update a GtkMakieWidget with new plots.
 This means we either have to create a new GtkMakieWidget to update the plot
 or we hook into the observables of the plots.

 The second approach breaks for certain plots, for example for isovolumes (if the isovalue changed).
=# 
abstract type Abstract3DViewerModeRedrawType end
struct ObservableRedraw <: Abstract3DViewerModeRedrawType end
struct WidgetRedraw <: Abstract3DViewerModeRedrawType end
redrawType(::Abstract3DViewerMode) = ObservableRedraw()

include("3DViewerWidget.jl")
include("VolumeMode.jl")
include("SectionalMode.jl")
include("IsoSurfaceMode.jl")

function updateData!(m::Abstract3DViewerMode, arr)
  # NOP
end

function showData!(gm::Gtk4Makie.GtkGLMakie, mode, data; kwargs...)
  fig = Figure()
  lscene = LScene(fig[1,1])
  res = showData!(WidgetRedraw(), lscene, mode, data; kwargs...)
  push!(gm, fig)
  return res
end

export DataViewer3D, DataViewer3DWidget
mutable struct DataViewer3D
  w::Gtk4.GtkWindowLeaf
  dvw::DataViewer3DWidget
end

function DataViewer3D(imFG; kwargs...)
  dv = DataViewer3D(; kwargs...)
  updateData!(dv.dvw,imFG)
  return dv
end

function DataViewer3D(; kwargs...)
  w = GtkWindow("Data Viewer",800,600)
  dw = DataViewer3DWidget(; kwargs...)
  push!(w,dw)
  show(w)
  return DataViewer3D(w,dw)
end