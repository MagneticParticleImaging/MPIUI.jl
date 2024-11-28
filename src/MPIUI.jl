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
using MPISphericalHarmonics, SphericalHarmonicExpansions # for MagneticFieldViewer
using NLsolve # for MagneticFieldViewer: findFFP()
using DataFrames, CSV # for MagneticFieldViewer: export as csv
using Unitful
import CairoMakie
using Gtk4Makie

ENV["MPILIB_UI"] = "Nothing"

@reexport using MPIMeasurements
@reexport using MPIReco
@reexport using MPIViewers
using MPIReco.RegularizedLeastSquares

import MPIViewers: updateData!, showData!, updateData, showData

using ImageUtils: makeAxisArray, Axis

using Gtk4, Gtk4.G_, Gtk4.GLib
using Cairo
using Images
#using HDF5

using Colors

import Base: getindex
import MPIFiles: addReco, getVisu, addVisu
import MPIMeasurements #: measurement
import Logging: shouldlog, min_enabled_level, handle_message
export openFileBrowser


const dateTimeFormatter = DateFormat("yyyy-mm-dd HH:MM:SS.sss")

function object_(builder::GtkBuilder,name::AbstractString, T::Type)::T
   return convert(T,ccall((:gtk_builder_get_object,Gtk4.libgtk),Ptr{Gtk4.GObject},(Ptr{Gtk4.GObject},Ptr{UInt8}),builder,name))
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

function showError(ex)
  exTrunc = first(string(ex), 500)
  if length(string(ex)) > 500
    exTrunc *="..."
  end
  str = string("Something went wrong!\n", exTrunc)
  if isassigned(mpilab)
    d = info_dialog(()-> nothing, str, mpilab[]["mainWindow"])
  else
    d = info_dialog(()-> nothing, str)
  end
  d.modal = true
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


include("LogMessagesWidget.jl")
include("Reconstruction/OfflineRecoWidget.jl")
include("Protocol/ProtocolWidget.jl")
include("SFBrowser.jl")
include("Settings.jl")
include("Devices/ScannerBrowser.jl")
include("MPILab.jl")
include("LCRMeter.jl")
include("OnlineReco/OnlineReco.jl")

function __init__()
  if Threads.nthreads() < 4
    @warn "MPIUI was started with less than four Julia threads. For use with MPIMeasurements please start Julia with 'julia -t 4' or more"
  end
end

end # module
