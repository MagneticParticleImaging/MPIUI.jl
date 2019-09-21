

function getMetaDataSlices(m::DataViewerWidget)
  ctxZY = Gtk.getgc(m.grid3D[2,1])
  ctxZX = Gtk.getgc(m.grid3D[1,1])
  ctxXY = Gtk.getgc(m.grid3D[2,2])
  hZY = height(ctxZY)
  wZY = width(ctxZY)
  hZX = height(ctxZX)
  wZX = width(ctxZX)
  hXY = height(ctxXY)
  wXY = width(ctxXY)
  return ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY
end

function getImSizes(cdata_zy,cdata_zx,cdata_xy)
  imSizeZY = [size(cdata_zy)...]#flipdim([size(cdata_zy)...],1)
  imSizeZX = [size(cdata_zx)...]#flipdim([size(cdata_zx)...],1)
  imSizeXY = [size(cdata_xy)...]#flipdim([size(cdata_xy)...],1)
  return imSizeZY,imSizeZX,imSizeXY
end


function cacheSelectedFovXYZPos(m::DataViewerWidget, cachePos::Array{Float64,1}, pixelSpacingBG, sizeBG, hX,wY,hZ)
  m.cacheSelectedFovXYZ = cachePos
  screenXYZtoBackgroundXYZ = (cachePos .-[hX/2,wY/2,hZ/2]) .* (sizeBG ./ [hX,wY,hZ])
  m.cacheSelectedMovePos = screenXYZtoBackgroundXYZ .* pixelSpacingBG
  @debug "" cachePos screenXYZtoBackgroundXYZ m.cacheSelectedMovePos
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

function getSliceSizes(fov_mm, pixelSpacing)
  fov_vox = fov_mm ./ pixelSpacing
  xy = [fov_vox[2],fov_vox[1]]
  xz = [fov_vox[1],fov_vox[3]]
  yz = [fov_vox[2],fov_vox[3]]
  return xy,xz,yz
end


function calcDFFovRectangle(m::DataViewerWidget, trans::Vector, pixelSpacingBG::Vector)
  dfFov = getDFFov(m.currentlyShownData[1])
  xy,xz,yz = getSliceSizes(dfFov, pixelSpacingBG)
  @debug "" dfFov xy xz yz
  offsetxy = ([trans[2], trans[1]])./([pixelSpacingBG[2],pixelSpacingBG[1]])
  offsetxz = ([-trans[1], -trans[3]])./([pixelSpacingBG[1],pixelSpacingBG[3]])
  offsetyz = ([trans[2], -trans[3]])./([pixelSpacingBG[2],pixelSpacingBG[3]])
  return xy,xz,yz,offsetxy,offsetxz,offsetyz
end

function getDFFov(im::ImageMeta)
  props = properties(im)
  if haskey(props, "dfStrength") && haskey(props, "acqGradient")
    dfS = squeeze(props["dfStrength"])
    acqGrad = squeeze(props["acqGradient"])
    acqGrad_ = zeros(size(acqGrad,2),size(acqGrad,3))
    for k=1:size(acqGrad,3)
        acqGrad_[:,k]=diag(acqGrad[:,:,k])
    end
    dfFov = abs.(2*(dfS./acqGrad_))
  else
    dfFov = [0.05,0.05,0.025] # use better default...
    #warn("using default dfFov: ",dfFov)
  end
  return dfFov
end

function drawImages(m::DataViewerWidget,slices,isDrawSectionalLines,isDrawRectangle,
                    cdata_zx, cdata_zy, cdata_xy, trans, pixelSpacingBG, sizeBG)
   
  xy,zx,zy,offsetxy,offsetzx,offsetzy = calcDFFovRectangle(m, trans, pixelSpacingBG)
   
  drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)

  m.grid3D[1,1].mouse.button3press = @guarded (widget, event) -> begin
    @guarded Gtk.draw(widget) do widget
      if isDrawRectangle
        @debug "mouse event ZX"
        ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
        reveal(widget)
        pZX = [event.x, event.y]
        ZXtoXYforX = (wZX-pZX[1])/wZX *hXY # X coord in ZX width direction and in XY in height direction
        cacheSelectedFovXYZPos(m, [ZXtoXYforX,m.cacheSelectedFovXYZ[2], pZX[2]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
        @debug "cacheSelectedFovXYZ" m.cacheSelectedFovXYZ
        pZY = [m.cacheSelectedFovXYZ[2], pZX[2]]
        pXY = [m.cacheSelectedFovXYZ[2], ZXtoXYforX]
        imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
        @debug "" pZX zx offsetzy imSizeZY
        drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
        drawRectangle(ctxZY, hZY,wZY, pZY, imSizeZY, zy, offsetzy, rgb=[1,0,0],lineWidth=3.0)
        drawRectangle(ctxZX, hZX,wZX, pZX, imSizeZX, zx, offsetzx, rgb=[1,0,0],lineWidth=3.0)
        drawRectangle(ctxXY, hXY,wXY, pXY, imSizeXY, xy, offsetxy, rgb=[1,0,0],lineWidth=3.0)
      end
    end
  end
  m.grid3D[2,1].mouse.button3press = @guarded (widget, event) -> begin
   @guarded Gtk.draw(widget) do widget
     if isDrawRectangle
       @debug "mouse event ZY"
       ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
       reveal(widget)
       pZY = [event.x, event.y]
       cacheSelectedFovXYZPos(m, [m.cacheSelectedFovXYZ[1],pZY[1], pZY[2]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
       @debug "" m.cacheSelectedFovXYZ
       XYtoZXforX = wZX-(m.cacheSelectedFovXYZ[1]/hXY *wZX) # X coord in ZX width direction and in XY in height direction
       pZX = [XYtoZXforX, pZY[2]]
       pXY = [pZY[1],m.cacheSelectedFovXYZ[1]]
       imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
       @debug "" pZY zy offsetzy imSizeZY
       drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
       drawRectangle(ctxZY, hZY,wZY, pZY, imSizeZY, zy, offsetzy, rgb=[1,0,0],lineWidth=3.0)
       drawRectangle(ctxZX, hZX,wZX, pZX, imSizeZX, zx, offsetzx, rgb=[1,0,0],lineWidth=3.0)
       drawRectangle(ctxXY, hXY,wXY, pXY, imSizeXY, xy, offsetxy, rgb=[1,0,0],lineWidth=3.0)
     end
   end
 end
 m.grid3D[2,2].mouse.button3press = @guarded (widget, event) -> begin
   @guarded Gtk.draw(widget) do widget
     if isDrawRectangle
       @debug "mouse event XY"
       ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
       reveal(widget)
       pXY = [event.x, event.y]
       XYtoZXforX = wZX-(pXY[2]/hXY *wZX) # X coord in ZX width direction and in XY in height direction
       cacheSelectedFovXYZPos(m, [pXY[2],pXY[1],m.cacheSelectedFovXYZ[3]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
       @debug "" m.cacheSelectedFovXYZ
       pZY = [pXY[1],m.cacheSelectedFovXYZ[3]]
       pZX = [XYtoZXforX, m.cacheSelectedFovXYZ[3]]
       imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
       @debug pXY xy offsetzy imSizeZY
       drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
       drawRectangle(ctxZY, hZY,wZY, pZY, imSizeZY, zy, offsetzy, rgb=[1,0,0],lineWidth=3.0)
       drawRectangle(ctxZX, hZX,wZX, pZX, imSizeZX, zx, offsetzx, rgb=[1,0,0],lineWidth=3.0)
       drawRectangle(ctxXY, hXY,wXY, pXY, imSizeXY, xy, offsetxy, rgb=[1,0,0],lineWidth=3.0)
     end
    end
  end
  return nothing
end

function drawSlice(m::DataViewerWidget,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
  drawImageCairo(m.grid3D[2,1], cdata_zy, isDrawSectionalLines,
                 slices[2], slices[3], false, true, m["adjSliceY"], m["adjSliceZ"], isDrawRectangle,zy, offsetzy)
  drawImageCairo(m.grid3D[1,1], cdata_zx, isDrawSectionalLines,
                 slices[1], slices[3], true, true, m["adjSliceX"], m["adjSliceZ"], isDrawRectangle,zx, offsetzx)
  drawImageCairo(m.grid3D[2,2], cdata_xy, isDrawSectionalLines,
                 slices[2], slices[1], false, false, m["adjSliceY"], m["adjSliceX"], isDrawRectangle,xy, offsetxy)
end

function drawImageCairo(c, image, isDrawSectionalLines, xsec, ysec,
                        flipX, flipY, adjX, adjY, isDrawRectangle, xy, xyOffset)
 @guarded Gtk.draw(c) do widget
  #c = reshape(c,size(c,1), size(c,2))
  ctx = getgc(c)
  h = height(ctx)
  w = width(ctx)

  im = copy(reverse(convert(ImageMeta{RGB{N0f8}},image).data,dims=1))
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


### Profile Plotting ###


function showProfile(m::DataViewerWidget, params, slicesInRawData)
  chan = params[:activeChannel]
  prof = get_gtk_property(m["cbProfile"],:active, Int64) + 1
  if prof == 1
    m.currentProfile = vec(m.data[chan][:,slicesInRawData[2],slicesInRawData[3],params[:frame]])
  elseif prof == 2
    m.currentProfile = vec(m.data[chan][slicesInRawData[1],:,slicesInRawData[3],params[:frame]])
  elseif prof == 3
    m.currentProfile = vec(m.data[chan][slicesInRawData[1],slicesInRawData[2],:,params[:frame]])
  else
    m.currentProfile = vec(m.data[chan][slicesInRawData[1],slicesInRawData[2],slicesInRawData[3],:])
  end
  showWinstonPlot(m, m.currentProfile, "c", "xyzt")
end

function showWinstonPlot(m::DataViewerWidget, data, xLabel::String, yLabel::String)
  p = Winston.FramedPlot(xlabel=xLabel, ylabel=yLabel)
  Winston.add(p, Winston.Curve(1:length(data), data, color="blue", linewidth=4))
  display(m.grid3D[1,2], p)
end

