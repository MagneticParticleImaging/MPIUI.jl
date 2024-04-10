mutable struct ParamExpander <: Gtk4.GtkExpander
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  handler::AbstractDataHandler
  param::GtkBox
end

getindex(m::ParamExpander, w::AbstractString) = G_.get_object(m.builder, w)

function ParamExpander(handler::AbstractDataHandler)
  title = getParameterTitle(handler)
  widget = getParameterWidget(handler)
  if isnothing(widget)
    widget = GtkBox(:v)
  end
  uifile = joinpath(@__DIR__,"..","..","builder","dataHandlerParams.ui")
  b = GtkBuilder(uifile)
  expander = G_.get_object(b, "expander")
  # TODO Make title bold
  set_gtk_property!(expander, :label, title)
  paramExpander = ParamExpander(expander.handle, b, handler, widget)
  Gtk4.GLib.gobject_move_ref(paramExpander, expander)
  push!(paramExpander["boxParams"], widget)
  signal_connect(paramExpander["switchEnable"], :state_set) do w, state
    enable!(paramExpander.handler, state)
    return false
  end
  return paramExpander
end

function enable!(param::ParamExpander, val::Bool)
  @idle_add_guarded begin
    enable!(param.handler, val) # Why is this needed???? For some reason the next setter does not fire always
    set_gtk_property!(param["switchEnable"], :active, val)
  end
end