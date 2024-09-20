module MPIViewers

using Reexport

# Data Handling
@reexport using MPIFiles
@reexport using MPIReco
@reexport using MPISphericalHarmonics
using SphericalHarmonicExpansions
using Unitful
using MPISphericalHarmonics.NLsolve
using FFTW

# File Handling
#using DelimtedFiles
using DataFrames
using CSV

# Visualization
using CairoMakie
using Colors
using Gtk4
using Gtk4Makie
using Gtk4.G_, Gtk4.GLib
using Cairo
using Images
using ImageUtils
using ImageUtils: converttometer, ColoringParams, makeAxisArray, Axis


import Base: getindex
import MPIFiles: addReco, getVisu, addVisu

function object_(builder::GtkBuilder,name::AbstractString, T::Type)::T
  return convert(T,ccall((:gtk_builder_get_object,Gtk4.libgtk),Ptr{Gtk4.GObject},(Ptr{Gtk4.GObject},Ptr{UInt8}),builder,name))
end

function imToVecIm(image::ImageMeta)
  out = ImageMeta[]
  for i=1:size(image,1)
    I = getindex(image, i, ntuple(x->:,ndims(image)-1)...)
    push!(out, I)
  end
  return out
end

macro guard(ex)
  return :(try; begin $(ex) end; catch e; showError(e); end)
end

macro idle_add_guarded(ex)
  quote
  g_idle_add() do
      try
        $(esc(ex))
      catch err
        @warn("Error in @guarded callback", exception=(err, catch_backtrace()))
      end
      return false
    end
  end
end

const colors = [(0/255,73/255,146/255), # UKE blau
(239/255,123/255,5/255),	# Orange (dunkel)
(138/255,189/255,36/255),	# Grün
(178/255,34/255,41/255), # Rot
(170/255,156/255,143/255), 	# Mocca
(87/255,87/255,86/255),	# Schwarz (Schrift)
(255/255,223/255,0/255), # Gelb
(104/255,195/255,205/255),	# "TUHH"
(45/255,198/255,214/255), #  TUHH
(193/255,216/255,237/255)]

function showError(ex)
  exTrunc = first(string(ex), 500)
  if length(string(ex)) > 500
    exTrunc *="..."
  end
  str = string("Something went wrong!\n", exTrunc)
  d = info_dialog(()-> nothing, str)
  d.modal = true
end

include("GtkUtils.jl")
include("BaseViewer.jl")
include("SimpleDataViewer.jl")
include("DataViewer/DataViewer.jl")
include("RawDataViewer.jl")
include("SpectrogramViewer.jl")
include("SFViewerWidget.jl")
include("MagneticFieldViewer/MagneticFieldViewer.jl")
include("3DViewer/3DViewer.jl")

end # module MPIViewers