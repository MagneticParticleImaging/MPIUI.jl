using Gtk, Gtk.ShortNames, Cairo

export DataViewer, DataViewer, DataViewerWidget, drawImageCairo
export getRegistrationBGParams, setRegistrationBGParams!

include("Widgets.jl")

function DataViewer(imFG, imBG=TransformedArray(zeros(Float32,0,0,0,0)); 
                    params=nothing)
  dw = DataViewer()
  updateData!(dw,imFG,imBG)
  if params!=nothing
    setParams(dw,params)
  end
  dw
end

function DataViewer()
  w = Window("Data Viewer",800,600)
  dw = DataViewerWidget()
  push!(w,dw)
  showall(w)

  signal_connect(w, "key-press-event") do widget, event
    if event.keyval ==  Gtk.GConstants.GDK_KEY_c
      if event.state & 0x04 != 0x00 # Control key is pressed
        @debug "copy visu params to clipboard..."
        str = string( getParams(dw) )
        str_ = replace(str,",Pair",",\n  Pair")
        clipboard( str_ )
      end
    end
  end

  dw
end

########### DataViewerWidget #################

mutable struct DataViewerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::Builder
  w::DVWidgets
  coloring::Vector{ColoringParams}
  upgradeColoringWInProgress::Bool
  offlineMode::Bool
  history::Vector{Float32}
  histIndex::Int64
  cacheStudyNameExpNumber::String
  cacheSelectedFovXYZ::Vector{Float64}
  cacheSelectedMovePos::Vector{Float64}
  stopPlayingMovie::Bool
  updating::Bool
  data::TransformedArray{Float32,5}
  dataBG::TransformedArray{Float32,3}
  dataBGNotPermuted::TransformedArray{Float32,3}
  currentlyShownImages::Vector{Array{RGBA{Normed{UInt8,8}},2}}
  currentlyShownData::TransformedArray{Float32,4}
  currentProfile::TransformedArray{Float32,1}
  filenameBG::String
end

include("Drawing.jl")
include("Export.jl")

function DataViewerWidget(offlineMode = true)

  uifile = joinpath(@__DIR__,"..","builder","dataviewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxDataViewer")
  m = DataViewerWidget( mainBox.handle, b, DVWidgets(b),  
                         Vector{ColoringParams}(), false, offlineMode,
                         zeros(Float32,10000), 1, string(),
                        [0.0,0.0,0.0], [0.0,0.0,0.0], false, false,
                        TransformedArray(zeros(Float32,0,0,0,0,0)),
                        TransformedArray(zeros(Float32,0,0,0)), 
                        TransformedArray(zeros(Float32,0,0,0)), 
                        Vector{Array{RGBA{Normed{UInt8,8}},2}}(undef,0),
                        TransformedArray(zeros(Float32,0,0,0,0)),
                        TransformedArray(zeros(Float32,0)),"")
                        
  Gtk.gobject_move_ref(m, mainBox)

  #initSimpleDataViewer(m)

  m.w.gridDataViewer3D[2,1] = Canvas()
  m.w.gridDataViewer3D[1,1] = Canvas()
  m.w.gridDataViewer3D[2,2] = Canvas()
  m.w.gridDataViewer3D[1,2] = Canvas()
  m.w.gridDataViewer2D[1,1] = Canvas()

  showall(m)

  choices = existing_cmaps()
  for c in choices
    push!(m.w.cbCMaps, c)
    push!(m.w.cbCMapsBG, c)
  end
  set_gtk_property!(m.w.cbCMaps,:active,length(choices)-1)
  set_gtk_property!(m.w.cbCMapsBG,:active,0)

  permutes = permuteCombinationsName()
  for c in permutes
    push!(m.w.cbPermutes, c)
  end
  set_gtk_property!(m.w.cbPermutes, :active, 0)

  flippings = flippingsName()
  for c in flippings
    push!(m.w.cbFlips, c)
  end
  set_gtk_property!(m.w.cbFlips, :active, 0)

  choicesFrameProj = ["None", "MIP", "TTP"]
  for c in choicesFrameProj
    push!(m.w.cbFrameProj, c)
  end
  set_gtk_property!(m.w.cbFrameProj,:active,0)

  visible(m.w.mbFusion, false)
  visible(m.w.lbFusion, false)
  visible(m.w.sepFusion, false)
  if !m.offlineMode
    visible(m.w.expExport, false)
    visible(m.w.expFrameProjection, false)
    visible(m.w.labelFrames, false)
    visible(m.w.spinFrames, false)
  end



  signal_connect(m.w.btnPlayMovie, "toggled") do widget
    isActive = get_gtk_property(m.w.btnPlayMovie, :active, Bool)
    if isActive
      m.stopPlayingMovie = false
      Gtk.@sigatom playMovie()
    else
      m.stopPlayingMovie = true
    end
  end

  function playMovie()
    @async begin
    L = get_gtk_property(m.w.adjFrames,:upper, Int64)
    curFrame = get_gtk_property(m.w.adjFrames,:value, Int64)
    while !m.stopPlayingMovie
      Gtk.@sigatom set_gtk_property!(m.w.adjFrames,:value, curFrame)
      yield()
      sleep(0.01)
      curFrame = mod1(curFrame+1,L)
    end
    m.stopPlayingMovie = false
    end
  end

  initCallbacks(m)

  return m
end

function initCallbacks(m_::DataViewerWidget)
  let m=m_

    function update( widget )
      if !m.upgradeColoringWInProgress
        updateColoring( m )
        showData( m )
      end
    end

    function updateChan( widget )
       updateColoringWidgets( m )
       update( m )
    end

    widgets = [m.w.cbSpatialMIP, m.w.cbShowSlices, m.w.cbHideFG, m.w.cbHideBG,
               m.w.cbBlendChannels, m.w.cbShowSFFOV, m.w.cbTranslucentBlending,
                m.w.cbSpatialBGMIP, m.w.cbShowDFFOV]
    for w in widgets
      signal_connect(update, w, "toggled")
    end

    widgets = [m.w.adjFrames, m.w.adjSliceX, m.w.adjSliceY, m.w.adjSliceZ,
               m.w.adjCMin, m.w.adjCMax, m.w.adjCMinBG, m.w.adjCMaxBG,
               m.w.adjTransX, m.w.adjTransY, m.w.adjTransZ,
               m.w.adjRotX, m.w.adjRotY, m.w.adjRotZ,
               m.w.adjTransBGX, m.w.adjTransBGY, m.w.adjTransBGZ,
               m.w.adjRotBGX, m.w.adjRotBGY, m.w.adjRotBGZ,
               m.w.adjTTPThresh]
    for w in widgets
      signal_connect(update, w, "value_changed")
    end

    widgets = [m.w.cbCMaps, m.w.cbCMapsBG, m.w.cbFrameProj]
    for w in widgets
      signal_connect(update, w, "changed")
    end

    signal_connect(updateChan, m.w.cbChannel, "changed")

    signal_connect(m.w.cbPermutes, "changed") do widget
      permuteBGData(m)
      updateSliceWidgets(m)
      update(m)
    end

    signal_connect(m.w.cbFlips, "changed") do widget
      permuteBGData(m)
      updateSliceWidgets(m)
      update(m)
    end
    
    initExportCallbacks(m)

    signal_connect(m.w.btnSaveVisu, "clicked") do widget
      addVisu(mpilab[], getParams(m))
    end

  end
end

function permuteBGData(m::DataViewerWidget)
  if length(m.dataBGNotPermuted) > 0
    permInd = get_gtk_property(m.w.cbPermutes, :active, Int64) + 1
    flipInd = get_gtk_property(m.w.cbFlips, :active, Int64) + 1
    perm = permuteCombinations()[permInd]
    flip = flippings()[flipInd]
    m.dataBG = applyPermutions(m.dataBGNotPermuted, perm, flip)
      @show pixelspacing(m.dataBG)
      @show pixelspacing(m.dataBGNotPermuted)

    #fov = collect(size(m.dataBG)).*collect(converttometer(pixelspacing(m.dataBG))).*1000
    fov = collect(size(m.dataBG)).*collect(pixelspacing(m.dataBG)).*1000

    set_gtk_property!(m.w.adjTransX,:lower,-fov[1]/2)
    set_gtk_property!(m.w.adjTransY,:lower,-fov[2]/2)
    set_gtk_property!(m.w.adjTransZ,:lower,-fov[3]/2)
    set_gtk_property!(m.w.adjTransX,:upper,fov[1]/2)
    set_gtk_property!(m.w.adjTransY,:upper,fov[2]/2)
    set_gtk_property!(m.w.adjTransZ,:upper,fov[3]/2)

    set_gtk_property!(m.w.adjTransBGX,:lower,-fov[1]/2)
    set_gtk_property!(m.w.adjTransBGY,:lower,-fov[2]/2)
    set_gtk_property!(m.w.adjTransBGZ,:lower,-fov[3]/2)
    set_gtk_property!(m.w.adjTransBGX,:upper,fov[1]/2)
    set_gtk_property!(m.w.adjTransBGY,:upper,fov[2]/2)
    set_gtk_property!(m.w.adjTransBGZ,:upper,fov[3]/2)
  end
end

function updateSliceWidgets(m::DataViewerWidget)

  sfw = get_gtk_property(m.w.adjFrames,:upper,Int64)
  sxw = get_gtk_property(m.w.adjSliceX,:upper,Int64)
  syw = get_gtk_property(m.w.adjSliceY,:upper,Int64)
  szw = get_gtk_property(m.w.adjSliceZ,:upper,Int64)
  refdata = (length(m.dataBG) > 0) ? m.data[1,:,:,:,:] : m.dataBG
  if !isempty(refdata) 
    if size(refdata,4) != sfw
      Gtk.@sigatom set_gtk_property!(m.w.adjFrames,:value, 1)
      set_gtk_property!(m.w.adjFrames,:upper,size(m.data,5))
    end
    
    if size(refdata,1) != sxw || size(refdata,2) != syw || size(refdata,3) != szw
      set_gtk_property!(m.w.adjSliceX,:upper,size(refdata,1))
      set_gtk_property!(m.w.adjSliceY,:upper,size(refdata,2))
      set_gtk_property!(m.w.adjSliceZ,:upper,size(refdata,3))

      Gtk.@sigatom set_gtk_property!(m.w.adjSliceX,:value,max(div(size(refdata,1),2),1))
      Gtk.@sigatom set_gtk_property!(m.w.adjSliceY,:value,max(div(size(refdata,2),2),1))
      Gtk.@sigatom set_gtk_property!(m.w.adjSliceZ,:value,max(div(size(refdata,3),2),1))
    end
  end
  return
end


function updateData!(m::DataViewerWidget, data::ImageMeta, dataBG=nothing; params=nothing, kargs...)
  data_ = TransformedArray(data.data.data, collect(converttometer(pixelspacing(data))))
  @show pixelspacing(data_)
  if dataBG != nothing
    dataBG_ = TransformedArray(dataBG.data.data, collect(converttometer(pixelspacing(dataBG))))
  @show pixelspacing(dataBG_)
    m.filenameBG = haskey(dataBG, "filename") ? dataBG["filename"] : ""
  else
    dataBG_ = TransformedArray(zeros(Float32,0,0,0))
  end
            
  updateData!(m, data_, dataBG_; params=params, kargs...)
end

function updateData!(m::DataViewerWidget, data::TransformedArray{Float32,5}, 
                     dataBG=TransformedArray(zeros(Float32,0,0,0)); params=nothing, ampPhase=false)

    m.updating = true
    visible(m.w.mbFusion, !isempty(dataBG))
    visible(m.w.lbFusion, !isempty(dataBG))
    visible(m.w.sepFusion, !isempty(dataBG))
    if !m.offlineMode
      visible(m.w.expExport, false)
      visible(m.w.labelFrames, false)
      visible(m.w.spinFrames, false)
      visible(m.w.expFrameProjection, false)
    end

    multiChannel = size(data,1) > 1
    visible(m.w.cbBlendChannels, multiChannel)
    visible(m.w.cbChannel, multiChannel)
    visible(m.w.lbChannel, multiChannel)

    if (size(m.data) != size(data))
      m.coloring = Array{ColoringParams}(undef,size(data,1))
      if size(data,1) == 1
        m.coloring[1] = ColoringParams(0.0,1.0,"viridis")
      end
      if size(data,1) > 2
        for l=1:length(data)
          m.coloring[l] = ColoringParams(0.0,1.0,l)
        end
      end
      if size(data,1) == 2
        if ampPhase
          m.coloring[1] = ColoringParams(0.0,1.0,"viridis")
          m.coloring[2] = ColoringParams(0.0,1.0,"viridis")
        else
          m.coloring[1] = ColoringParams(0.0,1.0,"blue")
          m.coloring[2] = ColoringParams(0.0,1.0,"red")
	      end
      end

      Gtk.@sigatom empty!(m.w.cbChannel)
      for i=1:size(data,1)
        push!(m.w.cbChannel, "$i")
      end
      set_gtk_property!(m.w.cbChannel,:active,0)

      strProfile = ["x direction", "y direction", "z direction","temporal"]
      Gtk.@sigatom empty!(m.w.cbProfile)
      nd = size(data,5) > 1 ? 4 : 3
      for i=1:nd
        push!(m.w.cbProfile, strProfile[i])
      end
      set_gtk_property!(m.w.cbProfile,:active,nd==4 ? 3 : 0)

      updateColoringWidgets( m )
      set_gtk_property!(m.w.cbBlendChannels, :active, size(data,1)>1 && !ampPhase)
    end

    m.data = data
    m.dataBGNotPermuted = dataBG
    #m.dataBG = nothing
    permuteBGData(m)
    updateSliceWidgets(m)
    m.updating = false

    showData(m)
    Gtk.@sigatom set_gtk_property!(m.w.adjPixelResizeFactor,:value, (isempty(dataBG)) ? 5 : 1  )

    if params!=nothing
      if !isempty(data)
        params[:sliceX] = min(params[:sliceX],size(data,2))
        params[:sliceY] = min(params[:sliceY],size(data,3))
        params[:sliceZ] = min(params[:sliceZ],size(data,4))
      end
      setParams(m,params)
    end
  return
end


function updateColoringWidgets(m::DataViewerWidget)
  m.upgradeColoringWInProgress = true
  chan = max(get_gtk_property(m.w.cbChannel,:active, Int64) + 1,1)
  Gtk.@sigatom set_gtk_property!(m.w.adjCMin,:value, m.coloring[chan].cmin)
  Gtk.@sigatom set_gtk_property!(m.w.adjCMax,:value, m.coloring[chan].cmax)
  idx = findfirst(a->a==m.coloring[chan].cmap,existing_cmaps())-1
  Gtk.@sigatom set_gtk_property!(m.w.cbCMaps,:active, idx)
  m.upgradeColoringWInProgress = false
end

function updateColoring(m::DataViewerWidget)
  chan = max(get_gtk_property(m.w.cbChannel,:active, Int64) + 1,1)
  cmin = get_gtk_property(m.w.adjCMin,:value, Float64)
  cmax = get_gtk_property(m.w.adjCMax,:value, Float64)
  cmap = existing_cmaps()[get_gtk_property(m.w.cbCMaps,:active, Int64)+1]
  m.coloring[chan] = ColoringParams(cmin,cmax,cmap)
end

function showData(m::DataViewerWidget)

  if !m.updating
  #try
    params = getParams(m)
    if m.data != nothing

      data_ = sliceTimeDim(m.data, params[:frameProj] == 1 ? "MIP" : params[:frame])

      slices = (params[:sliceX],params[:sliceY],params[:sliceZ])
      
      if params[:spatialMIP]
        proj = "MIP"
      else
        proj = slices
      end

      # global windowing
      maxval = maximum(m.data) #for d in m.data]
      minval = minimum(m.data) #for d in m.data]
      #if params[:frameProj] == 2 && ndims(m.data[1]) == 4
      #  maxval = [maximum(d) for d in data_]
      #  minval = [minimum(d) for d in data_]
      #end

      if !isempty(m.dataBG)
        slicesInRawData = ImageUtils.indexFromBGToFG(m.dataBG, data_, params)
        @debug "Slices in raw data:" slicesInRawData
        data = interpolateToRefImage(m.dataBG, data_, params)
        dataBG = interpolateToRefImage(m.dataBG, params)
      else
        # not ideal ....
        params[:sliceX] = min(params[:sliceX],size(m.data,2))
        params[:sliceY] = min(params[:sliceY],size(m.data,3))
        params[:sliceZ] = min(params[:sliceZ],size(m.data,4))

        data = data_
        slicesInRawData = slices
        dataBG = m.dataBG#nothing
      end

      m.currentlyShownData = data

      if ndims(squeeze(data[1,:,:,:])) >= 2
        cdata_zx, cdata_zy, cdata_xy = getColoredSlices(data.data, dataBG, m.coloring, minval, maxval, params)
        isDrawSectionalLines = params[:showSlices] && proj != "MIP"
        isDrawRectangle = params[:showDFFOV]
        pixelSpacingBG = isempty(dataBG) ? [0.002,0.002,0.001] : collect(pixelspacing(dataBG))
        sizeBG = isempty(dataBG) ? [128,128,64] : collect(size(dataBG))
        xy,xz,yz,offsetxy,offsetxz,offsetyz = calcDFFovRectangle(m, params, pixelSpacingBG)

        drawImages(m,slices, isDrawSectionalLines, isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy, xz, yz, offsetxy, offsetxz, offsetyz,
          pixelSpacingBG, sizeBG)
        if slicesInRawData != (0,0,0)
          showProfile(m, params, slicesInRawData)
          showWinstonPlot(m, m.currentProfile, "c", "xyzt")
        end
        G_.current_page(m.w.nb2D3D, 0)
        m.currentlyShownImages = [cdata_xy, cdata_zx, cdata_zy]
      else
        dat = vec(data_)
        p = Winston.FramedPlot(xlabel="x", ylabel="y")
        Winston.add(p, Winston.Curve(1:length(dat), dat, color="blue", linewidth=4))
        display(m.w.gridDataViewer2D[1,1],p)
        G_.current_page(m.w.nb2D3D, 1)

        #m.currentlyShownImages = cdata
      end
    end
  #catch ex
  #  @show "Exception" ex stacktrace(catch_backtrace())
  #  throw(ex)
  #end
  end
  return
end

function drawSlice(m::DataViewerWidget,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
  drawImageCairo(m.w.gridDataViewer3D[2,1], cdata_zy, isDrawSectionalLines,
                 slices[2], slices[3], false, true, m.w.adjSliceY, m.w.adjSliceZ, isDrawRectangle,zy, offsetzy)
  drawImageCairo(m.w.gridDataViewer3D[1,1], cdata_zx, isDrawSectionalLines,
                 slices[1], slices[3], true, true, m.w.adjSliceX, m.w.adjSliceZ, isDrawRectangle,zx, offsetzx)
  drawImageCairo(m.w.gridDataViewer3D[2,2], cdata_xy, isDrawSectionalLines,
                 slices[2], slices[1], false, false, m.w.adjSliceY, m.w.adjSliceX, isDrawRectangle,xy, offsetxy)
end

function getMetaDataSlices(m::DataViewerWidget)
  ctxZY = Gtk.getgc(m.w.gridDataViewer3D[2,1])
  ctxZX = Gtk.getgc(m.w.gridDataViewer3D[1,1])
  ctxXY = Gtk.getgc(m.w.gridDataViewer3D[2,2])
  hZY = height(ctxZY)
  wZY = width(ctxZY)
  hZX = height(ctxZX)
  wZX = width(ctxZX)
  hXY = height(ctxXY)
  wXY = width(ctxXY)
  return ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY
end

function getImSizes(cdata_zy,cdata_zx,cdata_xy)
  imSizeZY = collect(size(cdata_zy))
  imSizeZX = collect(size(cdata_zx))
  imSizeXY = collect(size(cdata_xy))
  return imSizeZY,imSizeZX,imSizeXY
end


function cacheSelectedFovXYZPos(m::DataViewerWidget, cachePos::Array{Float64,1}, pixelSpacingBG, sizeBG, hX,wY,hZ)
  m.cacheSelectedFovXYZ = cachePos
  screenXYZtoBackgroundXYZ = (cachePos .-[hX/2,wY/2,hZ/2]) .* (sizeBG ./ [hX,wY,hZ])
  m.cacheSelectedMovePos = screenXYZtoBackgroundXYZ .* pixelSpacingBG
  @debug "" cachePos screenXYZtoBackgroundXYZ m.cacheSelectedMovePos
  return
end

function drawImages(m::DataViewerWidget,slices,isDrawSectionalLines,isDrawRectangle,
   cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy,
   pixelSpacingBG, sizeBG)
   
  drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)

  m.w.gridDataViewer3D[1,1].mouse.button3press = @guarded (widget, event) -> begin
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
  m.w.gridDataViewer3D[2,1].mouse.button3press = @guarded (widget, event) -> begin
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
 m.w.gridDataViewer3D[2,2].mouse.button3press = @guarded (widget, event) -> begin
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

function calcDFFovRectangle(m::DataViewerWidget, params, pixelSpacingBG)
  dfFov = getDFFov(m.currentlyShownData[1,:,:,:])
  xy,xz,yz = getSliceSizes(dfFov, pixelSpacingBG)
  @debug "" dfFov xy xz yz
  offsetxy = ([params[:transY], params[:transX]])./([pixelSpacingBG[2],pixelSpacingBG[1]])
  offsetxz = ([-params[:transX], -params[:transZ]])./([pixelSpacingBG[1],pixelSpacingBG[3]])
  offsetyz = ([params[:transY], -params[:transZ]])./([pixelSpacingBG[2],pixelSpacingBG[3]])
  return xy,xz,yz,offsetxy,offsetxz,offsetyz
end

function getDFFov(im)
  #=props = properties(im)
  if haskey(props, "dfStrength") && haskey(props, "acqGradient")
    dfS = squeeze(props["dfStrength"])
    acqGrad = squeeze(props["acqGradient"])
    acqGrad_ = zeros(size(acqGrad,2),size(acqGrad,3))
    for k=1:size(acqGrad,3)
        acqGrad_[:,k]=diag(acqGrad[:,:,k])
    end
    dfFov = abs.(2*(dfS./acqGrad_))
  else
    dfFov = [0.05,0.05,0.025] 
  end=#
  return [0.05,0.05,0.025]
end

function showProfile(m::DataViewerWidget, params, slicesInRawData)
  chan = params[:activeChannel]
  prof = get_gtk_property(m.w.cbProfile,:active, Int64) + 1
  if prof == 1
    m.currentProfile = vec(m.data[chan,:,slicesInRawData[2],slicesInRawData[3],params[:frame]])
  elseif prof == 2
    m.currentProfile = vec(m.data[chan,slicesInRawData[1],:,slicesInRawData[3],params[:frame]])
  elseif prof == 3
    m.currentProfile = vec(m.data[chan,slicesInRawData[1],slicesInRawData[2],:,params[:frame]])
  else
    m.currentProfile = vec(m.data[chan,slicesInRawData[1],slicesInRawData[2],slicesInRawData[3],:])
  end
end

function getStudyNameExpNumber(props::Dict{String,Any})
  if haskey(props,"currentAcquisitionFile")
    return props["currentAcquisitionFile"]
  else
    return "NoStudy"
  end
end

function getSliceSizes(fov_mm, pixelSpacing)
  fov_vox = fov_mm ./ pixelSpacing
  xy = [fov_vox[2],fov_vox[1]]
  xz = [fov_vox[1],fov_vox[3]]
  yz = [fov_vox[2],fov_vox[3]]
  return xy,xz,yz
end

function getParams(m::DataViewerWidget)
  params = defaultVisuParams()
  params[:sliceX] = get_gtk_property(m.w.adjSliceX, :value, Int64)
  params[:sliceY] = get_gtk_property(m.w.adjSliceY, :value, Int64)
  params[:sliceZ] = get_gtk_property(m.w.adjSliceZ, :value, Int64)
  params[:frame] = get_gtk_property(m.w.adjFrames, :value, Int64)
  params[:spatialMIP] = get_gtk_property(m.w.cbSpatialMIP, :active, Bool)
  params[:coloring] = m.coloring
  params[:description] = get_gtk_property(m.w.entVisuName, :text, String)
  params[:showSlices] = get_gtk_property(m.w.cbShowSlices, :active, Bool)

  params[:permuteBG] = permuteCombinations()[get_gtk_property(m.w.cbPermutes, :active, Int64) + 1]
  params[:flipBG] = flippings()[get_gtk_property(m.w.cbFlips, :active, Int64) + 1]

  params[:transX] = get_gtk_property(m.w.adjTransX, :value, Float64) / 1000
  params[:transY] = get_gtk_property(m.w.adjTransY, :value, Float64) / 1000
  params[:transZ] = get_gtk_property(m.w.adjTransZ, :value, Float64) / 1000
  params[:rotX] = get_gtk_property(m.w.adjRotX, :value, Float64)
  params[:rotY] = get_gtk_property(m.w.adjRotY, :value, Float64)
  params[:rotZ] = get_gtk_property(m.w.adjRotZ, :value, Float64)
  params[:transBGX] = get_gtk_property(m.w.adjTransBGX, :value, Float64) / 1000
  params[:transBGY] = get_gtk_property(m.w.adjTransBGY, :value, Float64) / 1000
  params[:transBGZ] = get_gtk_property(m.w.adjTransBGZ, :value, Float64) / 1000
  params[:rotBGX] = get_gtk_property(m.w.adjRotBGX, :value, Float64)
  params[:rotBGY] = get_gtk_property(m.w.adjRotBGY, :value, Float64)
  params[:rotBGZ] = get_gtk_property(m.w.adjRotBGZ, :value, Float64)
  params[:coloringBG] = ColoringParams(get_gtk_property(m.w.adjCMinBG, :value, Float64),
                                       get_gtk_property(m.w.adjCMaxBG, :value, Float64),
                                       get_gtk_property(m.w.cbCMapsBG, :active, Int64))
                                       
  params[:filenameBG] = m.filenameBG

  params[:hideFG] = get_gtk_property(m.w.cbHideFG, :active, Bool)
  params[:hideBG] = get_gtk_property(m.w.cbHideBG, :active, Bool)
  params[:showSFFOV] = get_gtk_property(m.w.cbShowSFFOV, :active, Bool)
  params[:showDFFOV] = get_gtk_property(m.w.cbShowDFFOV, :active, Bool)
  params[:translucentBlending] = get_gtk_property(m.w.cbTranslucentBlending, :active, Bool)
  params[:spatialMIPBG] = get_gtk_property(m.w.cbSpatialBGMIP, :active, Bool)


  params[:TTPThresh] = get_gtk_property(m.w.adjTTPThresh, :value, Float64)
  params[:frameProj] = get_gtk_property(m.w.cbFrameProj, :active, Int64)

  params[:blendChannels] = get_gtk_property(m.w.cbBlendChannels, :active, Bool)
  params[:profile] = get_gtk_property(m.w.cbProfile, :active, Int64)

  params[:activeChannel] = max(get_gtk_property(m.w.cbChannel,:active, Int64) + 1,1)

  return params
end

function setParams(m::DataViewerWidget, params)
  #Gtk.@sigatom begin
  set_gtk_property!(m.w.adjSliceX, :value, params[:sliceX])
  set_gtk_property!(m.w.adjSliceY, :value, params[:sliceY])
  set_gtk_property!(m.w.adjSliceZ, :value, params[:sliceZ])
  set_gtk_property!(m.w.adjFrames, :value, params[:frame])
  set_gtk_property!(m.w.cbSpatialMIP, :active, params[:spatialMIP])
  m.coloring = Vector{ColoringParams}(undef,0)
  for col in params[:coloring]
    push!(m.coloring, ColoringParams(col.cmin, col.cmax, col.cmap))
  end 
  
  updateColoringWidgets(m)
  set_gtk_property!(m.w.entVisuName, :text, params[:description])
  set_gtk_property!(m.w.cbShowSlices, :active, get(params,:showSlices,false))

  # The following is for backwards compatibility with a former data format
  # where instead of permuteBG and flipBG we stored permutionBG
  if haskey(params, :permutionBG)
    perm, flip = convertMode2PermFlip(params[:permutionBG])
    set_gtk_property!(m.w.cbPermutes, :active, findall(x->x==perm,permuteCombinations())[1] - 1)
    set_gtk_property!(m.w.cbFlips, :active, findall(x->x==flip,flippings())[1] - 1)
  else
    set_gtk_property!(m.w.cbPermutes, :active, findall(x->x==params[:permuteBG],permuteCombinations())[1] - 1)
    set_gtk_property!(m.w.cbFlips, :active, findall(x->x==params[:flipBG],flippings())[1] - 1)
  end

  set_gtk_property!(m.w.adjTransX, :value, params[:transX]*1000)
  set_gtk_property!(m.w.adjTransY, :value, params[:transY]*1000)
  set_gtk_property!(m.w.adjTransZ, :value, params[:transZ]*1000)
  set_gtk_property!(m.w.adjRotX, :value, params[:rotX])
  set_gtk_property!(m.w.adjRotY, :value, params[:rotY])
  set_gtk_property!(m.w.adjRotZ, :value, params[:rotZ])

  set_gtk_property!(m.w.adjTransBGX, :value, get(params,:transBGX,0.0)*1000)
  set_gtk_property!(m.w.adjTransBGY, :value, get(params,:transBGY,0.0)*1000)
  set_gtk_property!(m.w.adjTransBGZ, :value, get(params,:transBGZ,0.0)*1000)
  set_gtk_property!(m.w.adjRotBGX, :value, get(params,:rotBGX,0.0))
  set_gtk_property!(m.w.adjRotBGY, :value, get(params,:rotBGY,0.0))
  set_gtk_property!(m.w.adjRotBGZ, :value, get(params,:rotBGZ,0.0))

  set_gtk_property!(m.w.adjCMinBG, :value, params[:coloringBG].cmin)
  set_gtk_property!(m.w.adjCMaxBG, :value, params[:coloringBG].cmax)
  col_ = params[:coloringBG]
  col = ColoringParams(col_.cmin, col_.cmax, col_.cmap)
  idx = findfirst(a->a==col.cmap, existing_cmaps())-1
  set_gtk_property!(m.w.cbCMapsBG, :active, idx)
  set_gtk_property!(m.w.cbHideFG, :active, get(params,:hideFG, false))
  set_gtk_property!(m.w.cbHideBG, :active, get(params,:hideBG, false))
  set_gtk_property!(m.w.cbShowSFFOV, :active, get(params,:showSFFOV, false))
  set_gtk_property!(m.w.cbShowDFFOV, :active, get(params,:showDFFOV, false))
  set_gtk_property!(m.w.cbTranslucentBlending, :active, get(params,:translucentBlending, false))
  set_gtk_property!(m.w.cbSpatialBGMIP, :active, get(params,:spatialMIPBG, false))

  set_gtk_property!(m.w.adjTTPThresh, :value, get(params,:TTPThresh, 0.4))
  set_gtk_property!(m.w.cbFrameProj, :active, get(params,:frameProj, 0))

  set_gtk_property!(m.w.cbBlendChannels, :active, get(params,:blendChannels, false))

  set_gtk_property!(m.w.cbProfile, :active, get(params,:profile, 0))
  #end
  showData(m)
end

function defaultVisuParams()
  params = Dict{Symbol,Any}()
  return params
end


function initSimpleDataViewer(m::DataViewerWidget)
  m.simpleDataViewer = SimpleDataViewerWidget()
end

function getRegistrationFGParams(m::DataViewerWidget)
    transBGX = get_gtk_property(m.w.adjTransX, :value, Float64)
    transBGY = get_gtk_property(m.w.adjTransY, :value, Float64)
    transBGZ = get_gtk_property(m.w.adjTransZ, :value, Float64)
    rotBGX = get_gtk_property(m.w.adjRotX, :value, Float64)
    rotBGY = get_gtk_property(m.w.adjRotY, :value, Float64)
    rotBGZ = get_gtk_property(m.w.adjRotZ, :value, Float64)
    transBG =[transBGX transBGY transBGZ]
    rotBG = [rotBGX rotBGY rotBGZ]
    return rotBG, transBG
end

function setRegistrationFGParams!(m::DataViewerWidget, rotBG, transBG)
  Gtk.@sigatom begin
    set_gtk_property!(m.w.adjTransX, :value, transBG[1])
    set_gtk_property!(m.w.adjTransY, :value, transBG[2])
    set_gtk_property!(m.w.adjTransZ, :value, transBG[3])
    set_gtk_property!(m.w.adjRotX, :value, rotBG[1])
    set_gtk_property!(m.w.adjRotY, :value, rotBG[2])
    set_gtk_property!(m.w.adjRotZ, :value, rotBG[3])
  end
end



