export CoordinateParameter

mutable struct CoordinateParameter <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  field::Symbol

  function CoordinateParameter(field::Symbol, coord::Union{ScannerCoords, Nothing}, tooltip::Union{Nothing, AbstractString} = nothing)
    grid = GtkGrid()
    uifile = joinpath(@__DIR__, "..", "..", "builder", "positionsWidget.ui")
    b = GtkBuilder(filename=uifile)
    coordEntry = Gtk4.G_.get_object(b, "gridCoord")
    label = GtkLabel(string(field))
    set_gtk_property!(label, :xalign, 0.0)
    addTooltip(label, tooltip)
    grid[1, 1] = label
    grid[2, 1] = coordEntry
    coordParam = new(grid.handle, b, field)
    updateCoordinate(coordParam, coord)
    return Gtk4.GLib.gobject_move_ref(coordParam, grid)
  end
end

getindex(m::CoordinateParameter, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)

function updateCoordinate(param::CoordinateParameter, coord::ScannerCoords)
  @idle_add_guarded begin
    set_gtk_property!(param["entX"], :text, string(ustrip(u"mm", coord.data[1])))
    set_gtk_property!(param["entY"], :text, string(ustrip(u"mm", coord.data[2])))
    set_gtk_property!(param["entZ"], :text, string(ustrip(u"mm", coord.data[3])))
  end
end

function updateCoordinate(param::CoordinateParameter, ::Nothing)
  coord = ScannerCoords([0.0, 0.0, 0.0].*1Unitful.mm)
  updateCoordinate(param, coord)
end

function setProtocolParameter(param::CoordinateParameter, params::ProtocolParams)
  entryX = get_gtk_property(param["entX"], :text, String)
  entryY = get_gtk_property(param["entY"], :text, String)
  entryZ = get_gtk_property(param["entZ"], :text, String)
  posFloat = tryparse.(Float64, [entryX, entryY, entryZ])
  scannerCoord = ScannerCoords(posFloat.*1Unitful.mm)
  setfield!(params, param.field, scannerCoord)
end