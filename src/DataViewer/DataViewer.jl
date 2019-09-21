using Gtk, Gtk.ShortNames, Cairo

export DataViewer, DataViewer, DataViewerWidget, drawImageCairo
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
  grid2D::Grid
  grid3D::Grid
  coloring
  upgradeColoringWInProgress
  cacheSelectedFovXYZ::Array{Float64,1}
  cacheSelectedMovePos::Array{Float64,1}
  stopPlayingMovie
  updating
  data
  dataBG
  dataBGNotPermuted
  currentlyShownImages
  currentlyShownData
  currentProfile
end

getindex(m::DataViewerWidget, w::AbstractString) = G_.object(m.builder, w)

include("Export.jl")
include("Drawing.jl")

function DataViewerWidget()

  uifile = joinpath(@__DIR__,"..","builder","dataviewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxDataViewer")
  m = DataViewerWidget( mainBox.handle, b,  
                         G_.object(b, "gridDataViewer2D"),
                         G_.object(b, "gridDataViewer3D"),
                         nothing, false, 
                        [0.0,0.0,0.0], [0.0,0.0,0.0], false, false,
                        nothing, nothing, nothing,nothing, nothing, nothing)
  Gtk.gobject_move_ref(m, mainBox)

  m.grid3D[2,1] = Canvas()
  m.grid3D[1,1] = Canvas()
  m.grid3D[2,2] = Canvas()
  m.grid3D[1,2] = Canvas()
  m.grid2D[1,1] = Canvas()

  showall(m)

  choices = existing_cmaps()
  for c in choices
    push!(m["cbCMaps"], c)
    push!(m["cbCMapsBG"], c)
  end
  set_gtk_property!(m["cbCMaps"],:active,length(choices)-1)
  set_gtk_property!(m["cbCMapsBG"],:active,0)

  permutes = permuteCombinationsName()
  for c in permutes
    push!(m["cbPermutes"], c)
  end
  set_gtk_property!(m["cbPermutes"], :active, 0)

  flippings = flippingsName()
  for c in flippings
    push!(m["cbFlips"], c)
  end
  set_gtk_property!(m["cbFlips"], :active, 0)

  choicesFrameProj = ["None", "MIP", "TTP"]
  for c in choicesFrameProj
    push!(m["cbFrameProj"], c)
  end
  set_gtk_property!(m["cbFrameProj"],:active,0)

  visible(m["mbFusion"], false)
  visible(m["lbFusion"], false)
  visible(m["sepFusion"], false)

  signal_connect(m["btnPlayMovie"], "toggled") do widget
    isActive = get_gtk_property(m["btnPlayMovie"], :active, Bool)
    if isActive
      m.stopPlayingMovie = false
      Gtk.@sigatom playMovie()
    else
      m.stopPlayingMovie = true
    end
  end

  function playMovie()
    @async begin
    L = get_gtk_property(m["adjFrames"],:upper, Int64)
    curFrame = get_gtk_property(m["adjFrames"],:value, Int64)
    while !m.stopPlayingMovie
      Gtk.@sigatom set_gtk_property!(m["adjFrames"],:value, curFrame)
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
        Gtk.@sigatom showData( m )
      end
    end

    function updateChan( widget )
       updateColoringWidgets( m )
       update( m )
    end

    widgets = ["cbSpatialMIP", "cbShowSlices", "cbHideFG", "cbHideBG",
               "cbBlendChannels", "cbTranslucentBlending",
                "cbSpatialBGMIP", "cbShowDFFOV", "cbComplexBlending"]
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

    signal_connect(m["btnSaveVisu"], "clicked") do widget
      addVisu(mpilab[], getParams(m))
    end

    initExportCallbacks(m)
  end
end

function permuteBGData(m::DataViewerWidget)
  if m.dataBGNotPermuted != nothing
    permInd = get_gtk_property(m["cbPermutes"], :active, Int64) + 1
    flipInd = get_gtk_property(m["cbFlips"], :active, Int64) + 1
    perm = permuteCombinations()[permInd]
    flip = flippings()[flipInd]
    m.dataBG = applyPermutions(m.dataBGNotPermuted, perm, flip)

    fov = collect(size(m.dataBG)).*collect(converttometer(pixelspacing(m.dataBG))).*1000

    set_gtk_property!(m["adjTransX"],:lower,-fov[1]/2)
    set_gtk_property!(m["adjTransY"],:lower,-fov[2]/2)
    set_gtk_property!(m["adjTransZ"],:lower,-fov[3]/2)
    set_gtk_property!(m["adjTransX"],:upper,fov[1]/2)
    set_gtk_property!(m["adjTransY"],:upper,fov[2]/2)
    set_gtk_property!(m["adjTransZ"],:upper,fov[3]/2)

    set_gtk_property!(m["adjTransBGX"],:lower,-fov[1]/2)
    set_gtk_property!(m["adjTransBGY"],:lower,-fov[2]/2)
    set_gtk_property!(m["adjTransBGZ"],:lower,-fov[3]/2)
    set_gtk_property!(m["adjTransBGX"],:upper,fov[1]/2)
    set_gtk_property!(m["adjTransBGY"],:upper,fov[2]/2)
    set_gtk_property!(m["adjTransBGZ"],:upper,fov[3]/2)
  end
end

function updateSliceWidgets(m::DataViewerWidget)

  sfw = get_gtk_property(m["adjFrames"],:upper,Int64)
  sxw = get_gtk_property(m["adjSliceX"],:upper,Int64)
  syw = get_gtk_property(m["adjSliceY"],:upper,Int64)
  szw = get_gtk_property(m["adjSliceZ"],:upper,Int64)
  refdata = (m.dataBG == nothing) ? m.data[1] : m.dataBG

  if refdata != nothing 
    if size(refdata,4) != sfw
      Gtk.@sigatom set_gtk_property!(m["adjFrames"],:value, 1)
      set_gtk_property!(m["adjFrames"],:upper,size(m.data[1],4))
    end
      
    if size(refdata,1) != sxw || size(refdata,2) != syw || size(refdata,3) != szw
      set_gtk_property!(m["adjSliceX"],:upper,size(refdata,1))
      set_gtk_property!(m["adjSliceY"],:upper,size(refdata,2))
      set_gtk_property!(m["adjSliceZ"],:upper,size(refdata,3))

      Gtk.@sigatom set_gtk_property!(m["adjSliceX"],:value,max(div(size(refdata,1),2),1))
      Gtk.@sigatom set_gtk_property!(m["adjSliceY"],:value,max(div(size(refdata,2),2),1))
      Gtk.@sigatom set_gtk_property!(m["adjSliceZ"],:value,max(div(size(refdata,3),2),1))
    end
  end
end

function updateData!(m::DataViewerWidget, data::ImageMeta, dataBG=nothing; params=nothing, kargs...)
  if ndims(data) <= 4
    updateData!(m, ImageMeta[data], dataBG; params=params, kargs...)
  else
    updateData!(m, imToVecIm(data), dataBG; params=params, kargs...)
  end
end

function updateData!(m::DataViewerWidget, data::Vector, dataBG=nothing; params=nothing, ampPhase=false)
  try
    m.updating = true
    visible(m["mbFusion"], dataBG != nothing)
    visible(m["lbFusion"], dataBG != nothing)
    visible(m["sepFusion"], dataBG != nothing)

    multiChannel = length(data) > 1
    visible(m["cbBlendChannels"], multiChannel)
    visible(m["cbChannel"], multiChannel)
    visible(m["lbChannel"], multiChannel)

    if m.data == nothing || (length(m.data) != length(data))
      m.coloring = Array{ColoringParams}(undef,length(data))
      if length(data) == 1
        m.coloring[1] = ColoringParams(0.0,1.0,21)
      end
      if length(data) > 2
        for l=1:length(data)
          m.coloring[l] = ColoringParams(0.0,1.0,l)
        end
      end
      if length(data) == 2
        if ampPhase
          m.coloring[1] = ColoringParams(0.0,1.0,21)
          m.coloring[2] = ColoringParams(0.0,1.0,21)
        else
          m.coloring[1] = ColoringParams(0.0,1.0,3)
          m.coloring[2] = ColoringParams(0.0,1.0,2)
        end
      end

      Gtk.@sigatom empty!(m["cbChannel"])
      for i=1:length(data)
        push!(m["cbChannel"], "$i")
      end
      Gtk.@sigatom set_gtk_property!(m["cbChannel"],:active,0)

      strProfile = ["x direction", "y direction", "z direction","temporal"]
      Gtk.@sigatom empty!(m["cbProfile"])
      nd = size(data[1],4) > 1 ? 4 : 3
      for i=1:nd
        push!(m["cbProfile"], strProfile[i])
      end
      Gtk.@sigatom set_gtk_property!(m["cbProfile"],:active,nd==4 ? 3 : 0)

      updateColoringWidgets( m )
      set_gtk_property!(m["cbBlendChannels"], :active, length(data)>1 )
      set_gtk_property!(m["cbComplexBlending"], :active, ampPhase)
    end

    m.data = data

    m.dataBGNotPermuted = dataBG
    m.dataBG = nothing
    permuteBGData(m)
    updateSliceWidgets(m)
    m.updating = false
    showData(m)
    Gtk.@sigatom set_gtk_property!(m["adjPixelResizeFactor"],:value, (dataBG==nothing) ? 5 : 1  )

    if params!=nothing
      if data != nothing
        params[:sliceX] = min(params[:sliceX],size(data[1],1))
        params[:sliceY] = min(params[:sliceY],size(data[1],2))
        params[:sliceZ] = min(params[:sliceZ],size(data[1],3))
      end
      setParams(m,params)
    end
  catch ex
    @warn "Exception" ex stacktrace(catch_backtrace())
  end
end

function updateColoringWidgets(m::DataViewerWidget)
  m.upgradeColoringWInProgress = true
  chan = max(get_gtk_property(m["cbChannel"],:active, Int64) + 1,1)
  Gtk.@sigatom set_gtk_property!(m["adjCMin"],:value, m.coloring[chan].cmin)
  Gtk.@sigatom set_gtk_property!(m["adjCMax"],:value, m.coloring[chan].cmax)
  Gtk.@sigatom set_gtk_property!(m["cbCMaps"],:active, m.coloring[chan].cmap)
  m.upgradeColoringWInProgress = false
end

function updateColoring(m::DataViewerWidget)
  chan = max(get_gtk_property(m["cbChannel"],:active, Int64) + 1,1)
  m.coloring[chan].cmin = get_gtk_property(m["adjCMin"],:value, Float64)
  m.coloring[chan].cmax = get_gtk_property(m["adjCMax"],:value, Float64)
  m.coloring[chan].cmap = get_gtk_property(m["cbCMaps"],:active, Int64)
end

function showData(m::DataViewerWidget)
  if !m.updating
  #try
    params = getParams(m)
    if m.data != nothing

      if  params[:frameProj] == 1 && ndims(m.data[1]) == 4
        #data_ = [maximum(d, 4) for d in m.data]
        data_ = [  mip(d,4) for d in m.data]
      elseif params[:frameProj] == 2 && ndims(m.data[1]) == 4
        data_ = [timetopeak(d, alpha=params[:TTPThresh], alpha2=params[:TTPThresh]) for d in m.data]
      else
        data_ = [getindex(d,:,:,:,params[:frame]) for d in m.data]
      end

      slices = (params[:sliceX],params[:sliceY],params[:sliceZ])
        if params[:spatialMIP]
          proj = "MIP"
        else
          proj = slices
        end

      # global windowing
      maxval = [maximum(d) for d in m.data]
      minval = [minimum(d) for d in m.data]
      if params[:frameProj] == 2 && ndims(m.data[1]) == 4
        maxval = [maximum(d) for d in data_]
        minval = [minimum(d) for d in data_]
      end

      if m.dataBG != nothing
        slicesInRawData = MPILib.indexFromBGToFG(m.dataBG, data_, params)
        @debug "Slices in raw data:" slicesInRawData
        data = interpolateToRefImage(m.dataBG, data_, params)
        dataBG = interpolateToRefImage(m.dataBG, params)
        edgeMask = nothing 
      else
        # not ideal ....
        params[:sliceX] = min(params[:sliceX],size(m.data[1],1))
        params[:sliceY] = min(params[:sliceY],size(m.data[1],2))
        params[:sliceZ] = min(params[:sliceZ],size(m.data[1],3))

        data = data_
        slicesInRawData = slices
        dataBG = edgeMask = nothing
      end
      
      m.currentlyShownData = data

      if ndims(squeeze(data[1])) >= 2
        cdata_zx, cdata_zy, cdata_xy = getColoredSlices(data, dataBG, edgeMask, m.coloring, minval, maxval, params)
        isDrawSectionalLines = params[:showSlices] && proj != "MIP"
        isDrawRectangle = params[:showDFFOV]
        pixelSpacingBG = (dataBG==nothing) ? [0.002,0.002,0.001] : collect(converttometer(pixelspacing(dataBG)))
        sizeBG = (dataBG==nothing) ? [128,128,64] : collect(size(dataBG))
        drawImages(m,slices, isDrawSectionalLines, isDrawRectangle, cdata_zx, cdata_zy, cdata_xy,
                   [params[:transX], params[:transY], params[:transZ]], pixelSpacingBG, sizeBG)

        if ndims(m.data[1]) >= 3 && slicesInRawData != (0,0,0)
          showProfile(m, params, slicesInRawData)
        end
        G_.current_page(m["nb2D3D"], 0)
        m.currentlyShownImages = ImageMeta[cdata_xy, cdata_zx, cdata_zy]
      else
        dat = vec(data_[1])
        p = Winston.FramedPlot(xlabel="x", ylabel="y")
        Winston.add(p, Winston.Curve(1:length(dat), dat, color="blue", linewidth=4))
        display(m.grid2D[1,1],p)
        G_.current_page(m["nb2D3D"], 1)

        #m.currentlyShownImages = cdata
      end
    end
  #catch ex
  #  @warn "Exception" ex stacktrace(catch_backtrace())
  #end
  end
end

function getParams(m::DataViewerWidget)
  params = defaultVisuParams()
  params[:sliceX] = get_gtk_property(m["adjSliceX"], :value, Int64)
  params[:sliceY] = get_gtk_property(m["adjSliceY"], :value, Int64)
  params[:sliceZ] = get_gtk_property(m["adjSliceZ"], :value, Int64)
  params[:frame] = get_gtk_property(m["adjFrames"], :value, Int64)
  params[:spatialMIP] = get_gtk_property(m["cbSpatialMIP"], :active, Bool)
  params[:coloring] = m.coloring
  params[:description] = get_gtk_property(m["entVisuName"], :text, String)
  params[:showSlices] = get_gtk_property(m["cbShowSlices"], :active, Bool)

  params[:permuteBG] = permuteCombinations()[get_gtk_property(m["cbPermutes"], :active, Int64) + 1]
  params[:flipBG] = flippings()[get_gtk_property(m["cbFlips"], :active, Int64) + 1]

  params[:transX] = get_gtk_property(m["adjTransX"], :value, Float64) / 1000
  params[:transY] = get_gtk_property(m["adjTransY"], :value, Float64) / 1000
  params[:transZ] = get_gtk_property(m["adjTransZ"], :value, Float64) / 1000
  params[:rotX] = get_gtk_property(m["adjRotX"], :value, Float64)
  params[:rotY] = get_gtk_property(m["adjRotY"], :value, Float64)
  params[:rotZ] = get_gtk_property(m["adjRotZ"], :value, Float64)
  params[:transBGX] = get_gtk_property(m["adjTransBGX"], :value, Float64) / 1000
  params[:transBGY] = get_gtk_property(m["adjTransBGY"], :value, Float64) / 1000
  params[:transBGZ] = get_gtk_property(m["adjTransBGZ"], :value, Float64) / 1000
  params[:rotBGX] = get_gtk_property(m["adjRotBGX"], :value, Float64)
  params[:rotBGY] = get_gtk_property(m["adjRotBGY"], :value, Float64)
  params[:rotBGZ] = get_gtk_property(m["adjRotBGZ"], :value, Float64)
  params[:coloringBG] = ColoringParams(get_gtk_property(m["adjCMinBG"], :value, Float64),
                                       get_gtk_property(m["adjCMaxBG"], :value, Float64),
                                       get_gtk_property(m["cbCMapsBG"], :active, Int64))

   params[:filenameBG] = (m.dataBGNotPermuted != nothing) && haskey(m.dataBGNotPermuted, "filename") ? m.dataBGNotPermuted["filename"] : ""

  params[:hideFG] = get_gtk_property(m["cbHideFG"], :active, Bool)
  params[:hideBG] = get_gtk_property(m["cbHideBG"], :active, Bool)
  params[:showDFFOV] = get_gtk_property(m["cbShowDFFOV"], :active, Bool)
  params[:translucentBlending] = get_gtk_property(m["cbTranslucentBlending"], :active, Bool)
  params[:spatialMIPBG] = get_gtk_property(m["cbSpatialBGMIP"], :active, Bool)


  params[:TTPThresh] = get_gtk_property(m["adjTTPThresh"], :value, Float64)
  params[:frameProj] = get_gtk_property(m["cbFrameProj"], :active, Int64)

  params[:blendChannels] = get_gtk_property(m["cbBlendChannels"], :active, Bool)
  params[:complexBlending] = get_gtk_property(m["cbComplexBlending"], :active, Bool)
  
  params[:profile] = get_gtk_property(m["cbProfile"], :active, Int64)

  params[:activeChannel] = max(get_gtk_property(m["cbChannel"],:active, Int64) + 1,1)

  return params
end

function setParams(m::DataViewerWidget, params)
  Gtk.@sigatom set_gtk_property!(m["adjSliceX"], :value, params[:sliceX])
  Gtk.@sigatom set_gtk_property!(m["adjSliceY"], :value, params[:sliceY])
  Gtk.@sigatom set_gtk_property!(m["adjSliceZ"], :value, params[:sliceZ])
  Gtk.@sigatom set_gtk_property!(m["adjFrames"], :value, params[:frame])
  Gtk.@sigatom set_gtk_property!(m["cbSpatialMIP"], :active, params[:spatialMIP])
  m.coloring = params[:coloring]
  updateColoringWidgets(m)
  Gtk.@sigatom set_gtk_property!(m["entVisuName"], :text, params[:description])
  Gtk.@sigatom set_gtk_property!(m["cbShowSlices"], :active, get(params,:showSlices,false))

  # The following is for backwards compatibility with a former data format
  # where instead of permuteBG and flipBG we stored permutionBG
  if haskey(params, :permutionBG)
    perm, flip = convertMode2PermFlip(params[:permutionBG])
    Gtk.@sigatom set_gtk_property!(m["cbPermutes"], :active, findall(x->x==perm,permuteCombinations())[1] - 1)
    Gtk.@sigatom set_gtk_property!(m["cbFlips"], :active, findall(x->x==flip,flippings())[1] - 1)
  else
    Gtk.@sigatom set_gtk_property!(m["cbPermutes"], :active, findall(x->x==params[:permuteBG],permuteCombinations())[1] - 1)
    Gtk.@sigatom set_gtk_property!(m["cbFlips"], :active, findall(x->x==params[:flipBG],flippings())[1] - 1)
  end

  Gtk.@sigatom set_gtk_property!(m["adjTransX"], :value, params[:transX]*1000)
  Gtk.@sigatom set_gtk_property!(m["adjTransY"], :value, params[:transY]*1000)
  Gtk.@sigatom set_gtk_property!(m["adjTransZ"], :value, params[:transZ]*1000)
  Gtk.@sigatom set_gtk_property!(m["adjRotX"], :value, params[:rotX])
  Gtk.@sigatom set_gtk_property!(m["adjRotY"], :value, params[:rotY])
  Gtk.@sigatom set_gtk_property!(m["adjRotZ"], :value, params[:rotZ])

  Gtk.@sigatom set_gtk_property!(m["adjTransBGX"], :value, get(params,:transBGX,0.0)*1000)
  Gtk.@sigatom set_gtk_property!(m["adjTransBGY"], :value, get(params,:transBGY,0.0)*1000)
  Gtk.@sigatom set_gtk_property!(m["adjTransBGZ"], :value, get(params,:transBGZ,0.0)*1000)
  Gtk.@sigatom set_gtk_property!(m["adjRotBGX"], :value, get(params,:rotBGX,0.0))
  Gtk.@sigatom set_gtk_property!(m["adjRotBGY"], :value, get(params,:rotBGY,0.0))
  Gtk.@sigatom set_gtk_property!(m["adjRotBGZ"], :value, get(params,:rotBGZ,0.0))

  Gtk.@sigatom set_gtk_property!(m["adjCMinBG"], :value, params[:coloringBG].cmin)
  Gtk.@sigatom set_gtk_property!(m["adjCMaxBG"], :value, params[:coloringBG].cmax)
  Gtk.@sigatom set_gtk_property!(m["cbCMapsBG"], :active, params[:coloringBG].cmap)
  Gtk.@sigatom set_gtk_property!(m["cbHideFG"], :active, get(params,:hideFG, false))
  Gtk.@sigatom set_gtk_property!(m["cbHideBG"], :active, get(params,:hideBG, false))
  Gtk.@sigatom set_gtk_property!(m["cbShowDFFOV"], :active, get(params,:showDFFOV, false))
  Gtk.@sigatom set_gtk_property!(m["cbTranslucentBlending"], :active, get(params,:translucentBlending, false))
  Gtk.@sigatom set_gtk_property!(m["cbSpatialBGMIP"], :active, get(params,:spatialMIPBG, false))

  Gtk.@sigatom set_gtk_property!(m["adjTTPThresh"], :value, get(params,:TTPThresh, 0.4))
  Gtk.@sigatom set_gtk_property!(m["cbFrameProj"], :active, get(params,:frameProj, 0))

  Gtk.@sigatom set_gtk_property!(m["cbBlendChannels"], :active, get(params,:blendChannels, false))

  Gtk.@sigatom set_gtk_property!(m["cbProfile"], :active, get(params,:profile, 0))

  showData(m)
end

function defaultVisuParams()
  params = Dict{Symbol,Any}()
  return params
end


