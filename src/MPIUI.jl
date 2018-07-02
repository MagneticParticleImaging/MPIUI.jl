__precompile__()
module MPIUI

using Reexport

ENV["MPILIB_UI"] = "Nothing"

@reexport using MPIMeasurements
@reexport using MPILib

using Gtk, Gtk.ShortNames
using Cairo
using Images

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
    if is_apple()
      run(`open $dir`)
    elseif is_linux()
      run(`xdg-open $dir`)
    else
      println("openFileBrowser not supported on thos OS!")
    end
  end
  return
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
#include("ArduinoDataLogger.jl")
end # module
