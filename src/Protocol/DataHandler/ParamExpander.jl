mutable struct ParamExpander <: Gtk.GtkExpander
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  handler::AbstractDataHandler
  param::GtkBox
end

getindex(m::ParamExpander, w::AbstractString, T::Type) = object_(m.builder, w, T)

function ParamExpander(handler::AbstractDataHandler)
  title = getParameterTitle(handler)
  widget = getParameterWidget(handler)
  uifile = joinpath(@__DIR__,"..","..","builder","dataHandlerParams.ui")
  b = Builder(filename=uifile)
  expander = object_(b, "expander", Expander)
  # TODO Make title bold
  set_gtk_property!(expander, :label, title)
  paramExpander = ParamExpander(expander.handle, b, handler, widget)
  Gtk.gobject_move_ref(paramExpander, expander)
  push!(paramExpander["boxParams", GtkBox], widget)
  signal_connect(paramExpander["switchEnable", Gtk.GtkSwitch], :state_set) do w, state
    enable!(paramExpander.handler, state)
    return false
  end
  return paramExpander
end

function enable!(param::ParamExpander, val::Bool)
  @idle_add_guarded begin
    set_gtk_property!(param["switchEnable", Gtk.GtkSwitch], :active, val)
  end
end