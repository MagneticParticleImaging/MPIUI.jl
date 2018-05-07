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
import MPIMeasurements: measurement

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

end # module
