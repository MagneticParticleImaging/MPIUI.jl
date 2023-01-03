

function getMetaDataSlices(m::DataViewerWidget)
  ctxZY = Gtk4.getgc(m.grid3D[2,1])
  ctxZX = Gtk4.getgc(m.grid3D[1,1])
  ctxXY = Gtk4.getgc(m.grid3D[2,2])
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
  dfFov = getDFFov(m.currentlyShownData)
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

function drawImages(m::DataViewerWidget,slices,isDrawSectionalLines,isDrawRectangle,isDrawAxes,
                    cdata_zx, cdata_zy, cdata_xy, trans, pixelSpacingBG, sizeBG)
   
  xy,zx,zy,offsetxy,offsetzx,offsetzy = calcDFFovRectangle(m, trans, pixelSpacingBG)
   
  drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle,isDrawAxes, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)


  g1 = GtkGestureClick(m.grid3D[1,1],3)
  signal_connect(g1, "pressed") do controller, n_press, x, y
    w = widget(controller)
    @guarded Gtk4.draw(w) do widget
      if isDrawRectangle
        @debug "mouse event ZX"
        ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
        reveal(widget)
        pZX = [x, y]
        ZXtoXYforX = (wZX-pZX[1])/wZX *hXY # X coord in ZX width direction and in XY in height direction
        cacheSelectedFovXYZPos(m, [ZXtoXYforX,m.cacheSelectedFovXYZ[2], pZX[2]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
        @debug "cacheSelectedFovXYZ" m.cacheSelectedFovXYZ
        pZY = [m.cacheSelectedFovXYZ[2], pZX[2]]
        pXY = [m.cacheSelectedFovXYZ[2], ZXtoXYforX]
        imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
        @debug "" pZX zx offsetzy imSizeZY
        drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle,isDrawAxes, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
        drawRectangle(ctxZY, hZY,wZY, pZY, imSizeZY, zy, offsetzy, rgb=[1,0,0],lineWidth=3.0)
        drawRectangle(ctxZX, hZX,wZX, pZX, imSizeZX, zx, offsetzx, rgb=[1,0,0],lineWidth=3.0)
        drawRectangle(ctxXY, hXY,wXY, pXY, imSizeXY, xy, offsetxy, rgb=[1,0,0],lineWidth=3.0)
      end
    end
  end
  g2 = GtkGestureClick(m.grid3D[2,1],3)
  signal_connect(g2, "pressed") do controller, n_press, x, y
    w = widget(controller)
   @guarded Gtk4.draw(w) do widget
     if isDrawRectangle
       @debug "mouse event ZY"
       ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
       reveal(widget)
       pZY = [x, y]
       cacheSelectedFovXYZPos(m, [m.cacheSelectedFovXYZ[1],pZY[1], pZY[2]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
       @debug "" m.cacheSelectedFovXYZ
       XYtoZXforX = wZX-(m.cacheSelectedFovXYZ[1]/hXY *wZX) # X coord in ZX width direction and in XY in height direction
       pZX = [XYtoZXforX, pZY[2]]
       pXY = [pZY[1],m.cacheSelectedFovXYZ[1]]
       imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
       @debug "" pZY zy offsetzy imSizeZY
       drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle,isDrawAxes, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
       drawRectangle(ctxZY, hZY,wZY, pZY, imSizeZY, zy, offsetzy, rgb=[1,0,0],lineWidth=3.0)
       drawRectangle(ctxZX, hZX,wZX, pZX, imSizeZX, zx, offsetzx, rgb=[1,0,0],lineWidth=3.0)
       drawRectangle(ctxXY, hXY,wXY, pXY, imSizeXY, xy, offsetxy, rgb=[1,0,0],lineWidth=3.0)
     end
   end
 end
 g3 = GtkGestureClick(m.grid3D[2,2],3)
 signal_connect(g3, "pressed") do controller, n_press, x, y
  w = widget(controller)
   @guarded Gtk4.draw(w) do widget
     if isDrawRectangle
       @debug "mouse event XY"
       ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
       reveal(widget)
       pXY = [x, y]
       XYtoZXforX = wZX-(pXY[2]/hXY *wZX) # X coord in ZX width direction and in XY in height direction
       cacheSelectedFovXYZPos(m, [pXY[2],pXY[1],m.cacheSelectedFovXYZ[3]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
       @debug "" m.cacheSelectedFovXYZ
       pZY = [pXY[1],m.cacheSelectedFovXYZ[3]]
       pZX = [XYtoZXforX, m.cacheSelectedFovXYZ[3]]
       imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
       @debug pXY xy offsetzy imSizeZY
       drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle,isDrawAxes, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
       drawRectangle(ctxZY, hZY,wZY, pZY, imSizeZY, zy, offsetzy, rgb=[1,0,0],lineWidth=3.0)
       drawRectangle(ctxZX, hZX,wZX, pZX, imSizeZX, zx, offsetzx, rgb=[1,0,0],lineWidth=3.0)
       drawRectangle(ctxXY, hXY,wXY, pXY, imSizeXY, xy, offsetxy, rgb=[1,0,0],lineWidth=3.0)
     end
    end
  end
  
  return nothing
end

function drawSlice(m::DataViewerWidget,slices,isDrawSectionalLines,isDrawRectangle,isDrawAxes, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
  drawImageCairo(m.grid3D[2,1], cdata_zy, isDrawSectionalLines, isDrawAxes,
                 slices[2], slices[3], false, true, m["adjSliceY"], m["adjSliceZ"], isDrawRectangle,zy, offsetzy, "yz")
  drawImageCairo(m.grid3D[1,1], cdata_zx, isDrawSectionalLines, isDrawAxes,
                 slices[1], slices[3], true, true, m["adjSliceX"], m["adjSliceZ"], isDrawRectangle,zx, offsetzx, "xz")
  drawImageCairo(m.grid3D[2,2], cdata_xy, isDrawSectionalLines, isDrawAxes,
                 slices[2], slices[1], false, false, m["adjSliceY"], m["adjSliceX"], isDrawRectangle,xy, offsetxy, "xy")
end

function drawImageCairo(c, image, isDrawSectionalLines, isDrawAxes, xsec, ysec,
                        flipX, flipY, adjX, adjY, isDrawRectangle, xy, xyOffset, slide)
 @guarded Gtk4.draw(c) do widget
  #c = reshape(c,size(c,1), size(c,2))
  ctx = getgc(c)
  h = height(ctx)
  w = width(ctx)

  im = copy(reverse(arraydata(convert(ImageMeta{RGB{N0f8}},image)),dims=1))
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
  if isDrawAxes
    drawAxes(ctx,slide)
    set_line_width(ctx, 3.0)
    Cairo.stroke(ctx)
  end
 end

  g = GtkGestureClick(c,1)
  signal_connect(g, "pressed") do controller, n_press, x, y
    w = widget(controller)
    ctx = getgc(w)
    reveal(w)
    h = height(ctx)
    w = width(ctx)
    xx = x / w*size(image,2) + 0.5
    yy = y / h*size(image,1) + 0.5
    xx = !flipX ? xx : (size(image,2)-xx+1)
    yy = !flipY ? yy : (size(image,1)-yy+1)
    @idle_add_guarded set_gtk_property!(adjX, :value, round(Int64,xx))
    @idle_add_guarded set_gtk_property!(adjY, :value, round(Int64,yy))
  end

end

## Draw coordinate system
function drawAxes(ctx,slide; rgb=[1,1,1])
    h = height(ctx)
    w = width(ctx)

    center = h/40
    if slide == "xy"
      posx = center
      posy = center
      tox = [h/4, posy]
      toy = [posx, h/4]
      si = [-1,-1]
      la = ["y","x"]
    elseif slide == "xz"
      posx = w-center
      posy = h-center
      tox = [posx-h/4, posy]
      toy = [posx, posy-h/4]
      si = [1, 1]
      la = ["x","z"]
    else # slide == "yz"
      posx = center
      posy = h-center
      tox = [h/4, posy]
      toy = [posx, posy-h/4]
      si = [-1, 1]
      la = ["y","z"]
    end

    set_source_rgb(ctx, rgb...)
    select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL,
                     Cairo.FONT_WEIGHT_BOLD);
    set_font_size(ctx, h/20);
    scale = h/64
    # x-axis
    move_to(ctx, posx, posy)
    line_to(ctx, tox[1], tox[2])
    rel_move_to(ctx, si[1]*(2*scale), -scale)
    line_to(ctx, tox[1], tox[2])
    rel_line_to(ctx, si[1]*(2*scale), scale)
    # xlabel
    extents = text_extents(ctx, la[1])
    move_to(ctx, tox[1] - (extents[3]/2 + extents[1]) - si[1]*(2*scale), tox[2]-(extents[4]/2 + extents[2]))
    show_text(ctx,la[1])
    # y-axis
    move_to(ctx, posx, posy)
    line_to(ctx, toy[1], toy[2])
    rel_move_to(ctx, -scale, si[2]*(2*scale))
    line_to(ctx, toy[1], toy[2])
    rel_line_to(ctx, scale, si[2]*(2*scale))
    # ylabel
    extents = text_extents(ctx, la[2])
    move_to(ctx, toy[1] - (extents[3]/2 + extents[1]), toy[2]-(extents[4]/2 + extents[2]) - si[2]*(2*scale))
    show_text(ctx,la[2])
end


### Profile Plotting ###


function showProfile(m::DataViewerWidget, params, slicesInRawData)
  chan = params[:activeChannel]
  prof = get_gtk_property(m["cbProfile"],:active, Int64) + 1
  if prof == 1
    m.currentProfile = vec(m.data[chan,:,slicesInRawData[2],slicesInRawData[3],params[:frame]])
    showProfile(m, m.currentProfile, "x", "c")
  elseif prof == 2
    m.currentProfile = vec(m.data[chan,slicesInRawData[1],:,slicesInRawData[3],params[:frame]])
    showProfile(m, m.currentProfile, "y", "c")
  elseif prof == 3
    m.currentProfile = vec(m.data[chan,slicesInRawData[1],slicesInRawData[2],:,params[:frame]])
    showProfile(m, m.currentProfile, "z", "c")
  else
    m.currentProfile = vec(m.data[chan,slicesInRawData[1],slicesInRawData[2],slicesInRawData[3],:])
    showProfile(m, m.currentProfile, "t", "c")
  end
end

function showProfile(m::DataViewerWidget, data, xLabel::String, yLabel::String)
  f, ax, l = CairoMakie.lines(1:length(data), data, 
        figure = (; resolution = (1000, 800), fontsize = 12),
        axis = (; title = "Profile"),
        color = CairoMakie.RGBf(colors[1]...))
  
  CairoMakie.autolimits!(ax)
  if length(data) > 1
    CairoMakie.xlims!(ax, 1, length(data))
  end
  ax.xlabel = xLabel
  ax.ylabel = yLabel
  drawonto(m.grid3D[1,2], f)
end

