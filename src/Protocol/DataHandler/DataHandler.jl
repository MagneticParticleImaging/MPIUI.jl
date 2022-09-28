abstract type AbstractDataHandler end

isready(widget::AbstractDataHandler) = false
function enable!(widget::AbstractDataHandler, val::Bool)
  # NOP
end
getParameterTitle(widget::AbstractDataHandler) = "N/A"
getParameterWidget(widget::AbstractDataHandler) = Gtk.Grid()
getDisplayTitle(widget::AbstractDataHandler) = "N/A"
getDisplayWidget(widget::AbstractDataHandler) = Gtk.Box()
function updateData(widget::AbstractDataHandler, data)
  # NOP
end

include("ParamExpander.jl")
include("RawDataHandler.jl")