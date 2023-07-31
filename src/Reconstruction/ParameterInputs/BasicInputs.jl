mutable struct BasicPlanInput{T} <: RecoPlanParameterInput
  grid::Gtk4.GtkGrid
  entry::Gtk4.GtkEntry
  cb::Union{Nothing,Function}
  function BasicPlanInput(::Type{T}, value, field::Symbol) where T
    entry = GtkEntry()
    str = ismissing(value) ? "" : string(value)
    set_gtk_property!(entry, :text, str)
    set_gtk_property!(entry, :hexpand, true)
    grid = GtkGrid()
    label = GtkLabel(string(field))
    grid[1, 1] = label
    grid[2, 1] = entry
    input = new{T}(grid, entry, nothing)
    signal_connect(entry, :activate) do w
      if !isnothing(input.cb)
        input.cb()
      end
    end
    return input
  end
end
RecoPlanParameterInput(t::Type{T}, value, field) where T = BasicPlanInput(t, value, field)
widget(input::BasicPlanInput) = input.grid
function value(input::BasicPlanInput{T}) where T
  value = input.entry.text
  return isempty(value) ? missing : parse(T, value)
end
function update!(input::BasicPlanInput, value)
  @idle_add_guarded begin
    input.entry.text = string(value)
  end
end
function update!(input::BasicPlanInput, value::Missing)
  @idle_add_guarded begin
    input.entry.text = ""
  end
end
callback!(input::BasicPlanInput, value) = input.cb = value

mutable struct BoolPlanInput <: RecoPlanParameterInput
  widget::Gtk4.GtkCheckButton
  cb::Union{Nothing,Function}
  function BoolPlanInput(value::Bool, field::Symbol)
    check = GtkCheckButton()
    set_gtk_property!(check, :label, field)
    set_gtk_property!(check, :active, value)
    input = new(check, nothing)
    signal_connect(check, :toggled) do w
      set_gtk_property!(check, :inconsistent, false)
      if !isnothing(input.cb)
        input.cb()
      end
    end
    return input
  end
end
function BoolPlanInput(value::Missing, field)
  input = BoolPlanInput(false, field)
  set_gtk_property!(input.widget, :inconsistent, true)
  return input
end
BoolPlanInput(value::Bool, field) = BoolPlanInput(value, field)
RecoPlanParameterInput(::Type{Bool}, value, field) = BoolPlanInput(value, field)
widget(input::BoolPlanInput) = input.widget
function value(input::BoolPlanInput)
  value = get_gtk_property(input.widget, :active, Bool)
  return get_gtk_property(input.widget, :inconsistent, Bool) ? missing : value
end
function update!(input::BoolPlanInput, value::Bool)
  @idle_add_guarded begin
    set_gtk_property!(input.widget, :active, value)
    set_gtk_property!(input.widget, :inconsistent, false)
  end
end
function update!(input::BoolPlanInput, value::Missing)
  @idle_add_guarded begin
    set_gtk_property!(input.widget, :inconsistent, true)
  end
end
callback!(input::BoolPlanInput, value) = input.cb = value
