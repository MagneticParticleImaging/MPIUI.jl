module MPIUI

using ImageUtils
using Statistics
using Random
using LinearAlgebra
using Reexport
using Printf
using DelimitedFiles
using FFTW
using Pkg
using InteractiveUtils
using ImageUtils: converttometer, ColoringParams

ENV["MPILIB_UI"] = "Nothing"

@reexport using MPIMeasurements
@reexport using MPIReco

using ImageUtils: makeAxisArray

using Gtk, Gtk.ShortNames, Gtk.GLib
using Cairo
using Images
using HDF5

import Winston
using Colors

import Base: getindex
import MPIFiles: addReco, getVisu, id, addVisu
import MPIMeasurements #: measurement
export openFileBrowser

function object_(builder::Builder,name::AbstractString, T::Type)::T
   return convert(T,ccall((:gtk_builder_get_object,Gtk.libgtk),Ptr{Gtk.GObject},(Ptr{Gtk.GObject},Ptr{UInt8}),builder,name))
end

function openFileBrowser(dir::String)
  if isdir(dir)
    if Sys.isapple()
      run(`open $dir`)
    elseif Sys.islinux()
      run(`xdg-open $dir`)
    else
      @info "openFileBrowser not supported on thos OS!"
    end
  end
  return
end

function imToVecIm(image::ImageMeta)
   out = ImageMeta[]
   for i=1:size(image,1)
     I = getindex(image, i, ntuple(x->:,ndims(image)-1)...)
     push!(out, I)
   end
   return out
 end

function showError(ex, bt=catch_backtrace())
  str = string("Something went wrong!\n", ex, "\n\n", stacktrace(bt))
  @show str
  if isassigned(mpilab)
    info_dialog(str, mpilab[]["mainWindow"])
  else
    info_dialog(str)
  end
end

macro guard(ex)
  return :(try; begin $(ex) end; catch e; showError(e); end)
end

include("GtkUtils.jl")
include("RawDataViewer.jl")
include("Measurement.jl")
include("SpectrumViewer.jl")
include("BaseViewer.jl")
include("DataViewer/DataViewer.jl")
include("SimpleDataViewer.jl")
include("SFViewerWidget.jl")
include("SFBrowser.jl")
include("RecoWidget.jl")
include("Settings.jl")
include("MPILab.jl")
include("LCRMeter.jl")
include("ArduinoDataLogger.jl")
include("OnlineReco/OnlineReco.jl")
end # module
