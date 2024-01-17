mutable struct SolverPlanInput <: RecoPlanParameterInput
  #grid::Gtk4.GtkGrid
  dd::GtkDropDown
  cb::Union{Nothing,Function}
  choices::Vector{Any}
  function SolverPlanInput(value, field::Symbol)
    choices = pushfirst!(RegularizedLeastSquares.linearSolverList(), missing)
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

abstract type AbstractRegularizationTermPlanInput <: RecoPlanParameterInput end

mutable struct RegularizationTermPlanInput{R<:AbstractRegularization} <: AbstractRegularizationTermPlanInput
  grid::GtkGrid
  cb::Union{Nothing, Function}
  inputs::Vector{RecoPlanParameterInput}
  userChange::Bool
  function RegularizationTermPlanInput(value::R, field::Union{Symbol, Nothing}) where R<:AbstractRegularization
    grid = GtkGrid()
    i = 1
    grid[1, i] = GtkLabel(string(nameof(R)))
    input = new{getfield(parentmodule(R), nameof(R))}(grid, nothing, RecoPlanParameterInput[], true)
    if !isnothing(field)
      grid[2, i] = GtkLabel(string(field))
    end
    i+=1
    for field in fieldnames(R)
      fieldInput = RecoPlanParameterInput(fieldtype(R, field), getfield(value, field), field)
      callback!(fieldInput, () -> begin
        if !isnothing(input.cb) && input.userChange
          input.cb()
        end 
      end)
      grid[1, i] = GtkLabel(string(field))
      grid[2, i] = widget(fieldInput)
      push!(input.inputs, fieldInput)
      i+=1
    end
    return input
  end
end
RecoPlanParameterInput(t::Type{T}, value::T, field) where T<:AbstractRegularization = RegularizationTermPlanInput(value, field)
widget(input::RegularizationTermPlanInput) = input.grid
function value(input::RegularizationTermPlanInput{R}) where R
  values = Dict{Symbol, Any}()
  for (idx, field) in enumerate(fieldnames(R))
    values[field] = value(input.inputs[idx])
  end
  λ = pop!(values, :λ)
  return R(λ; values...)
end
function update!(input::RegularizationTermPlanInput{R}, value::R) where R
  input.userChange = false
  for (idx, field) in enumerate(fieldnames(R))
    update!(input.inputs[idx], getfield(value, field))
  end
  input.userChange = true
end
function update!(input::RegularizationTermPlanInput, value::Missing)
  input.userChange = false
  for fieldInput in input.inputs
    update!(fieldInput, missing)
  end
  input.userChange = true
end
callback!(input::RegularizationTermPlanInput, value) = input.cb = value

mutable struct AutoScaledRegularizationTermPlanInput <: AbstractRegularizationTermPlanInput
  grid::GtkGrid
  cb::Union{Nothing, Function}
  regInput::Union{Nothing, AbstractRegularizationTermPlanInput}
  function AutoScaledRegularizationTermPlanInput(value::AutoScaledRegularization, field::Union{Symbol, Nothing})
    grid = GtkGrid()
    label = GtkLabel(string(nameof(typeof(value)), ":"))
    label.hexpand = true
    label.xalign = 0.0
    grid[1, 1] = label
    input = new(grid, nothing, nothing)
    update!(input, value)
    return input
  end
end
RecoPlanParameterInput(t::Type{T}, value::T, field) where T<:AutoScaledRegularization = AutoScaledRegularizationTermPlanInput(value, field)
widget(input::AutoScaledRegularizationTermPlanInput) = input.grid
function value(input::AutoScaledRegularizationTermPlanInput)
  return AutoScaledRegularization(value(input.regInput))
end
function update!(input::AutoScaledRegularizationTermPlanInput, value::AutoScaledRegularization)
  regInput = RecoPlanParameterInput(typeof(value.reg), value.reg, nothing)
  input.grid[1:2, 2] = widget(regInput)
  callback!(regInput, () -> begin
    if !isnothing(input.cb)
      input.cb()
    end 
  end)
  input.regInput = regInput
end
callback!(input::AutoScaledRegularizationTermPlanInput, value) = input.cb = value



mutable struct RegularizationPlanInput <: RecoPlanParameterInput
  list::GtkListBox
  cb::Union{Nothing,Function}
  regInputs::Vector{AbstractRegularizationTermPlanInput}
  RegularizationPlanInput(value::Missing, field::Symbol) = RegularizationPlanInput(AbstractRegularization[], field)
  function RegularizationPlanInput(value::Vector{<:AbstractRegularization}, field::Symbol)
    list = GtkListBox()
    list.vexpand = true
    list.hexpand = true
    list.show_separators = true
    input = new(list, nothing, AbstractRegularizationTermPlanInput[])
    update!(input, value)
    return input
  end
end
RecoPlanParameterInput(::Type{Vector{R} where R<:AbstractRegularization}, value, field) = RegularizationPlanInput(value, field)
widget(input::RegularizationPlanInput) = input.list
function value(input::RegularizationPlanInput)
  result = AbstractRegularization[]
  for input in input.regInputs
    push!(result, value(input))
  end
  return isempty(result) ? missing : result
end
function update!(input::RegularizationPlanInput, value)
  widgets = Any[]
  for widget in input.list
    push!(widgets, widget)
  end
  for widget in widgets
    delete!(input.list, widget)
  end
  empty!(input.regInputs)
  for reg in value
    regInput = RecoPlanParameterInput(typeof(reg), reg, nothing)
    callback!(regInput, () -> begin
      if !isnothing(input.cb)
        input.cb()
      end 
    end)
    push!(input.regInputs, regInput)
    push!(input.list, widget(regInput))
  end
end
function update!(input::RegularizationPlanInput, value::Missing)
  for widget in input.list
    push!(widgets, widget)
  end
  for widget in widgets
    delete!(input.list, widget)
  end
  empty!(input.regInputs)
end
callback!(input::RegularizationPlanInput, value) = input.cb = value