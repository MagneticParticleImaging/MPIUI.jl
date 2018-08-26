using Gtk, Gtk.ShortNames, Cairo

export baseViewer, baseViewerStandAlone, updateView, drawMIP

mutable struct BaseViewerWidget
  builder
  zxSliceGrid
  zySliceGrid
  yxSliceGrid
end


function baseViewerStandAlone()
  w = Window("Base Viewer",800,600)
  set_gtk_property!(w,:hexpand,true)
  set_gtk_property!(w,:vexpand,true)
  m, bv = baseViewer()
  push!(w, bv)
  showall(w)
  return w,m,bv
end

getindex(m::BaseViewerWidget, w::AbstractString) = G_.object(m.builder, w)

function baseViewer()
  uifile = joinpath(@__DIR__,"builder","baseViewer.ui")
  b = Builder(filename=uifile)
  m = BaseViewerWidget(b, nothing,nothing,nothing)
  w = m["parentGrid"]
  m.zxSliceGrid = m["zxSlice"]
  m.zySliceGrid = m["zySlice"]
  m.yxSliceGrid = m["yxSlice"]
  m.zxSliceGrid[1,1] = Canvas()
  m.zySliceGrid[1,1] = Canvas()
  m.yxSliceGrid[1,1] = Canvas()



  return m, w
end

function updateView(m::BaseViewerWidget,zx,zy,yx)
  drawMIP(m.zxSliceGrid[1,1],m.zySliceGrid[1,1],m.yxSliceGrid[1,1],zx,zy,yx)
end

function drawMIP(controlzx,controlzy,controlyx,zx,zy,yx)
  drawSlice(controlzx, zx)
  drawSlice(controlzy, zy)
  drawSlice(controlyx, yx)
end

function drawSlice(control, slice)
  @guarded Gtk.draw(control) do widget
      ctx = getgc(control)
      copy!(ctx, slice)
  end
end
