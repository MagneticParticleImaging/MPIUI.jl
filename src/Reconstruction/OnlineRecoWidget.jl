


mutable struct OnlineRecoWidget <: Gtk.GtkExpander
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  field::Symbol
  params::ReconstructionParameter
  onlineReco::CheckButton


  function OnlineRecoWidget(field::Symbol, params=defaultRecoParams()) #, value::Sequence, scanner::MPIScanner)
    uifile = joinpath(@__DIR__, "..", "builder", "reconstructionParams.ui")
    b = Builder(filename=uifile)
  
    box = Box(:v)
 
    exp = Expander(box, "Reconstruction")
    #push!(exp, recoParams)
    cbOnlineReco = CheckButton("Online Recconstruction")
    set_gtk_property!(cbOnlineReco, :active, false)
    recoParams = ReconstructionParameter(params) 
    push!(box, cbOnlineReco)
    push!(box, recoParams)

    #addTooltip(object_(pw.builder, "lblSequence", GtkLabel), tooltip)
    m = new(exp.handle, b, field, recoParams, cbOnlineReco) 
    Gtk.gobject_move_ref(m, exp)

    signal_connect(cbOnlineReco, "toggled") do widget
      value = get_gtk_property(cbOnlineReco, :active, Bool)
      @idle_add_guarded begin

      end
    end

    initCallbacks(m)
    return m
  end
  
end

getindex(m::OnlineRecoWidget, w::AbstractString) = G_.object(m.builder, w)


function initCallbacks(m::OnlineRecoWidget)

end