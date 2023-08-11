mutable struct SolverPlanInput <: RecoPlanParameterInput
  #grid::Gtk4.GtkGrid
  dd::GtkDropDown
  cb::Union{Nothing,Function}
  choices::Vector{Any}
  function SolverPlanInput(value, field::Symbol)
    choices = pushfirst!(subtypes(AbstractLinearSolver), missing)
    dd = GtkDropDown(choices)
    dd.hexpand = true
    idx = ismissing(value) ? 0 : findfirst(x->!ismissing(x) && x == value, choices) - 1
    dd.selected = idx
    #grid = GtkGrid()
    #label = GtkLabel(string(field))
    #grid[1, 1] = label
    #grid[2, 1] = dd
    input = new(dd, nothing, choices)
    signal_connect(dd, "notify::selected") do w, others...
      if !isnothing(input.cb)
        input.cb()
      end
    end
    return input
  end
end
RecoPlanParameterInput(::Type{Type{S} where S<:AbstractLinearSolver}, value, field) = SolverPlanInput(value, field)
widget(input::SolverPlanInput) = input.dd
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

mutable struct SolverNormalizationPlanInput <: RecoPlanParameterInput
  #grid::Gtk4.GtkGrid
  dd::GtkDropDown
  cb::Union{Nothing,Function}
  choices::Vector{Any}
  function SolverNormalizationPlanInput(value, field::Symbol)
    choices = pushfirst!(subtypes(AbstractRegularizationNormalization), missing)
    dd = GtkDropDown(choices)
    dd.hexpand = true
    idx = ismissing(value) ? 0 : findfirst(x->!ismissing(x) && x == typeof(value), choices) - 1
    dd.selected = idx
    input = new(dd, nothing, choices)
    signal_connect(dd, "notify::selected") do w, others...
      if !isnothing(input.cb)
        input.cb()
      end
    end
    return input
  end
end
RecoPlanParameterInput(::Type{AbstractRegularizationNormalization}, value, field) = SolverNormalizationPlanInput(value, field)
widget(input::SolverNormalizationPlanInput) = input.dd
function value(input::SolverNormalizationPlanInput)
  result = input.choices[input.dd.selected + 1]
  return result isa DataType ? result() : result
end
function update!(input::SolverNormalizationPlanInput, value)
  @idle_add_guarded begin
    input.dd.selected = findfirst(x->!ismissing(x) && x == typeof(value), input.choices) - 1
  end
end
function update!(input::SolverNormalizationPlanInput, value::Missing)
  @idle_add_guarded begin
    input.dd.selected = 0
  end
end
callback!(input::SolverNormalizationPlanInput, value) = input.cb = value