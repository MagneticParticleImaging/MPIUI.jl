

function showWinstonPlot(m::DataViewerWidget, data, xLabel::String, yLabel::String)
  p = Winston.FramedPlot(xlabel=xLabel, ylabel=yLabel)
  Winston.add(p, Winston.Curve(1:length(data), data, color="blue", linewidth=4))
  display(m.w.gridDataViewer3D[1,2], p)
end

function drawImageCairo(c, image, isDrawSectionalLines, xsec, ysec,
                        flipX, flipY, adjX, adjY, isDrawRectangle, xy, xyOffset)
 @guarded Gtk.draw(c) do widget
  #c = reshape(c,size(c,1), size(c,2))
  ctx = getgc(c)
  h = height(ctx)
  w = width(ctx)

  im = copy(reverse(convert(ImageMeta{RGB{N0f8}},image),dims=1))
  xsec_ = !flipX ? xsec : (size(im,2)-xsec+1)
  ysec_ = !flipY ? ysec : (size(im,1)-ysec+1)
  xx = w*(xsec_-0.5)/size(im,2)
  yy = h*(ysec_-0.5)/size(im,1)
  copy!(ctx,im)

  if isDrawSectionalLines
    set_source_rgb(ctx, 0, 1, 0)
    move_to(ctx, xx, 0)
    line_to(ctx, xx, h)
    move_to(ctx, 0, yy)
    line_to(ctx, w, yy)
    #set_line_width(ctx, 3.0)
    # Cairo.stroke(ctx)
   end
  imSize = size(im)
  if isDrawRectangle
    @debug "" imSize
    drawRectangle(ctx,h,w,[w/2,h/2], imSize, xy, xyOffset)
  end
  if isDrawSectionalLines || isDrawRectangle
    set_line_width(ctx, 3.0)
    Cairo.stroke(ctx)
  end
 end

 c.mouse.button1press = @guarded (widget, event) -> begin
  if isDrawSectionalLines
   ctx = getgc(widget)
   reveal(widget)
   h = height(ctx)
   w = width(ctx)
   xx = event.x / w*size(image,2) + 0.5
   yy = event.y / h*size(image,1) + 0.5
   xx = !flipX ? xx : (size(image,2)-xx+1)
   yy = !flipY ? yy : (size(image,1)-yy+1)
   Gtk.@sigatom set_gtk_property!(adjX, :value, round(Int64,xx))
   Gtk.@sigatom set_gtk_property!(adjY, :value, round(Int64,yy))
  end
 end
end



function drawRectangle(ctx,h,w, p, imSize, xy, xyOffset;rgb=[0,1,0], lineWidth=3.0)
  sFac = calcMeta(h,w, imSize)
  set_source_rgb(ctx, rgb...)
  createRectangle(ctx, p, sFac, xy, xyOffset)
  set_line_width(ctx, lineWidth)
  Cairo.stroke(ctx)
end

function calcMeta(h,w,imSize)
  cDA = [w/2,h/2]
  cIA = [imSize[2]/2,imSize[1]/2]
  sFac = cDA ./ cIA
  @debug "" cIA sFac
  return sFac
end

function createRectangle(ctx, cDA, sFac, xy, xyOffset)
  lowCX = cDA[1] - sFac[1] * xy[1]/2 + sFac[1] * xyOffset[1]
  lowCY= cDA[2] - sFac[2] * xy[2]/2 + sFac[2] * xyOffset[2]
  highCX =lowCX + sFac[1]*xy[1]
  highCY =lowCY + sFac[2]*xy[2]
  @debug "" lowCX lowCY highCX highCY
  move_to(ctx, lowCX, lowCY)
  line_to(ctx, highCX, lowCY)
  move_to(ctx, lowCX, lowCY)
  line_to(ctx, lowCX, highCY)
  move_to(ctx, highCX, lowCY)
  line_to(ctx, highCX, highCY)
  move_to(ctx, lowCX, highCY)
  line_to(ctx, highCX, highCY)
end

