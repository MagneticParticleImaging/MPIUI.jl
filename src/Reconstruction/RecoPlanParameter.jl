abstract type RecoPlanParameterInput end
widget(input::RecoPlanParameterInput) = error("$(typeof(input)) must implement method widget")
value(input::RecoPlanParameterInput) = error("$(typeof(input)) must implement method value")
update!(input::RecoPlanParameterInput, value) = error("$(typeof(input)) must implement method update!")

RecoPlanParameterInput(plan::RecoPlan, field::Symbol) = RecoPlanParameterInput(plan[field], field)

struct BoolPlanInput <: RecoPlanParameterInput
  widget::Gtk4.GtkCheckButton
  function BoolPlanInput(value::Bool, field::Symbol)
    check = GtkCheckButton()
    set_gtk_property!(check, :label, field)
    set_gtk_property!(check, :active, value)
    return new(check)
  end
end
RecoPlanParameterInput(value::Missing, field) = BoolPlanInput(false, field)
RecoPlanParameterInput(value::Bool, field) = BoolPlanInput(value, field)
widget(input::BoolPlanInput) = input.widget
value(input::BoolPlanInput) = get_gtk_property(input.widget, :active, Bool)
update!(input::BoolPlanInput, value::Bool) = set_gtk_property!(input.widget, :active, value)

struct RecoPlanParameter{T} 
  plan::RecoPlan
  field::Symbol
  input::RecoPlanParameterInput
  RecoPlanParameter(plan::RecoPlan, field::Symbol, input::RecoPlanParameterInput) = new{type(plan, field)}(plan, field, input)
end

function RecoPlanParameter(plan::RecoPlan{T}, field::Symbol) where {T<:AbstractReconstructionAlgorithmParameter}
  input = RecoPlanParameterInput(plan, field)
  parameter = RecoPlanParameter(plan, field, input)
  addListener!(plan, field, GtkPlanListener(parameter))
  return parameter
end

struct GtkPlanListener <: TransientListener
  parameter::RecoPlanParameter
end
AbstractImageReconstruction.valueupdate(listener::GtkPlanListener, origin, field, old, new) = update!(listener.parameter.input, new)