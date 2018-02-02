using Cairo, Gtk.ShortNames, Colors

using Graphics


function Base.copy!{C<:Union{Colorant,Number}}(ctx::CairoContext, img::AbstractArray{C})
    Cairo.save(ctx)
    Cairo.reset_transform(ctx)
    image(ctx, image_surface(img), 0, 0, width(ctx), height(ctx))
    restore(ctx)
end
Base.copy!(c::Canvas, img) = copy!(getgc(c), img)
function Base.fill!(c::Canvas, color::Colorant)
    ctx = getgc(c)
    w, h = width(c), height(c)
    rectangle(ctx, 0, 0, w, h)
    set_source(ctx, color)
    fill(ctx)
end

image_surface(img::Matrix{Gray24}) = CairoImageSurface(reinterpret(UInt32, img), Cairo.FORMAT_RGB24)
image_surface(img::Matrix{RGB24})  = CairoImageSurface(reinterpret(UInt32, img), Cairo.FORMAT_RGB24)
image_surface(img::Matrix{ARGB32}) = CairoImageSurface(reinterpret(UInt32, img), Cairo.FORMAT_ARGB32)

image_surface{T<:Number}(img::AbstractArray{T}) = image_surface(convert(Matrix{Gray24}, img))
image_surface{C<:Color}(img::AbstractArray{C}) = image_surface(convert(Matrix{RGB24}, img))
image_surface{C<:Colorant}(img::AbstractArray{C}) = image_surface(convert(Matrix{ARGB32}, img))
