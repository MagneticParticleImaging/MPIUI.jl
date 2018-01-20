using Gtk, Gtk.ShortNames, Cairo

export DataViewer, DataViewer, DataViewerWidget, drawImageCairo, drawImage
export getRegistrationBGParams, setRegistrationBGParams!

function DataViewer(imFG::ImageMeta, imBG=nothing; params=nothing)
  if ndims(imFG) <= 4
    DataViewer(ImageMeta[imFG], imBG; params=params)
  else
    DataViewer(imToVecIm(imFG), imBG; params=params)
  end
end

function DataViewer(imFG::Vector, imBG=nothing; params=nothing)
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
        @async println("copy visu params to clipboard...")
        str = string( getParams(dw) )
        str_ = replace(str,",Pair",",\n  Pair")
        clipboard( str_ )
      end
    end
  end

  dw
end

########### DataViewerWidget #################


type DataViewerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder
  data
  dataBG
  dataBGNotPermuted
  grid2D
  grid3D
  coloring
  upgradeColoringWInProgress
  currentlyShownImages
  currentlyShownData
  currentProfile
  offlineMode::Bool
  markerTracking
  simpleDataViewer
  extraWindow
  bgTracking
  cacheBGTrans
  cacheBGRot
  cacheDataBG
  cacheBGPerm
  cacheBGFlip
  history::Array{Float32,1}
  histIndex::Int64
  cacheStudyNameExpNumber::String
  cacheSelectedFovXYZ::Array{Float64,1}
  cacheSelectedMovePos::Array{Float64,1}
end

getindex(m::DataViewerWidget, w::AbstractString) = G_.object(m.builder, w)


function DataViewerWidget(offlineMode = true)

  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","dataviewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxDataViewer")
  m = DataViewerWidget( mainBox.handle, b, nothing, nothing, nothing, nothing,
                         nothing, nothing, false, nothing, nothing, nothing, offlineMode,
                        nothing, nothing, nothing, nothing, nothing , nothing, nothing,
                        nothing, nothing, zeros(Float32,10000), 1, string(), [0.0,0.0,0.0], [0.0,0.0,0.0])
  Gtk.gobject_move_ref(m, mainBox)

  initSimpleDataViewer(m)

  m.grid3D = m["gridDataViewer3D"]
  m.grid2D = m["gridDataViewer2D"]

  m.grid3D[2,1] = Canvas()
  m.grid3D[1,1] = Canvas()
  m.grid3D[2,2] = Canvas()
  m.grid3D[1,2] = Canvas()
  m.grid2D[1,1] = Canvas()

  choices = existing_cmaps()
  for c in choices
    push!(m["cbCMaps"], c)
    push!(m["cbCMapsBG"], c)
  end
  setproperty!(m["cbCMaps"],:active,length(choices)-1)
  setproperty!(m["cbCMapsBG"],:active,0)

  permutes = permuteCombinationsName()
  for c in permutes
    push!(m["cbPermutes"], c)
  end
  setproperty!(m["cbPermutes"], :active, 0)

  flippings = flippingsName()
  for c in flippings
    push!(m["cbFlips"], c)
  end
  setproperty!(m["cbFlips"], :active, 0)

  choicesFrameProj = ["None", "MIP", "TTP"]
  for c in choicesFrameProj
    push!(m["cbFrameProj"], c)
  end
  setproperty!(m["cbFrameProj"],:active,0)

  visible(m["expAnatomicRef"], false)
  if !m.offlineMode
    visible(m["expExport"], false)
    visible(m["expFrameProjection"], false)
    visible(m["labelFrames"], false)
    visible(m["spinFrames"], false)
  end


  function update( widget )
    if !m.upgradeColoringWInProgress
      updateColoring( m )
      Gtk.@sigatom showData( m )
    end
  end

  function updateChan( widget )
     updateColoringWidgets( m )
     update( m )
  end

  widgets = ["cbSpatialMIP", "cbShowSlices", "cbHideFG", "cbHideBG",
             "cbBlendChannels", "cbShowSFFOV", "cbTranslucentBlending",
              "cbSpatialBGMIP", "cbShowDFFOV"]
  for w in widgets
    signal_connect(update, m[w], "toggled")
  end

  widgets = ["adjFrames", "adjSliceX", "adjSliceY","adjSliceZ",
             "adjCMin", "adjCMax", "adjCMinBG", "adjCMaxBG",
             "adjTransX", "adjTransY", "adjTransZ",
             "adjRotX", "adjRotY", "adjRotZ",
             "adjTransBGX", "adjTransBGY", "adjTransBGZ",
             "adjRotBGX", "adjRotBGY", "adjRotBGZ",
             "adjTTPThresh"]
  for w in widgets
    signal_connect(update, m[w], "value_changed")
  end

  widgets = ["cbCMaps", "cbCMapsBG", "cbFrameProj"]
  for w in widgets
    signal_connect(update, m[w], "changed")
  end

  signal_connect(updateChan, m["cbChannel"], "changed")

  signal_connect(m["cbPermutes"], "changed") do widget
    permuteBGData(m)
    updateSliceWidgets(m)
    update(m)
  end

  signal_connect(m["cbFlips"], "changed") do widget
    permuteBGData(m)
    updateSliceWidgets(m)
    update(m)
  end

  signal_connect(m["cbShowExtraWindow"], "toggled") do widget
    if !getproperty(m["cbShowExtraWindow"], :active, Bool)
      Gtk.destroy(m.extraWindow)
      m.extraWindow = nothing
    end
  end

  signal_connect(m["btnExportImages"], "clicked") do widget
    if m.currentlyShownImages != nothing
      filter = Gtk.GtkFileFilter(pattern=String("*.png"), mimetype=String("image/png"))
      filenameImageData = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
      if filenameImageData != ""
        pixelResizeFactor = getproperty(m["adjPixelResizeFactor"],:value,Int64)
        @async println("Export Image as ", filenameImageData)
        exportImage(filenameImageData, m.currentlyShownImages, pixelResizeFactor=pixelResizeFactor)
      end
    end
  end

  signal_connect(m["btnExportTikz"], "clicked") do widget
    if m.currentlyShownImages != nothing
      filter = Gtk.GtkFileFilter(pattern=String("*.tikz*"), mimetype=String("image/tikz"))
      filenameImageData = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
      if filenameImageData != ""
        pixelResizeFactor = getproperty(m["adjPixelResizeFactor"],:value,Int64)
        @async println("Export Tikz as ", filenameImageData)
        props = m.currentlyShownData[1].properties
        SFPath=props["recoParams"][:SFPath]
        bSF = MPIFile(SFPath)
        exportTikz(filenameImageData, m.currentlyShownImages, collect(size(m.dataBG)),
         collect(pixelspacing(m.dataBG)),fov(bSF),getParams(m); pixelResizeFactor=pixelResizeFactor)
      end
    end
  end

  signal_connect(m["btnExportMovi"], "clicked") do widget
    filter = Gtk.GtkFileFilter(pattern=String("*.gif"), mimetype=String("image/gif"))
    filenameMovi = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
    if filenameMovi != ""
      params = getParams(m)
      sliceMovies = getColoredSlicesMovie(m.data, m.dataBG, m.coloring, params)
      pixelResizeFactor = getproperty(m["adjPixelResizeFactor"],:value, Int64)
      @async println("Export Movi as ", filenameMovi)
      exportMovies(filenameMovi, sliceMovies, pixelResizeFactor=pixelResizeFactor)
    end
  end

  signal_connect(m["btnExportAllData"], "clicked") do widget
    if m.data != nothing
      filter = Gtk.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
      filenameData = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
      if filenameData != ""

        params = getParams(m)

        maxval = [maximum(d) for d in m.data]
        minval = [minimum(d) for d in m.data]

        if m.dataBG != nothing
          data_ = interpolateToRefImage(m.dataBG, m.data, params)
          dataBG = interpolateToRefImage(m.dataBG, params)

          data__ = [data(d) for d in data_]

          cdataFG = colorize(data__, m.coloring, minval, maxval, params)

          minval,maxval = extrema(dataBG)
          cdataBG = colorize(dataBG,params[:coloringBG],minval,maxval)

          blendF = get(params, :translucentBlending, false) ? blend : dogyDoge
          cdata = blendF(cdataBG, cdataFG)
        else
          data_ = [data(d) for d in m.data]
          cdata = colorize(data_, m.coloring, minval, maxval, params)
        end

        prop = properties(m.data[1])
        cdata_ = similar(cdata, RGB{N0f8})
        cdata_[:] = convert(ImageMeta{RGB},cdata)[:] #TK: ugly hack

        file, ext = splitext(filenameData)
        savedata(string(file,".nii"), ImageMeta(cdata_,prop), permRGBData=true)
      end
    end
  end

  signal_connect(m["btnExportRealDataAllFr"], "clicked") do widget
    if m.data != nothing && m.dataBG != nothing
      filter = Gtk.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
      filenameData = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
      if filenameData != ""
        params = getParams(m)

        data = interpolateToRefImageAllFr(m.dataBG, m.data, params)
        dataBG = interpolateToRefImage(m.dataBG, params)

        #dataBG_ = applyPermutionsRev(m, dataBG)

        file, ext = splitext(filenameData)
        savedata(string(file,".nii"), data)
        savedata(string(file,"_BG.nii"), dataBG)
      end
    end
  end

  signal_connect(m["btnExportData"], "clicked") do widget
    if m.currentlyShownData != nothing
      filter = Gtk.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
      filenameData = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
      if filenameData != ""

        params = getParams(m)

        maxval = [maximum(d) for d in m.data]
        minval = [minimum(d) for d in m.data]

        data_ = [data(d) for d in m.currentlyShownData]

        cdata = colorize(data_,m.coloring,minval,maxval,params)

        if m.dataBG != nothing
          minval,maxval = extrema(m.dataBG)
          cdataBG = colorize(m.dataBG,params[:coloringBG],minval,maxval)

          blendF = get(params, :translucentBlending, false) ? blend : dogyDoge
          cdata = blendF(cdataBG, cdata)
        end

        prop = properties(m.currentlyShownData[1])
        cdata_ = similar(cdata, RGB{N0f8})
        cdata_[:] = convert(ImageMeta{RGB},cdata)[:] #TK: ugly hack

        file, ext = splitext(filenameData)
        savedata(string(file,".nii"), ImageMeta(cdata_,prop), permRGBData=true)
      end
    end
  end



  signal_connect(m["btnExportProfile"], "clicked") do widget
    if m.currentlyShownData != nothing
      filter = Gtk.GtkFileFilter(pattern=String("*.csv"), mimetype=String("text/comma-separated-values"))
      filenameImageData = save_dialog("Select Export File", GtkNullContainer(), (filter, ))
      if filenameImageData != "" && m.currentProfile != nothing
        @async println("Export Image as ", filenameImageData)

        writecsv(filenameImageData, m.currentProfile )
      end
    end
  end

  signal_connect(m["btnSaveVisu"], "clicked") do widget
    addVisu(mpilab, getParams(m))
  end

  stopPlayingMovie = false

  signal_connect(m["btnPlayMovie"], "toggled") do widget
    isActive = getproperty(m["btnPlayMovie"], :active, Bool)
    if isActive
      stopPlayingMovie = false
      Gtk.@sigatom playMovie()
    else
      stopPlayingMovie = true
    end
  end

  function playMovie()
    @async begin
    L = getproperty(m["adjFrames"],:upper, Int64)
    curFrame = getproperty(m["adjFrames"],:value, Int64)
    while !stopPlayingMovie
      Gtk.@sigatom setproperty!(m["adjFrames"],:value, curFrame)
      yield()
      sleep(0.01)
      curFrame = mod1(curFrame+1,L)
    end
    stopPlayingMovie = false
    end
  end

  signal_connect(m["btnAutoRegistration"], "clicked") do widget
    println("auto reigister")
  end

  return m
end

function permuteBGData(m::DataViewerWidget)
  if m.dataBGNotPermuted != nothing
    permInd = getproperty(m["cbPermutes"], :active, Int64) + 1
    flipInd = getproperty(m["cbFlips"], :active, Int64) + 1
    perm = permuteCombinations()[permInd]
    flip = flippings()[flipInd]
    m.dataBG = applyPermutions(m.dataBGNotPermuted, perm, flip)

    fov = collect(size(m.dataBG)).*collect(pixelspacing(m.dataBG)).*1000

    setproperty!(m["adjTransX"],:lower,-fov[1]/2)
    setproperty!(m["adjTransY"],:lower,-fov[2]/2)
    setproperty!(m["adjTransZ"],:lower,-fov[3]/2)
    setproperty!(m["adjTransX"],:upper,fov[1]/2)
    setproperty!(m["adjTransY"],:upper,fov[2]/2)
    setproperty!(m["adjTransZ"],:upper,fov[3]/2)

    setproperty!(m["adjTransBGX"],:lower,-fov[1]/2)
    setproperty!(m["adjTransBGY"],:lower,-fov[2]/2)
    setproperty!(m["adjTransBGZ"],:lower,-fov[3]/2)
    setproperty!(m["adjTransBGX"],:upper,fov[1]/2)
    setproperty!(m["adjTransBGY"],:upper,fov[2]/2)
    setproperty!(m["adjTransBGZ"],:upper,fov[3]/2)
  end
end

function updateSliceWidgets(m::DataViewerWidget)

  sxw = getproperty(m["adjSliceX"],:upper,Int64)
  syw = getproperty(m["adjSliceY"],:upper,Int64)
  szw = getproperty(m["adjSliceZ"],:upper,Int64)
  refdata = (m.dataBG == nothing) ? m.data[1] : m.dataBG
  if m.offlineMode
    if refdata != nothing && (size(refdata) != (sxw,syw,szw))

      setproperty!(m["adjFrames"],:upper,size(m.data[1],4))
      setproperty!(m["adjSliceX"],:upper,size(refdata,1))
      setproperty!(m["adjSliceY"],:upper,size(refdata,2))
      setproperty!(m["adjSliceZ"],:upper,size(refdata,3))

      Gtk.@sigatom setproperty!(m["adjFrames"],:value, 1)
      Gtk.@sigatom setproperty!(m["adjSliceX"],:value,max(div(size(refdata,1),2),1))
      Gtk.@sigatom setproperty!(m["adjSliceY"],:value,max(div(size(refdata,2),2),1))
      Gtk.@sigatom setproperty!(m["adjSliceZ"],:value,max(div(size(refdata,3),2),1))
    end
  elseif refdata != nothing
    setproperty!(m["adjFrames"],:upper,size(m.data[1],4))
    setproperty!(m["adjSliceX"],:upper,size(refdata,1))
    setproperty!(m["adjSliceY"],:upper,size(refdata,2))
    setproperty!(m["adjSliceZ"],:upper,size(refdata,3))

    sxwValue = getproperty(m["adjSliceX"],:value,Int64)
    sywValue = getproperty(m["adjSliceY"],:value,Int64)
    szwValue = getproperty(m["adjSliceZ"],:value,Int64)
    if sxwValue > sxw || sywValue > syw || szwValue > szw
      setproperty!(m["adjSliceX"],:value,size(refdata,1))
      setproperty!(m["adjSliceY"],:value,size(refdata,2))
      setproperty!(m["adjSliceZ"],:value,size(refdata,3))
    end
  end
end


function updateData!(m::DataViewerWidget, data::ImageMeta, dataBG=nothing; params=nothing)
  if ndims(data) <= 4
    updateData!(m, ImageMeta[data], dataBG; params=params)
  else
    updateData!(m, imToVecIm(data), dataBG; params=params)
  end
end

function updateData!(m::DataViewerWidget, data::Vector, dataBG=nothing; params=nothing)
  try
    visible(m["expAnatomicRef"], dataBG != nothing)
    if !m.offlineMode
      visible(m["expExport"], false)
      visible(m["labelFrames"], false)
      visible(m["spinFrames"], false)
      visible(m["expFrameProjection"], false)
    end

    multiChannel = length(data) > 1
    visible(m["cbBlendChannels"], multiChannel)
    visible(m["cbChannel"], multiChannel)
    visible(m["lbChannel"], multiChannel)

    if m.data == nothing || (length(m.data) != length(data))
      m.coloring = Array{ColoringParams}(length(data))
      for l=1:length(data)
        m.coloring[l] = ColoringParams(0.0,1.0,0)
      end

      Gtk.@sigatom empty!(m["cbChannel"])
      for i=1:length(data)
        push!(m["cbChannel"], "Channel $i")
      end
      Gtk.@sigatom setproperty!(m["cbChannel"],:active,0)

      strProfile = ["x direction", "y direction", "z direction","temporal"]
      Gtk.@sigatom empty!(m["cbProfile"])
      nd = size(data[1],4) > 1 ? 4 : 3
      for i=1:nd
        push!(m["cbProfile"], strProfile[i])
      end
      Gtk.@sigatom setproperty!(m["cbProfile"],:active,nd==4?3:0)

      updateColoringWidgets( m )
    end

    m.data = data
    if !m.offlineMode
      (dataBG != nothing) && (dataBG["offset"] = [0.0,0.0,0.0])
    end
    m.dataBGNotPermuted = dataBG
    m.dataBG = nothing
    permuteBGData(m)
    updateSliceWidgets(m)
    showData(m)
    Gtk.@sigatom setproperty!(m["adjPixelResizeFactor"],:value, (dataBG==nothing)?5:1  )

    if params!=nothing
      setParams(m,params)
    end
  catch ex
    println(catch_stacktrace(),"\nException: ",ex)
  end
end


function updateColoringWidgets(m::DataViewerWidget)
  m.upgradeColoringWInProgress = true
  chan = max(getproperty(m["cbChannel"],:active, Int64) + 1,1)
  Gtk.@sigatom setproperty!(m["adjCMin"],:value, m.coloring[chan].cmin)
  Gtk.@sigatom setproperty!(m["adjCMax"],:value, m.coloring[chan].cmax)
  Gtk.@sigatom setproperty!(m["cbCMaps"],:active, m.coloring[chan].cmap)
  m.upgradeColoringWInProgress = false
end

function updateColoring(m::DataViewerWidget)
  chan = max(getproperty(m["cbChannel"],:active, Int64) + 1,1)
  m.coloring[chan].cmin = getproperty(m["adjCMin"],:value, Float64)
  m.coloring[chan].cmax = getproperty(m["adjCMax"],:value, Float64)
  m.coloring[chan].cmap = getproperty(m["cbCMaps"],:active, Int64)
end


#     function get_context(c::Gtk.Canvas, pc::Winston.PlotContainer)
#         device = Winston.CairoRenderer(Gtk.cairo_surface(c))
#         ext_bbox = Winston.BoundingBox(0,Winston.width(c),0,Winston.height(c))
#         Winston._get_context(device, ext_bbox, pc)
#     end


function showData(m::DataViewerWidget)
  try
    params = getParams(m)
    if m.data != nothing

      if  params[:frameProj] == 1 && ndims(m.data[1]) == 4
        #data_ = [maximum(d, 4) for d in m.data]
        data_ = [  mip(d,4) for d in m.data]
      elseif params[:frameProj] == 2 && ndims(m.data[1]) == 4
        data_ = [timetopeak(d, params[:TTPThresh]) for d in m.data]
      else
        data_ = [getindex(d,:,:,:,params[:frame]) for d in m.data]
      end
      slices = (params[:sliceX],params[:sliceY],params[:sliceZ])
        if params[:spatialMIP]
          proj = "MIP"
        else
          proj = slices
        end
      #data = squeeze(data)

      # The following would be for per frame windowing
      #maxval = [maximum(d) for d in data_]
      #minval = [minimum(d) for d in data_]

      # global windowing
      maxval = [maximum(d) for d in m.data]
      minval = [minimum(d) for d in m.data]
      if params[:frameProj] == 2 && ndims(m.data[1]) == 4
        maxval = [maximum(d) for d in data_]
        minval = [minimum(d) for d in data_]
      end

      if m.dataBG != nothing
        slicesInRawData = MPILib.indexFromBGToFG(m.dataBG, data_, params)
        @async println("Slices in raw data: ", slicesInRawData)
        data = interpolateToRefImage(m.dataBG, data_, params)
        dataBG = cacheBackGround(m, params)
        edgeMask = getEdgeMask(m.dataBG, data_, params)
      else
        data = data_
        slicesInRawData = slices
        dataBG = edgeMask = nothing
      end

      m.currentlyShownData = data

      if ndims(squeeze(data[1])) == 3
        cdata_zx, cdata_zy, cdata_xy = getColoredSlices(data, dataBG, edgeMask, m.coloring, minval, maxval, params)
        isDrawSectionalLines = params[:showSlices] && proj != "MIP"
        isDrawRectangle = params[:showDFFOV]
        pixelSpacingBG = dataBG==nothing ? [0.002,0.002,0.001] : collect(pixelspacing(dataBG))
        sizeBG = dataBG==nothing ? [128,128,64] : collect(size(dataBG))
        xy,xz,yz,offsetxy,offsetxz,offsetyz = calcDFFovRectangle(m, params, pixelSpacingBG)
        drawImages(m,slices, isDrawSectionalLines, isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy, xz, yz, offsetxy, offsetxz, offsetyz,
          pixelSpacingBG, sizeBG)

        if getproperty(m["cbShowExtraWindow"], :active, Bool) && !m.offlineMode
          showExtraWindow(m, cdata_zy, cdata_zx, cdata_xy, isDrawSectionalLines, slices)
        end
        if ndims(m.data[1]) >= 3 && slicesInRawData != (0,0,0)
          if m.offlineMode
            showProfile(m, params, slicesInRawData)
            showWinstonPlot(m, m.currentProfile, "c", "xyzt")
          else
            showHistory(m)
          end
        end
        G_.current_page(m["nb2D3D"], 0)
        m.currentlyShownImages = ImageMeta[cdata_xy, cdata_zx, cdata_zy]
      else
        cdata = colorize(data, m.coloring, minval, maxval, params)
        pZ = drawImage( convert(Array,cdata.data) )
        display(m.grid2D[1,1],pZ)
        G_.current_page(m["nb2D3D"], 1)
        m.currentlyShownImages = cdata
      end
    end
  catch ex
    println(catch_stacktrace(),"\nException: ",ex)
  end
end

function drawSlice(m::DataViewerWidget,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)
  drawImageCairo(m.grid3D[2,1], cdata_zy, isDrawSectionalLines,
                 slices[2], slices[3], false, true, m["adjSliceY"], m["adjSliceZ"], isDrawRectangle,zy, offsetzy)
  drawImageCairo(m.grid3D[1,1], cdata_zx, isDrawSectionalLines,
                 slices[1], slices[3], true, true, m["adjSliceX"], m["adjSliceZ"], isDrawRectangle,zx, offsetzx)
  drawImageCairo(m.grid3D[2,2], cdata_xy, isDrawSectionalLines,
                 slices[2], slices[1], false, false, m["adjSliceY"], m["adjSliceX"], isDrawRectangle,xy, offsetxy)
end

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
  println("cachePos",cachePos,"screenXYZtoBackgroundXYZ", screenXYZtoBackgroundXYZ, "m.cacheSelectedMovePos", m.cacheSelectedMovePos)
end

function drawImages(m::DataViewerWidget,slices,isDrawSectionalLines,isDrawRectangle,
   cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy,
   pixelSpacingBG, sizeBG)
  drawSlice(m,slices,isDrawSectionalLines,isDrawRectangle, cdata_zx, cdata_zy, cdata_xy, xy,zx,zy,offsetxy,offsetzx,offsetzy)

  m.grid3D[1,1].mouse.button3press = @guarded (widget, event) -> begin
    @guarded Gtk.draw(widget) do widget
      if isDrawRectangle
        println("mouse event ZX")
        ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
        reveal(widget)
        pZX = [event.x, event.y]
        ZXtoXYforX = (wZX-pZX[1])/wZX *hXY # X coord in ZX width direction and in XY in height direction
        cacheSelectedFovXYZPos(m, [ZXtoXYforX,m.cacheSelectedFovXYZ[2], pZX[2]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
        println("cacheSelectedFovXYZ",m.cacheSelectedFovXYZ)
        pZY = [m.cacheSelectedFovXYZ[2], pZX[2]]
        pXY = [m.cacheSelectedFovXYZ[2], ZXtoXYforX]
        imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
        println("pZX",pZX,"zx", zx, "offsetzy", offsetzy, "imSizeZY", imSizeZY)
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
       println("mouse event ZY")
       ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
       reveal(widget)
       pZY = [event.x, event.y]
       cacheSelectedFovXYZPos(m, [m.cacheSelectedFovXYZ[1],pZY[1], pZY[2]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
       println("cacheSelectedFovXYZ",m.cacheSelectedFovXYZ)
       XYtoZXforX = wZX-(m.cacheSelectedFovXYZ[1]/hXY *wZX) # X coord in ZX width direction and in XY in height direction
       pZX = [XYtoZXforX, pZY[2]]
       pXY = [pZY[1],m.cacheSelectedFovXYZ[1]]
       imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
       println("pZY",pZY,"zy", zy, "offsetzy", offsetzy, "imSizeZY", imSizeZY)
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
       println("mouse event XY")
       ctxZY,ctxZX,ctxXY,hZY,wZY,hZX,wZX,hXY,wXY = getMetaDataSlices(m)
       reveal(widget)
       pXY = [event.x, event.y]
       XYtoZXforX = wZX-(pXY[2]/hXY *wZX) # X coord in ZX width direction and in XY in height direction
       cacheSelectedFovXYZPos(m, [pXY[2],pXY[1],m.cacheSelectedFovXYZ[3]], pixelSpacingBG, sizeBG, hXY,wZY,hZY)
       println("cacheSelectedFovXYZ",m.cacheSelectedFovXYZ)
       pZY = [pXY[1],m.cacheSelectedFovXYZ[3]]
       pZX = [XYtoZXforX, m.cacheSelectedFovXYZ[3]]
       imSizeZY,imSizeZX,imSizeXY= getImSizes(cdata_zy,cdata_zx,cdata_xy)
       println("pXY",pXY,"xy", xy, "offsetzy", offsetzy, "imSizeZY", imSizeZY)
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
  dfFov = getDFFov(m.currentlyShownData[1])
  xy,xz,yz = getSliceSizes(dfFov, pixelSpacingBG)
  #println("dfFov",dfFov,"xy:",xy,"xz:",xz,"yz:",yz,"pS:",m.dataBG==nothing ? [0.002,0.002,0.001] : collect(pixelspacing(m.dataBG)))
  offsetxy = ([params[:transY], params[:transX]])./([pixelSpacingBG[2],pixelSpacingBG[1]])
  offsetxz = ([-params[:transX], -params[:transZ]])./([pixelSpacingBG[1],pixelSpacingBG[3]])
  offsetyz = ([params[:transY], -params[:transZ]])./([pixelSpacingBG[2],pixelSpacingBG[3]])
  return xy,xz,yz,offsetxy,offsetxz,offsetyz
end

function getDFFov(im::ImageMeta)
  props = properties(im)
  if haskey(props, "dfStrength") && haskey(props, "acqGradient")
    dfS = squeeze(props["dfStrength"])
    acqGrad = squeeze(props["acqGradient"])
    dfFov = abs.(2*(dfS./acqGrad))
  else
    dfFov = [0.05,0.05,0.025] # use better default...
    warn("using default dfFov: ",dfFov)
  end
  return dfFov
end

function cacheBackGround(m::DataViewerWidget, params)
  # if m.cacheBGRot == nothing || m.cacheBGRot != [params[:rotBGX],params[:rotBGY],params[:rotBGZ]] ||
  #   m.cacheBGTrans == nothing || m.cacheBGTrans != [params[:transBGX],params[:transBGY],params[:transBGZ]] ||
  #   m.cacheBGPerm == nothing || m.cacheBGPerm != params[:permuteBG] || m.cacheBGFlip ==nothing || m.cacheBGFlip != params[:flipBG]
  #   dataBG = interpolateToRefImage(m.dataBG, params)
  #   m.cacheBGRot = [params[:rotBGX],params[:rotBGY],params[:rotBGZ]]
  #   m.cacheBGTrans = [params[:transBGX],params[:transBGY],params[:transBGZ]]
  #   m.cacheDataBG = dataBG
  #   m.cacheBGPerm = params[:permuteBG]
  #   m.cacheBGFlip = params[:flipBG]
  # else
  #   dataBG = m.cacheDataBG
  # end
  # if m.offlineMode || m.cacheBGRot == nothing || m.cacheBGRot != [params[:rotBGX],params[:rotBGY],params[:rotBGZ]] || m.cacheBGTrans == nothing || m.cacheBGTrans != [params[:transBGX],params[:transBGY],params[:transBGZ]]
    dataBG = interpolateToRefImage(m.dataBG, params)
  #   m.cacheBGRot = [params[:rotBGX],params[:rotBGY],params[:rotBGZ]]
  #   m.cacheBGTrans = [params[:transBGX],params[:transBGY],params[:transBGZ]]
  #   m.cacheDataBG = dataBG
  # else
  #   dataBG = m.cacheDataBG
  # end
  return dataBG
end

function showProfile(m::DataViewerWidget, params, slicesInRawData)
  chan = params[:activeChannel]
  prof = getproperty(m["cbProfile"],:active, Int64) + 1
  if prof == 1
    m.currentProfile = squeeze(m.data[chan][:,slicesInRawData[2],slicesInRawData[3],params[:frame]])
  elseif prof == 2
    m.currentProfile = squeeze(m.data[chan][slicesInRawData[1],:,slicesInRawData[3],params[:frame]])
  elseif prof == 3
    m.currentProfile = squeeze(m.data[chan][slicesInRawData[1],slicesInRawData[2],:,params[:frame]])
  else
    m.currentProfile = squeeze(m.data[chan][slicesInRawData[1],slicesInRawData[2],slicesInRawData[3],:])
  end
end

function showHistory(m::DataViewerWidget)
  studyNameExpNumber = getStudyNameExpNumber(properties(m.currentlyShownData[1]))
  if m.cacheStudyNameExpNumber == string() || m.cacheStudyNameExpNumber != studyNameExpNumber || m.histIndex >= 10000
    m.history[:] = 0
    m.cacheStudyNameExpNumber = studyNameExpNumber
    m.histIndex=1
  end
  val = sum(m.currentlyShownData[1])
  m.history[m.histIndex] = val
  showWinstonPlot(m, m.history[1:m.histIndex], "t", "sum xyz")
  m.histIndex+=1
end

function getStudyNameExpNumber(props::Dict{String,Any})
  if haskey(props,"currentAcquisitionFile")
    return props["currentAcquisitionFile"]
  else
    return "NoStudy"
  end
end

function showWinstonPlot(m::DataViewerWidget, data, xLabel::String, yLabel::String)
  p = Winston.FramedPlot(xlabel=xLabel, ylabel=yLabel)
  Winston.add(p, Winston.Curve(1:length(data), data, color="blue", linewidth=4))
  display(m.grid3D[1,2], p)
end

function showExtraWindow(m::DataViewerWidget, cdata_zy, cdata_zx, cdata_xy, isDrawSectionalLines::Bool, slices)
  if m.extraWindow == nothing
    m.extraWindow = Window("Simple Data Viewer",1920,1080)
    push!(m.extraWindow, m.simpleDataViewer)
    showall(m.extraWindow)
  end
  showData(m.simpleDataViewer, cdata_zy, cdata_zx, cdata_xy, isDrawSectionalLines, slices)
end

function drawImageCairo(c, image, isDrawSectionalLines, xsec, ysec,
                        flipX, flipY, adjX, adjY, isDrawRectangle, xy, xyOffset)
 @guarded Gtk.draw(c) do widget
  ctx = getgc(c)
  h = height(ctx)
  w = width(ctx)

  im = flipdim(convert(ImageMeta{RGB{N0f8}},image).data,1)
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
    println(imSize)
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
   Gtk.@sigatom setproperty!(adjX, :value, round(Int64,xx))
   Gtk.@sigatom setproperty!(adjY, :value, round(Int64,yy))
  end
 end
end


function drawImage(slice)
  tmp = map(x->convert(RGB24,x), squeeze(slice))
  csliceUint32 = reinterpret(UInt32, tmp)

  img = Winston.Image((1, size(csliceUint32,2)), (1, size(csliceUint32,1)), csliceUint32)
  p = Winston.FramedPlot()
  Winston.add(p, img)
  Winston.setattr( p.frame, "draw_nothing", true )

  return p
end


function drawSliceLines(p, xx, yy)
  lineX = Winston.LineX( xx, color=colorant"blue", linekind="dashed", linewidth = 2.5 )  #dotted
  Winston.add(p, lineX)
  lineY = Winston.LineY( yy, color=colorant"blue", linekind="dashed", linewidth = 2.5)
  Winston.add(p, lineY)

  return p
end

function mm2vox(p, pixelSpacing, dims)
  return p[dims]./pixelSpacing[dims]
end

function vox2mm(p, pixelSpacing, dims)
  return p.*pixelSpacing[dims]
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
  println("cIA", cIA, "sFac", sFac)
  return sFac
end

function createRectangle(ctx, cDA, sFac, xy, xyOffset)
  lowCX = cDA[1] - sFac[1] * xy[1]/2 + sFac[1] * xyOffset[1]
  lowCY= cDA[2] - sFac[2] * xy[2]/2 + sFac[2] * xyOffset[2]
  highCX =lowCX + sFac[1]*xy[1]
  highCY =lowCY + sFac[2]*xy[2]
  #println("lowCX:",lowCX,"lowCY:",lowCY,"highCX:",highCX,"highCY:",highCY)
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

function getParams(m::DataViewerWidget)
  params = defaultVisuParams()
  params[:sliceX] = getproperty(m["adjSliceX"], :value, Int64)
  params[:sliceY] = getproperty(m["adjSliceY"], :value, Int64)
  params[:sliceZ] = getproperty(m["adjSliceZ"], :value, Int64)
  params[:frame] = getproperty(m["adjFrames"], :value, Int64)
  params[:spatialMIP] = getproperty(m["cbSpatialMIP"], :active, Bool)
  params[:coloring] = m.coloring
  params[:description] = getproperty(m["entVisuName"], :text, String)
  params[:showSlices] = getproperty(m["cbShowSlices"], :active, Bool)

  params[:permuteBG] = permuteCombinations()[getproperty(m["cbPermutes"], :active, Int64) + 1]
  params[:flipBG] = flippings()[getproperty(m["cbFlips"], :active, Int64) + 1]

  params[:transX] = getproperty(m["adjTransX"], :value, Float64) / 1000
  params[:transY] = getproperty(m["adjTransY"], :value, Float64) / 1000
  params[:transZ] = getproperty(m["adjTransZ"], :value, Float64) / 1000
  params[:rotX] = getproperty(m["adjRotX"], :value, Float64)
  params[:rotY] = getproperty(m["adjRotY"], :value, Float64)
  params[:rotZ] = getproperty(m["adjRotZ"], :value, Float64)
  params[:transBGX] = getproperty(m["adjTransBGX"], :value, Float64) / 1000
  params[:transBGY] = getproperty(m["adjTransBGY"], :value, Float64) / 1000
  params[:transBGZ] = getproperty(m["adjTransBGZ"], :value, Float64) / 1000
  params[:rotBGX] = getproperty(m["adjRotBGX"], :value, Float64)
  params[:rotBGY] = getproperty(m["adjRotBGY"], :value, Float64)
  params[:rotBGZ] = getproperty(m["adjRotBGZ"], :value, Float64)
  params[:coloringBG] = ColoringParams(getproperty(m["adjCMinBG"], :value, Float64),
                                       getproperty(m["adjCMaxBG"], :value, Float64),
                                       getproperty(m["cbCMapsBG"], :active, Int64))
  if m.offlineMode
    params[:filenameBG] = (m.dataBGNotPermuted != nothing) ?
                          m.dataBGNotPermuted["filename"] : ""
  end
  params[:hideFG] = getproperty(m["cbHideFG"], :active, Bool)
  params[:hideBG] = getproperty(m["cbHideBG"], :active, Bool)
  params[:showSFFOV] = getproperty(m["cbShowSFFOV"], :active, Bool)
  params[:showDFFOV] = getproperty(m["cbShowDFFOV"], :active, Bool)
  params[:translucentBlending] = getproperty(m["cbTranslucentBlending"], :active, Bool)
  params[:spatialMIPBG] = getproperty(m["cbSpatialBGMIP"], :active, Bool)


  params[:TTPThresh] = getproperty(m["adjTTPThresh"], :value, Float64)
  params[:frameProj] = getproperty(m["cbFrameProj"], :active, Int64)

  params[:blendChannels] = getproperty(m["cbBlendChannels"], :active, Bool)
  params[:profile] = getproperty(m["cbProfile"], :active, Int64)

  params[:activeChannel] = max(getproperty(m["cbChannel"],:active, Int64) + 1,1)

  return params
end

function setParams(m::DataViewerWidget, params)
  Gtk.@sigatom setproperty!(m["adjSliceX"], :value, params[:sliceX])
  Gtk.@sigatom setproperty!(m["adjSliceY"], :value, params[:sliceY])
  Gtk.@sigatom setproperty!(m["adjSliceZ"], :value, params[:sliceZ])
  Gtk.@sigatom setproperty!(m["adjFrames"], :value, params[:frame])
  Gtk.@sigatom setproperty!(m["cbSpatialMIP"], :active, params[:spatialMIP])
  m.coloring = params[:coloring]
  updateColoringWidgets(m)
  Gtk.@sigatom setproperty!(m["entVisuName"], :text, params[:description])
  Gtk.@sigatom setproperty!(m["cbShowSlices"], :active, get(params,:showSlices,false))

  # The following is for backwards compatibility with a former data format
  # where instead of permuteBG and flipBG we stored permutionBG
  if haskey(params, :permutionBG)
    perm, flip = convertMode2PermFlip(params[:permutionBG])
    Gtk.@sigatom setproperty!(m["cbPermutes"], :active, find(x->x==perm,permuteCombinations())[1] - 1)
    Gtk.@sigatom setproperty!(m["cbFlips"], :active, find(x->x==flip,flippings())[1] - 1)
  else
    Gtk.@sigatom setproperty!(m["cbPermutes"], :active, find(x->x==params[:permuteBG],permuteCombinations())[1] - 1)
    Gtk.@sigatom setproperty!(m["cbFlips"], :active, find(x->x==params[:flipBG],flippings())[1] - 1)
  end

  Gtk.@sigatom setproperty!(m["adjTransX"], :value, params[:transX]*1000)
  Gtk.@sigatom setproperty!(m["adjTransY"], :value, params[:transY]*1000)
  Gtk.@sigatom setproperty!(m["adjTransZ"], :value, params[:transZ]*1000)
  Gtk.@sigatom setproperty!(m["adjRotX"], :value, params[:rotX])
  Gtk.@sigatom setproperty!(m["adjRotY"], :value, params[:rotY])
  Gtk.@sigatom setproperty!(m["adjRotZ"], :value, params[:rotZ])

  Gtk.@sigatom setproperty!(m["adjTransBGX"], :value, get(params,:transBGX,0.0)*1000)
  Gtk.@sigatom setproperty!(m["adjTransBGY"], :value, get(params,:transBGY,0.0)*1000)
  Gtk.@sigatom setproperty!(m["adjTransBGZ"], :value, get(params,:transBGZ,0.0)*1000)
  Gtk.@sigatom setproperty!(m["adjRotBGX"], :value, get(params,:rotBGX,0.0))
  Gtk.@sigatom setproperty!(m["adjRotBGY"], :value, get(params,:rotBGY,0.0))
  Gtk.@sigatom setproperty!(m["adjRotBGZ"], :value, get(params,:rotBGZ,0.0))

  Gtk.@sigatom setproperty!(m["adjCMinBG"], :value, params[:coloringBG].cmin)
  Gtk.@sigatom setproperty!(m["adjCMaxBG"], :value, params[:coloringBG].cmax)
  Gtk.@sigatom setproperty!(m["cbCMapsBG"], :active, params[:coloringBG].cmap)
  Gtk.@sigatom setproperty!(m["cbHideFG"], :active, get(params,:hideFG, false))
  Gtk.@sigatom setproperty!(m["cbHideBG"], :active, get(params,:hideBG, false))
  Gtk.@sigatom setproperty!(m["cbShowSFFOV"], :active, get(params,:showSFFOV, false))
  Gtk.@sigatom setproperty!(m["cbShowDFFOV"], :active, get(params,:showDFFOV, false))
  Gtk.@sigatom setproperty!(m["cbTranslucentBlending"], :active, get(params,:translucentBlending, false))
  Gtk.@sigatom setproperty!(m["cbSpatialBGMIP"], :active, get(params,:spatialMIPBG, false))

  Gtk.@sigatom setproperty!(m["adjTTPThresh"], :value, get(params,:TTPThresh, 0.4))
  Gtk.@sigatom setproperty!(m["cbFrameProj"], :active, get(params,:frameProj, 0))

  Gtk.@sigatom setproperty!(m["cbBlendChannels"], :active, get(params,:blendChannels, false))

  Gtk.@sigatom setproperty!(m["cbProfile"], :active, get(params,:profile, 0))
  #for (i,solver) in enumerate(linearSolverList())
  #  if solver == params[:solver]
  #    Gtk.@sigatom setproperty!(m["cbSolver"],:active, i-1)
  #  end
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
    transBGX = getproperty(m["adjTransX"], :value, Float64)
    transBGY = getproperty(m["adjTransY"], :value, Float64)
    transBGZ = getproperty(m["adjTransZ"], :value, Float64)
    rotBGX = getproperty(m["adjRotX"], :value, Float64)
    rotBGY = getproperty(m["adjRotY"], :value, Float64)
    rotBGZ = getproperty(m["adjRotZ"], :value, Float64)
    transBG =[transBGX transBGY transBGZ]
    rotBG = [rotBGX rotBGY rotBGZ]
    return rotBG, transBG
end

function setRegistrationFGParams!(m::DataViewerWidget, rotBG, transBG)
  Gtk.@sigatom begin
    setproperty!(m["adjTransX"], :value, transBG[1])
    setproperty!(m["adjTransY"], :value, transBG[2])
    setproperty!(m["adjTransZ"], :value, transBG[3])
    setproperty!(m["adjRotX"], :value, rotBG[1])
    setproperty!(m["adjRotY"], :value, rotBG[2])
    setproperty!(m["adjRotZ"], :value, rotBG[3])
  end
end
