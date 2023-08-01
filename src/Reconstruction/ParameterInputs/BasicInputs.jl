mutable struct BasicPlanInput{T} <: RecoPlanParameterInput
  grid::Gtk4.GtkGrid
  entry::Gtk4.GtkEntry
  cb::Union{Nothing,Function}
  BasicPlanInput(t, value::Missing, field) = BasicPlanInput(t, "", field)
  BasicPlanInput(t, value, field) = BasicPlanInput(t, string(value), field)
  BasicPlanInput(t, value::Vector, field) = BasicPlanInput(t, join(value, ", "), field)
  function BasicPlanInput(::Type{T}, value::String, field::Symbol) where T
    entry = GtkEntry()
    set_gtk_property!(entry, :text, value)
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
function value(input::BasicPlanInput{Vector{T}}) where T
  value = input.entry.text
  return isempty(value) ? missing : map(x->parse(T, x), split(value, ","))
end
update!(input::BasicPlanInput, value) = update!(input, string(value))
update!(input::BasicPlanInput, value::Vector) = update!(input, join(value, ", "))
function update!(input::BasicPlanInput, value::String)
  @idle_add_guarded begin
    input.entry.text = value
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

mutable struct UnitRangePlanInput{T} <: RecoPlanParameterInput
  grid::Gtk4.GtkGrid
  entry::Gtk4.GtkEntry
  cb::Union{Nothing,Function}
  function UnitRangePlanInput(::Type{UnitRange{T}}, value, field::Symbol) where T
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
RecoPlanParameterInput(t::Type{UnitRange{T}}, value, field) where T = UnitRangePlanInput(t, value, field)
widget(input::UnitRangePlanInput) = input.grid
function value(input::UnitRangePlanInput{T}) where T
  value = input.entry.text
  if isempty(value)
    return missing
  else
    temp = split(value, ":")
    start = parse(T, temp[1])
    stop = length(temp) == 1 ? start : parse(T, temp[2])
    return UnitRange(start, stop)
  end
end
function update!(input::UnitRangePlanInput, value)
  @idle_add_guarded begin
    input.entry.text = string(value)
  end
end
function update!(input::UnitRangePlanInput, value::Missing)
  @idle_add_guarded begin
    input.entry.text = ""
  end
end
callback!(input::UnitRangePlanInput, value) = input.cb = value

mutable struct SolverPlanInput <: RecoPlanParameterInput
  grid::Gtk4.GtkGrid
  dd::GtkDropDown
  cb::Union{Nothing,Function}
  choices::Vector{Any}
  function SolverPlanInput(value, field::Symbol)
    choices = pushfirst!(subtypes(AbstractLinearSolver), missing)
    dd = GtkDropDown(choices)
    dd.hexpand = true
    idx = ismissing(value) ? 0 : findfirst(x->!ismissing(x) && x == value, choices) - 1
    dd.selected = idx
    grid = GtkGrid()
    label = GtkLabel(string(field))
    grid[1, 1] = label
    grid[2, 1] = dd
    input = new(grid, dd, nothing, choices)
    signal_connect(dd, "notify::selected") do w, others...
      if !isnothing(input.cb)
        input.cb()
      end
    end
    return input
  end
end
RecoPlanParameterInput(::Type{Type{S} where S<:AbstractLinearSolver}, value, field) = SolverPlanInput(value, field)
widget(input::SolverPlanInput) = input.grid
function value(input::SolverPlanInput)
  return input.choices[input.dd.selected + 1]
end
function update!(input::SolverPlanInput, value)
  @idle_add_guarded begin
    input.dd.selected = findfirst(x->!ismissing(x) && x == value, input.choices) - 1
  end
end
function update!(input::SolverPlanInput, value::Missing)
  @idle_add_guarded begin
    input.dd.selected = 0
  end
end
callback!(input::SolverPlanInput, value) = input.cb = value

mutable struct UnionPlanInput <: RecoPlanParameterInput
  #grid::Gtk4.GtkGrid
  nb::GtkNotebook
  cb::Union{Nothing,Function}
  choices::Vector{RecoPlanParameterInput}
  types::Vector{Any}
  userChange::Bool
  page::Int64
  function UnionPlanInput(plan::RecoPlan, union::Union, value, field)
    nb = GtkNotebook()
    choices = RecoPlanParameterInput[]
    types = AbstractImageReconstruction.uniontypes(union)
    input = new(nb, nothing, choices, types, true, 1)
    for type in types
      temp = value isa type ? value : missing
      tempInput = RecoPlanParameterInput(plan, type, temp, field)
      callback!(tempInput, () -> begin 
        if !isnothing(input.cb) && input.userChange
          input.cb()
        end
      end)
      push!(choices, tempInput)
      push!(nb, widget(tempInput), string(nameof(type)))
    end    
    signal_connect(nb, :switch_page) do nb, page, idx
      # This happens before page switch, so value(input) would return old value if we access nb.page in value(...)
      input.page = idx + 1
      if !isnothing(input.cb) && input.userChange
        input.cb()
      end
    end
    return input
  end
end
RecoPlanParameterInput(plan::RecoPlan, union::Union, value, field) = UnionPlanInput(plan, union, value, field)
widget(input::UnionPlanInput) = input.nb
value(input::UnionPlanInput) = value(input.choices[input.page])
function update!(input::UnionPlanInput, value)
  input.userChange = false
  idx = findfirst(x-> value isa x, input.types)
  input.nb.page = idx - 1
  update!(input.choices[idx], value)
  input.userChange = true
end
function update!(input::UnionPlanInput, value::Missing)
  input.userChange = false
  for temp in input.choices
    update!(temp, value)
  end
  input.userChange = true
end
callback!(input::UnionPlanInput, value) = input.cb = value