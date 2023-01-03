using Gtk4, Cairo

export SimpleDataViewer, SimpleDataViewerWidget, simpleDrawImageCairo

function SimpleDataViewer()
  w = Window("Data Viewer",1024,768)
  dw = SimpleDataViewerWidget()
  push!(w,dw)
  show(w)
  return dw, w
end

########### SimpleDataViewerWidget #################


mutable struct SimpleDataViewerWidget <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder
  grid3D
  grid2D
end

getindex(m::SimpleDataViewerWidget, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)


function SimpleDataViewerWidget()
  uifile = joinpath(@__DIR__,"..","builder","simpleDataViewer.ui")
  b = GtkBuilder(filename=uifile)
  mainBox = Gtk4.G_.get_object(b, "boxSimpleDataViewer")
  m = SimpleDataViewerWidget( mainBox.handle, b, nothing, nothing)
  Gtk4.GLib.gobject_move_ref(m, mainBox)

  m.grid3D = m["gridDataViewer3D"]
  m.grid2D = m["gridDataViewer2D"]

  m.grid3D[2,1] = GtkCanvas()
  m.grid3D[1,1] = GtkCanvas()
  m.grid3D[2,2] = GtkCanvas()
  m.grid3D[1,2] = GtkCanvas()
  m.grid2D[1,1] = GtkCanvas()

  return m
end

function showData(m::SimpleDataViewerWidget, cdata_zy, cdata_zx, cdata_xy, drawSectionalLines, slices)
  try
    simpleDrawImageCairo(m.grid3D[2,1], cdata_zy, drawSectionalLines,
                   slices[2], slices[3], false, true)
    simpleDrawImageCairo(m.grid3D[1,1], cdata_zx, drawSectionalLines,
                   slices[1], slices[3], true, true)
    simpleDrawImageCairo(m.grid3D[2,2], cdata_xy, drawSectionalLines,
                   slices[2], slices[1], false, false)

    Gtk4.G_.set_current_page(m["nb2D3D"], 0)
  catch ex
    @warn "Exception" ex stacktrace(catch_backtrace())
  end
end

function showData(m::SimpleDataViewerWidget, cdata)
  try
    pZ = drawImage( convert(Array,cdata.data) )
    display(m.grid2D[1,1],pZ)
    Gtk4.G_.set_current_page(m["nb2D3D"], 1)
  catch ex
    @warn "Exception" ex stacktrace(catch_backtrace())
  end
end

function simpleDrawImageCairo(c, image, drawSectionalLines, xsec, ysec,
                        flipX, flipY)
 @guarded Gtk4.draw(c) do widget
  ctx = getgc(c)
  h = height(ctx)
  w = width(ctx)

  im = reverse(convert(ImageMeta{RGB{N0f8}},image).data,dims=1)
  xsec_ = !flipX ? xsec : (size(im,2)-xsec+1)
  ysec_ = !flipY ? ysec : (size(im,1)-ysec+1)
  xx = w*(xsec_-0.5)/size(im,2)
  yy = h*(ysec_-0.5)/size(im,1)
  copy!(ctx,im)
  if drawSectionalLines
    set_source_rgb(ctx, 0, 1, 0)
    move_to(ctx, xx, 0)
    line_to(ctx, xx, h)
    move_to(ctx, 0, yy)
    line_to(ctx, w, yy)
    set_line_width(ctx, 3.0)
    Cairo.stroke(ctx)
  end # end if
 end # guard
end # end function
