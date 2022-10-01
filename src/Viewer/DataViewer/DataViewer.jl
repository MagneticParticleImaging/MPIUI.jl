using Gtk, Gtk.ShortNames, Cairo

export DataViewer, DataViewerWidget

########### DataViewerWidget #################

mutable struct DataViewerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::Builder
  grid2D::Grid
  grid3D::Grid
  coloring::Vector{ColoringParams}
  upgradeColoringWInProgress::Bool
  cacheSelectedFovXYZ::Array{Float64,1}
  cacheSelectedMovePos::Array{Float64,1}
  stopPlayingMovie::Bool
  updating::Bool
  data
  dataBG
  dataBGNotPermuted
  currentlyShownImages
  currentlyShownData
  currentProfile
end

getindex(m::DataViewerWidget, w::AbstractString) = G_.object(m.builder, w)

mutable struct DataViewer
  w::Window
  dvw::DataViewerWidget
end

function DataViewer(imFG::ImageMeta, imBG=nothing; params=nothing)
  dv = DataViewer()
  updateData!(dv.dvw,imFG,imBG)
  if params!=nothing
    setParams(dv.dvw,params)
  end
  return dv
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

  return DataViewer(w,dw)
end

include("Export.jl")
include("Drawing.jl")

function DataViewerWidget()

  uifile = joinpath(@__DIR__,"..","..","builder","dataviewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxDataViewer")
  m = DataViewerWidget( mainBox.handle, b,
                         G_.object(b, "gridDataViewer2D"),
                         G_.object(b, "gridDataViewer3D"),
                         Vector{ColoringParams}(), false,
                        [0.0,0.0,0.0], [0.0,0.0,0.0], false, false,
                        nothing, nothing, nothing,nothing, nothing, nothing)
  Gtk.gobject_move_ref(m, mainBox)

  m.grid3D[2,1] = Canvas()
  m.grid3D[1,1] = Canvas()
  m.grid3D[2,2] = Canvas()
  m.grid3D[1,2] = Canvas()
  m.grid2D[1,1] = Canvas()

  showall(m)

  choices = important_cmaps()
  for c in choices
    push!(m["cbCMaps"], c)
    push!(m["cbCMapsBG"], c)
  end
  set_gtk_property!(m["cbCMaps"],:active,5) # default: viridis
  set_gtk_property!(m["cbCMapsBG"],:active,0) # default: gray

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
      @idle_add_guarded playMovie()
    else
      m.stopPlayingMovie = true
    end
  end

  function playMovie()
    @async begin
    L = get_gtk_property(m["adjFrames"],:upper, Int64)
    curFrame = get_gtk_property(m["adjFrames"],:value, Int64)
    while !m.stopPlayingMovie
      @idle_add_guarded set_gtk_property!(m["adjFrames"],:value, curFrame)
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

    widgets = ["cbSpatialMIP", "cbShowSlices", "cbHideFG", "cbHideBG",
               "cbBlendChannels", "cbTranslucentBlending",
               "cbSpatialBGMIP", "cbShowDFFOV", "cbComplexBlending",
		           "cbShowAxes"]
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
      try
        m.updating = true
        permuteBGData(m)
        updateSliceWidgets(m)
        m.updating = false
        update(m)
      catch e
        @error e
        showError(e)
      end
    end

    signal_connect(m["cbFlips"], "changed") do widget
      try
        m.updating = true
        permuteBGData(m)
        updateSliceWidgets(m)
        m.updating = false
        update(m)
      catch e
        @error e
        showError(e)
      end
    end

    signal_connect(m["btnSaveVisu"], "clicked") do widget
      try
        params = getParams(m)
        # Need to convert the coloring into the old Int format
        coloring = params[:coloring]

        coloringInt = ColoringParamsInt[]
        for c in coloring
          idx = findfirst(a->a==c.cmap,important_cmaps())-1
          push!(coloringInt, ColoringParamsInt(c.cmin, c.cmax, idx))
        end
        params[:coloring] = coloringInt

        c = params[:coloringBG]
        idx = findfirst(a->a==c.cmap,important_cmaps())-1
        params[:coloringBG] = ColoringParamsInt(c.cmin, c.cmax, idx)

        addVisu(mpilab[], params)
      catch e
        showError(e)
      end
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
  refdata = (m.dataBG == nothing) ? m.data[1,:,:,:,:] : m.dataBG

  if refdata != nothing

    if size(refdata,4) != sfw
      @idle_add_guarded set_gtk_property!(m["adjFrames"],:value, 1)
      @idle_add_guarded set_gtk_property!(m["adjFrames"],:upper,size(m.data,Axis{:time}))
    end

    if size(refdata,1) != sxw || size(refdata,2) != syw || size(refdata,3) != szw
      @idle_add_guarded set_gtk_property!(m["adjSliceX"],:upper,size(refdata,1))
      @idle_add_guarded set_gtk_property!(m["adjSliceY"],:upper,size(refdata,2))
      @idle_add_guarded set_gtk_property!(m["adjSliceZ"],:upper,size(refdata,3))

      @idle_add_guarded set_gtk_property!(m["adjSliceX"],:value,max(div(size(refdata,1),2),1))
      @idle_add_guarded set_gtk_property!(m["adjSliceY"],:value,max(div(size(refdata,2),2),1))
      @idle_add_guarded set_gtk_property!(m["adjSliceZ"],:value,max(div(size(refdata,3),2),1))
    end
  end
  return
end

function updateData!(m::DataViewerWidget, data::ImageMeta{T,3}, dataBG=nothing; kargs...) where T
  ax = ImageUtils.AxisArrays.axes(data)
  dAx = AxisArray(reshape(data.data.data, 1, size(data,1), size(data,2), size(data,3), 1),
                        Axis{:color}(1:1), ax[1], ax[2], ax[3],
                        Axis{:time}(range(0*unit(1u"s"),step=1u"s",length=1)))
  dIm = copyproperties(data, dAx)
  updateData!(m, dIm, dataBG; kargs...)
end

function updateData!(m::DataViewerWidget, data::ImageMeta{T,4}, dataBG=nothing; kargs...) where T
  ax = ImageUtils.AxisArrays.axes(data)

  if timeaxis(data) == nothing
    dAx = AxisArray(reshape(data.data.data, size(data,1), size(data,2),
                            size(data,3), size(data,4), 1),
                        ax[1], ax[2], ax[3], ax[4],
                        Axis{:time}(range(0*unit(1u"s"),step=1u"s",length=1)))
  else
    dAx = AxisArray(reshape(data.data.data, 1, size(data,1), size(data,2),
                            size(data,3), size(data,4)),
                            Axis{:color}(1:1), ax[1], ax[2], ax[3], ax[4])
  end

  dIm = copyproperties(data, dAx)
  updateData!(m, dIm, dataBG; kargs...)
end

function updateData!(m::DataViewerWidget, data::ImageMeta{T,5}, dataBG=nothing; params=nothing, ampPhase=false) where T
  #try
    m.updating = true
    numChan = size(data,Axis{:color})

    visible(m["mbFusion"], dataBG != nothing)
    visible(m["lbFusion"], dataBG != nothing)
    visible(m["sepFusion"], dataBG != nothing)

    multiChannel = numChan > 1
    visible(m["cbBlendChannels"], multiChannel)
    visible(m["cbChannel"], multiChannel)
    visible(m["lbChannel"], multiChannel)


    if m.data == nothing || (size(m.data,Axis{:color}) != numChan)
      m.coloring = Array{ColoringParams}(undef,numChan)
      if numChan == 1
        m.coloring[1] = ColoringParams(0.0,1.0,"viridis")
      end
      if numChan > 2
        for l=1:numChan
          m.coloring[l] = ColoringParams(0.0,1.0,l)
        end
      end
      if numChan == 2
        if ampPhase
          m.coloring[1] = ColoringParams(0.0,1.0,"viridis")
          m.coloring[2] = ColoringParams(0.0,1.0,"viridis")
        else
          m.coloring[1] = ColoringParams(0.0,1.0,"blue")
          m.coloring[2] = ColoringParams(0.0,1.0,"red")
        end
      end

      @idle_add_guarded begin
          empty!(m["cbChannel"])
          for i=1:numChan
            push!(m["cbChannel"], "$i")
          end
          set_gtk_property!(m["cbChannel"],:active,0)
          updateColoringWidgets( m )
      end

      @idle_add_guarded begin
          strProfile = ["x direction", "y direction", "z direction","temporal"]
          empty!(m["cbProfile"])
          nd = size(data,5) > 1 ? 4 : 3
          for i=1:nd
            push!(m["cbProfile"], strProfile[i])
          end
          set_gtk_property!(m["cbProfile"],:active,nd==4 ? 3 : 0)
      end

      set_gtk_property!(m["cbBlendChannels"], :active, numChan>1 )
      set_gtk_property!(m["cbComplexBlending"], :active, ampPhase)
    end

    m.data = data

    m.dataBGNotPermuted = dataBG
    m.dataBG = nothing
    permuteBGData(m)
    updateSliceWidgets(m)
    m.updating = false
    showData(m)
    @idle_add_guarded set_gtk_property!(m["adjPixelResizeFactor"],:value, (dataBG==nothing) ? 5 : 1  )

    if params!=nothing
      if data != nothing
        params[:sliceX] = min(params[:sliceX],size(data,Axis{:x}))
        params[:sliceY] = min(params[:sliceY],size(data,Axis{:y}))
        params[:sliceZ] = min(params[:sliceZ],size(data,Axis{:z}))
      end
      setParams(m,params)
    end
  #catch ex
  #  @warn "Exception" ex stacktrace(catch_backtrace())
  #end
end

function updateColoringWidgets(m::DataViewerWidget)
  m.upgradeColoringWInProgress = true
  chan = max(get_gtk_property(m["cbChannel"],:active, Int64) + 1,1)
  @idle_add_guarded set_gtk_property!(m["adjCMin"],:value, m.coloring[chan].cmin)
  @idle_add_guarded set_gtk_property!(m["adjCMax"],:value, m.coloring[chan].cmax)
  idx = findfirst(a->a==m.coloring[chan].cmap,important_cmaps())-1
  @idle_add_guarded set_gtk_property!(m["cbCMaps"],:active, idx)
  m.upgradeColoringWInProgress = false
end

function updateColoring(m::DataViewerWidget)
  chan = max(get_gtk_property(m["cbChannel"],:active, Int64) + 1,1)
  cmin = get_gtk_property(m["adjCMin"],:value, Float64)
  cmax = get_gtk_property(m["adjCMax"],:value, Float64)
  cmap = important_cmaps()[get_gtk_property(m["cbCMaps"],:active, Int64)+1]
  m.coloring[chan] = ColoringParams(cmin,cmax,cmap)
end

function showData(m::DataViewerWidget)
  if !m.updating
   try
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
      maxval = [maximum(sliceColorDim(m.data,d)) for d=1:size(m.data,1)]
      minval = [minimum(sliceColorDim(m.data,d)) for d=1:size(m.data,1)]
      #if params[:frameProj] == 2 && ndims(m.data[1]) == 4
      #  maxval = [maximum(d) for d in data_]
      #  minval = [minimum(d) for d in data_]
      #end

      if m.dataBG != nothing
        slicesInRawData = ImageUtils.indexFromBGToFG(m.dataBG, data_, params)
        @debug "Slices in raw data:" slicesInRawData
        data = interpolateToRefImage(m.dataBG, data_, params)
        dataBG = interpolateToRefImage(m.dataBG, params)
      else
        # not ideal ....
        params[:sliceX] = min(params[:sliceX],size(m.data,Axis{:x}))
        params[:sliceY] = min(params[:sliceY],size(m.data,Axis{:y}))
        params[:sliceZ] = min(params[:sliceZ],size(m.data,Axis{:z}))

        data = data_
        slicesInRawData = slices
        dataBG = nothing
      end

      m.currentlyShownData = data

      if ndims(squeeze(data[1,:,:,:])) >= 2
        cdata_zx, cdata_zy, cdata_xy = getColoredSlices(data, dataBG, m.coloring, minval, maxval, params)
        isDrawSectionalLines = params[:showSlices] && proj != "MIP"
        isDrawRectangle = params[:showDFFOV]
        isDrawAxes = params[:showAxes]
        pixelSpacingBG = (dataBG==nothing) ? [0.002,0.002,0.001] : collect(converttometer(pixelspacing(dataBG)))
        sizeBG = (dataBG==nothing) ? [128,128,64] : collect(size(dataBG))
        drawImages(m,slices, isDrawSectionalLines, isDrawRectangle, isDrawAxes, cdata_zx, cdata_zy, cdata_xy,
                   [params[:transX], params[:transY], params[:transZ]], pixelSpacingBG, sizeBG)

        if ndims(m.data) >= 3 && slicesInRawData != (0,0,0)
          showProfile(m, params, slicesInRawData)
        end
        G_.current_page(m["nb2D3D"], 0)
        m.currentlyShownImages = [cdata_xy, cdata_zx, cdata_zy]
      else
        dat = vec(data_)
        p = Winston.FramedPlot(xlabel="x", ylabel="y")
        Winston.add(p, Winston.Curve(1:length(dat), dat, color="blue", linewidth=4))
        display(m.grid2D[1,1],p)
        G_.current_page(m["nb2D3D"], 1)

        #m.currentlyShownImages = cdata
      end
    end
  catch ex
    @info ex
    showError(ex)
  #  @warn "Exception" ex stacktrace(catch_backtrace())
  end
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
  params[:showAxes] = get_gtk_property(m["cbShowAxes"], :active, Bool)

  params[:profile] = get_gtk_property(m["cbProfile"], :active, Int64)

  params[:activeChannel] = max(get_gtk_property(m["cbChannel"],:active, Int64) + 1,1)

  return params
end

function setParams(m::DataViewerWidget, params)
  @idle_add_guarded set_gtk_property!(m["adjSliceX"], :value, params[:sliceX])
  @idle_add_guarded set_gtk_property!(m["adjSliceY"], :value, params[:sliceY])
  @idle_add_guarded set_gtk_property!(m["adjSliceZ"], :value, params[:sliceZ])
  @idle_add_guarded set_gtk_property!(m["adjFrames"], :value, params[:frame])
  @idle_add_guarded set_gtk_property!(m["cbSpatialMIP"], :active, params[:spatialMIP])
  m.coloring = Vector{ColoringParams}(undef,0)
  for col in params[:coloring]
    push!(m.coloring, ColoringParams(col.cmin, col.cmax, col.cmap))
  end
  updateColoringWidgets(m)
  @idle_add_guarded set_gtk_property!(m["entVisuName"], :text, params[:description])
  @idle_add_guarded set_gtk_property!(m["cbShowSlices"], :active, get(params,:showSlices,false))

  # The following is for backwards compatibility with a former data format
  # where instead of permuteBG and flipBG we stored permutionBG
  if haskey(params, :permutionBG)
    perm, flip = convertMode2PermFlip(params[:permutionBG])
    @idle_add_guarded set_gtk_property!(m["cbPermutes"], :active, findall(x->x==perm,permuteCombinations())[1] - 1)
    @idle_add_guarded set_gtk_property!(m["cbFlips"], :active, findall(x->x==flip,flippings())[1] - 1)
  else
    @idle_add_guarded set_gtk_property!(m["cbPermutes"], :active, findall(x->x==params[:permuteBG],permuteCombinations())[1] - 1)
    @idle_add_guarded set_gtk_property!(m["cbFlips"], :active, findall(x->x==params[:flipBG],flippings())[1] - 1)
  end

  @idle_add_guarded set_gtk_property!(m["adjTransX"], :value, params[:transX]*1000)
  @idle_add_guarded set_gtk_property!(m["adjTransY"], :value, params[:transY]*1000)
  @idle_add_guarded set_gtk_property!(m["adjTransZ"], :value, params[:transZ]*1000)
  @idle_add_guarded set_gtk_property!(m["adjRotX"], :value, params[:rotX])
  @idle_add_guarded set_gtk_property!(m["adjRotY"], :value, params[:rotY])
  @idle_add_guarded set_gtk_property!(m["adjRotZ"], :value, params[:rotZ])

  @idle_add_guarded set_gtk_property!(m["adjTransBGX"], :value, get(params,:transBGX,0.0)*1000)
  @idle_add_guarded set_gtk_property!(m["adjTransBGY"], :value, get(params,:transBGY,0.0)*1000)
  @idle_add_guarded set_gtk_property!(m["adjTransBGZ"], :value, get(params,:transBGZ,0.0)*1000)
  @idle_add_guarded set_gtk_property!(m["adjRotBGX"], :value, get(params,:rotBGX,0.0))
  @idle_add_guarded set_gtk_property!(m["adjRotBGY"], :value, get(params,:rotBGY,0.0))
  @idle_add_guarded set_gtk_property!(m["adjRotBGZ"], :value, get(params,:rotBGZ,0.0))

  @idle_add_guarded set_gtk_property!(m["adjCMinBG"], :value, params[:coloringBG].cmin)
  @idle_add_guarded set_gtk_property!(m["adjCMaxBG"], :value, params[:coloringBG].cmax)
  @idle_add_guarded set_gtk_property!(m["cbCMapsBG"], :active, params[:coloringBG].cmap)
  @idle_add_guarded set_gtk_property!(m["cbHideFG"], :active, get(params,:hideFG, false))
  @idle_add_guarded set_gtk_property!(m["cbHideBG"], :active, get(params,:hideBG, false))
  @idle_add_guarded set_gtk_property!(m["cbShowDFFOV"], :active, get(params,:showDFFOV, false))
  @idle_add_guarded set_gtk_property!(m["cbTranslucentBlending"], :active, get(params,:translucentBlending, false))
  @idle_add_guarded set_gtk_property!(m["cbSpatialBGMIP"], :active, get(params,:spatialMIPBG, false))

  @idle_add_guarded set_gtk_property!(m["adjTTPThresh"], :value, get(params,:TTPThresh, 0.4))
  @idle_add_guarded set_gtk_property!(m["cbFrameProj"], :active, get(params,:frameProj, 0))

  @idle_add_guarded set_gtk_property!(m["cbBlendChannels"], :active, get(params,:blendChannels, false))
  @idle_add_guarded set_gtk_property!(m["cbShowAxes"], :active, get(params,:showAxes, false))

  @idle_add_guarded set_gtk_property!(m["cbProfile"], :active, get(params,:profile, 0))

  showData(m)
end

function defaultVisuParams()
  params = Dict{Symbol,Any}()
  return params
end
