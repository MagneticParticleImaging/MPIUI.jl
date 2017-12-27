module MPIUI

using Reexport

ENV["MPILIB_UI"] = "Nothing"

@reexport using MPIMeasurements
@reexport using MPILib

using Gtk, Gtk.ShortNames
using Cairo

ENV["WINSTON_OUTPUT"] = :gtk
import Winston
using Colors

import Base: getindex
import MPIFiles: addReco, getVisu, id, addVisu
import MPIMeasurements: measurement


include("Measurement.jl")
include("SpectrumViewer.jl")
include("BaseViewer.jl")
include("DataViewer.jl")
include("SimpleDataViewer.jl")
include("SFViewer2.jl")
include("SFBrowser.jl")
include("RecoWidget.jl")
include("Settings.jl")
include("MPILab.jl")
include("RawDataViewer.jl")
include("RecoParams.jl")

end # module
