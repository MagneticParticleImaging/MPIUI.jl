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
using MPIMeasurements.Sockets
using Logging, LoggingExtras
using ThreadPools
using Dates
using REPL: fielddoc

ENV["MPILIB_UI"] = "Nothing"

@reexport using MPIMeasurements
@reexport using MPIReco

using ImageUtils: makeAxisArray

using Gtk, Gtk.ShortNames, Gtk.GLib
using Cairo
using Images
#using HDF5

import Winston
using Colors

import Base: getindex
import MPIFiles: addReco, getVisu, addVisu
import MPIMeasurements #: measurement
import Logging: shouldlog, min_enabled_level, handle_message
export openFileBrowser


const dateTimeFormatter = DateFormat("yyyy-mm-dd HH:MM:SS.sss")

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
      @info "openFileBrowser not supported on this OS!"
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


include("LogMessagesWidget.jl")
include("GtkUtils.jl")
include("RawDataViewer.jl")
#include("Measurement/MeasurementWidget.jl")
include("Protocol/ProtocolWidget.jl")
include("SpectrumViewer.jl")
include("BaseViewer.jl")
include("DataViewer/DataViewer.jl")
include("SimpleDataViewer.jl")
include("SFViewerWidget.jl")
include("SFBrowser.jl")
include("RecoWidget.jl")
include("Settings.jl")
include("Devices/ScannerBrowser.jl")
include("MPILab.jl")
include("LCRMeter.jl")
include("ArduinoDataLogger.jl")
include("OnlineReco/OnlineReco.jl")

function __init__()
  if Threads.nthreads() < 4
    error("MPIUI needs Julia to be started with at least two threads. To do so start Julia with `julia -t 4`.")
  end
end

end # module
