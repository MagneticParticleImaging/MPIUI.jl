module MPIUI

using Statistics
using Random
using LinearAlgebra
using Reexport
using Printf
using DelimitedFiles
using FFTW
using Pkg
using InteractiveUtils

ENV["MPILIB_UI"] = "Nothing"

@reexport using MPIMeasurements
@reexport using MPILib

using Gtk, Gtk.ShortNames
using Cairo
using Images
using HDF5

ENV["WINSTON_OUTPUT"] = :gtk
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
  info_dialog(str, mpilab[]["mainWindow"])
end

include("GtkUtils.jl")
include("RawDataViewer.jl")
include("Measurement.jl")
include("SpectrumViewer.jl")
include("BaseViewer.jl")
include("DataViewer.jl")
include("SimpleDataViewer.jl")
include("SFViewerWidget.jl")
include("SFBrowser.jl")
include("RecoWidget.jl")
include("Settings.jl")
include("MPILab.jl")
include("LCRMeter.jl")
include("ArduinoDataLogger.jl")
end # module
