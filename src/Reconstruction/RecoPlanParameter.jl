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

function RecoPlanParameter(plan::RecoPlan{T}, field::Symbol) where {T<:AbstractReconstructionAlgorithmParameter}
  input = RecoPlanParameterInput(plan, field)
  widget = createParameterWidget(plan, field, input)
  parameter = RecoPlanParameter(plan, field, input, widget)
  addListener!(plan, field, GtkPlanListener(parameter))
  callback!(input, () -> update!(parameter))
  return parameter
end

function createParameterWidget(plan, field, input::RecoPlanParameterInput) # support different stylings as an argument
  grid = GtkGrid()
  label = GtkLabel("<b>$field:</b>")
  label.use_markup = true
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