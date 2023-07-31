abstract type RecoPlanParameterInput end
widget(input::RecoPlanParameterInput) = error("$(typeof(input)) must implement method widget")
value(input::RecoPlanParameterInput) = error("$(typeof(input)) must implement method value")
update!(input::RecoPlanParameterInput, value) = error("$(typeof(input)) must implement method update!")
callback!(input::RecoPlanParameterInput, value) = error("$(typeof(input)) must implement method callback!")
RecoPlanParameterInput(plan::RecoPlan, field::Symbol) = RecoPlanParameterInput(type(plan, field), plan[field], field)

mutable struct BoolPlanInput <: RecoPlanParameterInput
  widget::Gtk4.GtkCheckButton
  cb::Union{Nothing, Function}
  activeCb::Bool
  function BoolPlanInput(value::Bool, field::Symbol)
    check = GtkCheckButton()
    set_gtk_property!(check, :label, field)
    set_gtk_property!(check, :active, value)
    input = new(check, nothing, true)
    signal_connect(check, :toggled) do w
      set_gtk_property!(check, :inconsistent, false)
      if !isnothing(input.cb) && input.activeCb
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
    input.activeCb = false
    set_gtk_property!(input.widget, :active, value)
    set_gtk_property!(input.widget, :inconsistent, false)
    input.activeCb = true
  end
end
function update!(input::BoolPlanInput, value::Missing)
  @idle_add_guarded begin
    input.activeCb = false
    set_gtk_property!(input.widget, :inconsistent, true)
    input.activeCb = true
  end
end
callback!(input::BoolPlanInput, value) = input.cb = value 

struct RecoPlanParameter{T, I<:RecoPlanParameterInput} 
  plan::RecoPlan
  field::Symbol
  input::I
  RecoPlanParameter(plan::RecoPlan, field::Symbol, input::I) where {I<:RecoPlanParameterInput} = new{type(plan, field), I}(plan, field, input)
end

function RecoPlanParameter(plan::RecoPlan{T}, field::Symbol) where {T<:AbstractReconstructionAlgorithmParameter}
  input = RecoPlanParameterInput(plan, field)
  parameter = RecoPlanParameter(plan, field, input)
  addListener!(plan, field, GtkPlanListener(parameter))
  callback!(input, () -> update!(parameter))
  return parameter
end

function update!(parameter::RecoPlanParameter)
  parameter.plan[parameter.field] = value(parameter.input)
end
struct GtkPlanListener <: TransientListener
  parameter::RecoPlanParameter
end
function AbstractImageReconstruction.valueupdate(listener::GtkPlanListener, origin, field, old, new)
  update!(listener.parameter.input, new)
end