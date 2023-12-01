abstract type RecoPlanParameterInput end
widget(input::RecoPlanParameterInput) = error("$(typeof(input)) must implement method widget")
value(input::RecoPlanParameterInput) = error("$(typeof(input)) must implement method value")
update!(input::RecoPlanParameterInput, value) = error("$(typeof(input)) must implement method update!")
callback!(input::RecoPlanParameterInput, value) = error("$(typeof(input)) must implement method callback!")
RecoPlanParameterInput(plan::RecoPlan, field::Symbol) = RecoPlanParameterInput(plan, type(plan, field), plan[field], field)
RecoPlanParameterInput(plan::RecoPlan, type, value, field) = RecoPlanParameterInput(type, value, field)

include("ParameterInputs/ParameterInputs.jl")

mutable struct RecoPlanParameter{T, I<:RecoPlanParameterInput} 
  plan::RecoPlan
  field::Symbol
  input::I
  userChange::Bool
  widget::GtkWidget
  RecoPlanParameter(plan::RecoPlan, field::Symbol, input::I, widget::GtkWidget) where {I<:RecoPlanParameterInput} = new{type(plan, field), I}(plan, field, input, false, widget)
end
widget(parameter::RecoPlanParameter) = parameter.widget
id(parameter::RecoPlanParameter) = join(string.(push!(AbstractImageReconstruction.parentfields(parameter.plan), parameter.field)), ".")

function RecoPlanParameter(plan::RecoPlan{T}, field::Symbol) where {T<:AbstractImageReconstructionParameters}
  input = RecoPlanParameterInput(plan, field)
  widget = createParameterWidget(plan, field, input)
  parameter = RecoPlanParameter(plan, field, input, widget)
  addListener!(plan, field, GtkPlanListener(parameter))
  callback!(input, () -> update!(parameter))
  return parameter
end

function createParameterWidget(plan, field, input::RecoPlanParameterInput) # support different stylings as an argument
  grid = GtkGrid()
  label = GtkLabel("$field:")
  label.use_markup = true
  label.xalign = 0.0
  grid[1,1] = label
  grid[1:2,2] = widget(input)
  return grid
end

function update!(parameter::RecoPlanParameter)
  parameter.userChange = true
  parameter.plan[parameter.field] = value(parameter.input)
  parameter.userChange = false
end
struct GtkPlanListener <: TransientListener
  parameter::RecoPlanParameter
end
function AbstractImageReconstruction.valueupdate(listener::GtkPlanListener, origin, field, old, new)
  # Only update if change was not initiated by user
  !listener.parameter.userChange && update!(listener.parameter.input, new)
end

mutable struct RecoPlanParameters{T}
  plan::RecoPlan{T}
  parameters::Vector{RecoPlanParameter}
  nestedParameters::Vector{RecoPlanParameters}
end
id(parameters::RecoPlanParameters) = join(string.(AbstractImageReconstruction.parentfields(parameters.plan)), ".")

function RecoPlanParameters(plan::RecoPlan)
  parameters = Vector{RecoPlanParameter}()
  nested = Vector{RecoPlanParameters}()
  for property in sort(collect(propertynames(plan)))
    prop = plan[property]
    if prop isa RecoPlan
      push!(nested, RecoPlanParameters(prop))
    else
      push!(parameters, RecoPlanParameter(plan, property))
    end
  end
  return RecoPlanParameters(plan, parameters, nested)
end