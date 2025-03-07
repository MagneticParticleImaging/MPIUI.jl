using Cairo, Colors

using Graphics


mutable struct MakieCanvas#  <: Gtk4Widget # Is not recognized as a GtkWidget for some reason
    handle::Ptr{Gtk4.GObject}
    canvas::GtkCanvas
    fig::CairoMakie.Figure
    function MakieCanvas()
        canvas = GtkCanvas()
        figure = CairoMakie.Figure()
        mc = new(canvas.handle, canvas, figure)
        #Gtk4.GLib.gobject_move_ref(mc, canvas)
        return mc
    end
end

function MakieCanvas(fig::CairoMakie.Figure)
    mc = MakieCanvas()
    drawonto(mc, fig)
    return mc
end
function drawonto(canvas::MakieCanvas, figure::CairoMakie.Figure)
    canvas.fig = figure
    drawonto(canvas[], canvas.fig)
end
Base.getindex(canvas::MakieCanvas) = canvas.canvas
Gtk4.draw(f, canvas::MakieCanvas) = draw(f, canvas[])
Gtk4.draw(canvas::MakieCanvas) = draw(canvas[])
Gtk4.getgc(canvas::MakieCanvas) = getgc(canvas[])

function Base.copy!(ctx::CairoContext, img::AbstractArray{C}) where C<:Union{Colorant,Number}
    Cairo.save(ctx)
    Cairo.reset_transform(ctx)
    image(ctx, image_surface(img), 0, 0, width(ctx), height(ctx))
    restore(ctx)
end
Base.copy!(c::GtkCanvas, img) = copy!(getgc(c), img)
function Base.fill!(c::GtkCanvas, color::Colorant)
    ctx = getgc(c)
    w, h = width(c), height(c)
    rectangle(ctx, 0, 0, w, h)
    set_source(ctx, color)
    fill(ctx)
end

image_surface(img::Matrix{Gray24}) = CairoImageSurface(copy(reinterpret(UInt32, img)), Cairo.FORMAT_RGB24)
image_surface(img::Matrix{RGB24})  = CairoImageSurface(copy(reinterpret(UInt32, img)), Cairo.FORMAT_RGB24)
image_surface(img::Matrix{ARGB32}) = CairoImageSurface(copy(reinterpret(UInt32, img)), Cairo.FORMAT_ARGB32)

image_surface(img::AbstractArray{T}) where {T<:Number} = image_surface(convert(Matrix{Gray24}, img))
image_surface(img::AbstractArray{C}) where {C<:Color} = image_surface(convert(Matrix{RGB24}, img))
image_surface(img::AbstractArray{C}) where {C<:Colorant} = image_surface(convert(Matrix{ARGB32}, img))


function drawonto(canvas, figure)
  CairoMakie.activate!(px_per_unit=3, pt_per_unit=3) 
  @guarded draw(canvas) do _
      scene = figure.scene
      CairoMakie.resize!(scene, Gtk4.width(canvas), Gtk4.height(canvas))
      config = CairoMakie.ScreenConfig(1.0, 1.0, :good, true, false, nothing)
      screen = CairoMakie.Screen(scene, config, Gtk4.cairo_surface(canvas))
      CairoMakie.cairo_draw(screen, scene)
  end
end