abstract type ParameterType end
abstract type SpecialParameterType <: ParameterType end
abstract type RegularParameterType <: ParameterType end
struct GenericParameterType <: RegularParameterType end
struct SequenceParameterType <: SpecialParameterType end
struct PositionParameterType <: SpecialParameterType end
struct BoolParameterType <: RegularParameterType end
struct CoordinateParameterType <: SpecialParameterType end
struct ReconstructionParameterType <: SpecialParameterType end
function parameterType(field::Symbol, value)
  if field == :sequence
    return SequenceParameterType()
  elseif field == :positions
    return PositionParameterType()
  elseif field == :fgPos || field == :center
    return CoordinateParameterType()
  elseif field == :reconstruction
    return ReconstructionParameterType()
  else
    return GenericParameterType()
  end
end
function parameterType(::Symbol, value::Bool)
    return BoolParameterType()
end
function parameterType(::Symbol, value::ScannerCoords)
  return CoordinateParameterType()
end

mutable struct GenericEntry{T} <: Gtk4.GtkEntry
  handle::Ptr{Gtk4.GObject}
  entry::GtkEntry
  function GenericEntry{T}(value::AbstractString) where {T}
    entry = GtkEntry()
    set_gtk_property!(entry, :text, value)
    set_gtk_property!(entry, :hexpand, true)
    set_gtk_property!(entry,:width_chars,5)
    generic = new(entry.handle, entry)
    return Gtk4.GLib.gobject_move_ref(generic, entry)
  end
end

function value(entry::GenericEntry{T}) where {T}
  valueString = get_gtk_property(entry, :text, String)
  return tryparse(T, valueString)
end

function value(entry::GenericEntry{T}) where {T<:AbstractString}
  return Gtk4.get_gtk_property(entry, :text, String)
end

mutable struct GenericParameter{T} <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  field::Symbol
  label::GtkLabel
  entry::GenericEntry{T}

  function GenericParameter{T}(field::Symbol, label::AbstractString, value::AbstractString, tooltip::Union{Nothing, AbstractString} = nothing) where {T}
    grid = GtkGrid()
    entry = GenericEntry{T}(value)
    label = GtkLabel(label)
    ### set_gtk_property!(label, :xalign, 0.0)
    addTooltip(label, tooltip)
    grid[1, 1] = label
    grid[2, 1] = entry
    generic = new(grid.handle, field, label, entry)
    return Gtk4.GLib.gobject_move_ref(generic, grid)
  end
end

mutable struct UnitfulGtkEntry <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  entry::GtkEntry
  unitValue
  function UnitfulGtkEntry(value::T) where {T<:Quantity}
    grid = GtkGrid()
    entry = GtkEntry()
    set_gtk_property!(entry, :text, string(ustrip(value)))
    unitValue = unit(value)
    unitText = string(unitValue)
    unitLabel = GtkLabel(unitText)
    grid[1, 1] = entry
    grid[2, 1] = unitLabel
    set_gtk_property!(grid,:column_spacing,5)
    set_gtk_property!(entry,:width_chars,5)
    set_gtk_property!(entry, :hexpand, true)
    result = new(grid.handle, entry, unitValue)
    return Gtk4.GLib.gobject_move_ref(result, grid)
  end
end

function value(entry::UnitfulGtkEntry)
  valueString = get_gtk_property(entry.entry, :text, String)
  value = tryparse(Float64, valueString)
  return value * entry.unitValue
end
mutable struct UnitfulParameter <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  field::Symbol
  label::GtkLabel
  entry::UnitfulGtkEntry
  function UnitfulParameter(field::Symbol, label::AbstractString, value::T, tooltip::Union{Nothing, AbstractString} = nothing) where {T<:Quantity}
    grid = GtkGrid()
      
    unitfulGtkEntry = UnitfulGtkEntry(value)
    label = GtkLabel(label)
    ### set_gtk_property!(label, :xalign, 0.0)
    addTooltip(label, tooltip)
    grid[1, 1] = label
    grid[2, 1] = unitfulGtkEntry
    #set_gtk_property!(unitLabel, :hexpand, true)
    generic = new(grid.handle, field, label, unitfulGtkEntry)
    return Gtk4.GLib.gobject_move_ref(generic, grid)
  end
end

mutable struct RegularParameters <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  paramDict::Dict{Symbol, GObject}
  function RegularParameters()
    grid = GtkGrid()
    set_gtk_property!(grid, :column_spacing, 5)
    set_gtk_property!(grid, :row_spacing, 5)
    result = new(grid.handle, Dict{Symbol, GObject}())
    return Gtk4.GLib.gobject_move_ref(result, grid)
  end
end

mutable struct ParameterLabel <: Gtk4.GtkLabel
  handle::Ptr{Gtk4.GObject}
  field::Symbol

  function ParameterLabel(field::Symbol, tooltip::Union{AbstractString, Nothing} = nothing)
    label = GtkLabel(string(field))
    addTooltip(label, tooltip)
    result = new(label.handle, field)
    return Gtk4.GLib.gobject_move_ref(result, label)
  end
end

mutable struct BoolParameter <: Gtk4.GtkCheckButton
  handle::Ptr{Gtk4.GObject}
  field::Symbol

  function BoolParameter(field::Symbol, label::AbstractString, value::Bool, tooltip::Union{Nothing, AbstractString} = nothing)
    check = GtkCheckButton()
    set_gtk_property!(check, :label, label)
    set_gtk_property!(check, :active, value)
    ### set_gtk_property!(check, :xalign, 0.5)
    addTooltip(check, tooltip)
    cb = new(check.handle, field)
    return Gtk4.GLib.gobject_move_ref(cb, check)
  end
end

value(entry::BoolParameter) = get_gtk_property(entry, :active, Bool)

function setProtocolParameter(field::Symbol, parameterObj, params::ProtocolParams)
  @info "Setting field $field"
  val = value(parameterObj)
  setfield!(params, field, val)
end

# Technically BoolParameter contains the field already but for the sake of consistency this is structured like the other parameter
function setProtocolParameter(parameterObj::BoolParameter, params::ProtocolParams)
  field = parameterObj.field
  setProtocolParameter(field, parameterObj, params)
end

function setProtocolParameter(parameterObj::Union{UnitfulParameter, GenericParameter{T}}, params::ProtocolParams) where {T}
  field = parameterObj.field
  setProtocolParameter(field, parameterObj.entry, params)
end

function setProtocolParameter(fieldObj::Union{ParameterLabel, BoolParameter}, valueObj, params::ProtocolParams)
  field = fieldObj.field
  setProtocolParameter(field, valueObj, params)
end

function setProtocolParameter(parameterObj::RegularParameters, params::ProtocolParams)
  for i = 1:length(parameterObj.paramDict)
    fieldObj = parameterObj[1, i]
    valueObj = parameterObj[2, i]
    setProtocolParameter(fieldObj, valueObj, params)
  end
end

include("SequenceParameter.jl")
include("PositionsParameter.jl")
include("CoordinateParameter.jl")