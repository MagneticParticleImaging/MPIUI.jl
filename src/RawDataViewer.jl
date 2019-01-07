import Base: getindex

mutable struct RawDataWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::Builder
  data::Array{Float32,4}
  dataBG::Array{Float32,4}
  cTD::Canvas
  cFD::Canvas
  deltaT::Float64
  filenameData::String
  loadingData::Bool
  updatingData::Bool
  fileModus::Bool
  winHarmView::WindowLeaf
  harmViewAdj::Vector{AdjustmentLeaf}
  harmViewCanvas::Vector{Canvas}
  harmBuff::Vector{Vector{Float32}}
end

#getindex(m::RawDataWidget, w::AbstractString) = G_.object(m.builder, w)
getindex(m::RawDataWidget, w::AbstractString, T::Type) = object_(m.builder, w, T)

function RawDataWidget(filenameConfig=nothing)
  @info "Starting RawDataWidget"
  uifile = joinpath(@__DIR__,"builder","rawDataViewer.ui")

  b = Builder(filename=uifile)
  mainBox = object_(b, "boxRawViewer", BoxLeaf)

  m = RawDataWidget( mainBox.handle, b,
                  zeros(Float32,0,0,0,0), zeros(Float32,0,0,0,0),
                  Canvas(), Canvas(),
                  1.0, "", false, false, false,
                  object_(b,"winHarmonicViewer",WindowLeaf),
                  AdjustmentLeaf[], Canvas[], Vector{Vector{Float32}}())
  Gtk.gobject_move_ref(m, mainBox)

  @debug "Type constructed"

  push!(m["boxTD",BoxLeaf],m.cTD)
  set_gtk_property!(m["boxTD",BoxLeaf],:expand,m.cTD,true)

  push!(m["boxFD",BoxLeaf],m.cFD)
  set_gtk_property!(m["boxFD",BoxLeaf],:expand,m.cFD,true)

  @debug "InitCallbacks"

  initHarmView(m)

  initCallbacks(m)

  @info "Finished starting RawDataWidget"

  return m
end

function initHarmView(m::RawDataWidget)

  m.harmViewAdj = AdjustmentLeaf[]
  m.harmViewCanvas = Canvas[]
  m.harmBuff = Vector{Vector{Float32}}()

  for l=1:5
    push!(m.harmViewAdj, m["adjHarm$l",AdjustmentLeaf] )
    Gtk.@sigatom set_gtk_property!(m["adjHarm$l",AdjustmentLeaf],:value,l+1)
    c = Canvas()

    push!(m["boxHarmView", BoxLeaf],c)
    set_gtk_property!(m["boxHarmView", BoxLeaf],:expand,c,true)
    push!(m.harmViewCanvas, c)
    push!(m.harmBuff, zeros(Float32,0))
  end

end

function clearHarmBuff(m::RawDataWidget)
  for l=1:5
    m.harmBuff[l] = zeros(Float32,0)
  end
end

function initCallbacks(m_::RawDataWidget)
 let m=m_
  @time for sl in ["adjPatch","adjRxChan","adjMinTP","adjMaxTP",
                   "adjMinFre","adjMaxFre"]
    signal_connect(m[sl,AdjustmentLeaf], "value_changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Nothing, (), false, m )
  end

  @time for cb in ["cbShowBG","cbSubtractBG","cbShowAllPatches"]
    signal_connect(m[cb,CheckButtonLeaf], :toggled) do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[cb], "toggled", Nothing, (), false, m)
  end

  @time for cb in ["cbCorrTF","cbSLCorr","cbAbsFrameAverage"]
    signal_connect(m[cb,CheckButtonLeaf], :toggled) do w
      loadData(C_NULL, m)
    end
  end

  @time for cb in ["adjFrame"]
    signal_connect(m[cb,AdjustmentLeaf], "value_changed") do w
      loadData(C_NULL, m)
    end
  end

  signal_connect(m["cbHarmonicViewer",CheckButtonLeaf], :toggled) do w
      harmViewOn = get_gtk_property(m["cbHarmonicViewer",CheckButtonLeaf], :active, Bool)
      if harmViewOn
        clearHarmBuff(m)
        @Gtk.sigatom set_gtk_property!(m.winHarmView,:visible, true)
        @Gtk.sigatom showall(m.winHarmView)
      else
        @Gtk.sigatom set_gtk_property!(m.winHarmView,:visible, false)
      end
  end

  @time for sl in ["entTDMinVal","entTDMaxVal","entFDMinVal","entFDMaxVal"]
    signal_connect(m[sl,EntryLeaf], "changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Nothing, (), false, m )
  end


  signal_connect(m.winHarmView, "delete-event") do widget, event
    #typeof(event)
    #@show event
    @Gtk.sigatom set_gtk_property!(m["cbHarmonicViewer",CheckButtonLeaf], :active, false)
  end

  #@time signal_connect(loadData, m["cbCorrTF"], "toggled", Nothing, (), false, m)
 end
end



function loadData(widgetptr::Ptr, m::RawDataWidget)
  if !m.loadingData
    m.loadingData = true
    @Gtk.sigatom @info "Loading Data ..."


    if m.filenameData != "" && ispath(m.filenameData)
      f = MPIFile(m.filenameData)#, isCalib=false)
      params = MPIFiles.loadMetadata(f)
      params["acqNumFGFrames"] = acqNumFGFrames(f)
      params["acqNumBGFrames"] = acqNumBGFrames(f)

      Gtk.@sigatom set_gtk_property!(m["adjFrame",AdjustmentLeaf], :upper, acqNumFGFrames(f))

      if get_gtk_property(m["cbAbsFrameAverage",CheckButtonLeaf], :active, Bool)
        frame = 1:acqNumFGFrames(f)
      else
        frame = max( get_gtk_property(m["adjFrame",AdjustmentLeaf], :value, Int64),1)
      end

      timePoints = rxTimePoints(f)
      deltaT = timePoints[2] - timePoints[1]

      u = getMeasurements(f, true, frames=frame,
                  bgCorrection=false, spectralLeakageCorrection = get_gtk_property(m["cbSLCorr",CheckButtonLeaf], :active, Bool),
                  tfCorrection=get_gtk_property(m["cbCorrTF",CheckButtonLeaf], :active, Bool))

      if acqNumBGFrames(f) > 0
        m.dataBG = getMeasurements(f, false, frames=measBGFrameIdx(f),
              bgCorrection=false, spectralLeakageCorrection = get_gtk_property(m["cbSLCorr",CheckButtonLeaf], :active, Bool),
              tfCorrection=get_gtk_property(m["cbCorrTF",CheckButtonLeaf], :active, Bool))
      else
        m.dataBG = zeros(Float32,0,0,0,0)
      end

      updateData(m, u, deltaT, true)
    end
    m.loadingData = false
  end
  return nothing
end


function showData(widgetptr::Ptr, m::RawDataWidget)

  if length(m.data) > 0 && !m.updatingData
    chan = get_gtk_property(m["adjRxChan",AdjustmentLeaf], :value, Int64)
    patch = get_gtk_property(m["adjPatch",AdjustmentLeaf], :value, Int64)
    minTP = get_gtk_property(m["adjMinTP",AdjustmentLeaf], :value, Int64)
    maxTP = get_gtk_property(m["adjMaxTP",AdjustmentLeaf], :value, Int64)
    minFr = get_gtk_property(m["adjMinFre",AdjustmentLeaf], :value, Int64)
    maxFr = get_gtk_property(m["adjMaxFre",AdjustmentLeaf], :value, Int64)

    autoRangingTD = true
    autoRangingFD = true
    minValTD_ = tryparse(Float64,get_gtk_property( m["entTDMinVal",EntryLeaf] ,:text,String))
    maxValTD_ = tryparse(Float64,get_gtk_property( m["entTDMaxVal",EntryLeaf] ,:text,String))
    minValFD_ = tryparse(Float64,get_gtk_property( m["entFDMinVal",EntryLeaf] ,:text,String))
    maxValFD_ = tryparse(Float64,get_gtk_property( m["entFDMaxVal",EntryLeaf] ,:text,String))

    if minValTD_ != nothing && maxValTD_ != nothing
      minValTD = minValTD_
      maxValTD = maxValTD_
      autoRangingTD = false
    end

    if minValFD_ != nothing && maxValFD_ != nothing
      minValFD = minValFD_
      maxValFD = maxValFD_
      autoRangingFD = false
    end


    if get_gtk_property(m["cbShowAllPatches",CheckButtonLeaf], :active, Bool)
      minTP = 1
      maxTP = size(m.data,1)*size(m.data,3)

      data = vec(m.data[:,chan,:,1])

      minFr = 1
      maxFr = (div(length(data),2)+1)

      if length(m.dataBG) > 0 && get_gtk_property(m["cbSubtractBG",CheckButtonLeaf], :active, Bool)
        data[:] .-=  vec(mean(m.dataBG[:,chan,:,:],dims=3))
      end
    else
      if get_gtk_property(m["cbAbsFrameAverage",CheckButtonLeaf], :active, Bool)
        dataFD = rfft(m.data[:,chan,patch,:],1)
        dataFD_ = vec(mean(abs.(dataFD), dims=2))
        data = irfft(dataFD_, 2*size(dataFD_, 1) -2)

        if length(m.dataBG) > 0
          dataBGFD = rfft(m.dataBG[:,chan,patch,:],1)
          dataBGFD_ = vec(mean(abs.(dataBGFD), dims=2))
          dataBG = irfft(dataBGFD_, 2*size(dataBGFD_, 1) -2)
          if get_gtk_property(m["cbSubtractBG",CheckButtonLeaf], :active, Bool)
            data[:] .-=  dataBG
          end
        end
      else
        data = vec(m.data[:,chan,patch,1])
        if length(m.dataBG) > 0
          #dataBG = vec(m.dataBG[:,chan,patch,1] .- mean(m.dataBG[:,chan,patch,:], dims=2))
          dataBG = vec( mean(m.dataBG[:,chan,patch,:],dims=2))
          if get_gtk_property(m["cbSubtractBG",CheckButtonLeaf], :active, Bool)
            data[:] .-=  dataBG
          end
        end
      end
    end

    timePoints = (0:(length(data)-1)).*m.deltaT
    numFreq = floor(Int, length(data) ./ 2 .+ 1)
    freq = collect(0:(numFreq-1))./(numFreq-1)./m.deltaT./2.0

    freqdata = abs.(rfft(data)) / length(data)

    p1 = Winston.plot(timePoints[minTP:maxTP],data[minTP:maxTP],"b-",linewidth=5)
    Winston.ylabel("u / V")
    Winston.xlabel("t / ms")
    if !autoRangingTD
      Winston.ylim(minValTD, maxValTD)
    end
    ls = "b-" #length(minFr:maxFr) > 150 ? "b-" : "b-o"
    p2 = Winston.semilogy(freq[minFr:maxFr],freqdata[minFr:maxFr],ls,linewidth=5)
    #Winston.ylabel("u / V")
    Winston.xlabel("f / kHz")
    if !autoRangingFD
        Winston.ylim(minValFD, maxValFD)
    end

    if length(m.dataBG) > 0 && get_gtk_property(m["cbShowBG",CheckButtonLeaf], :active, Bool)
      Winston.plot(p1,timePoints[minTP:maxTP],dataBG[minTP:maxTP],"k--",linewidth=2)
      ls = length(minFr:maxFr) > 150 ? "k-" : "k-x"
      Winston.plot(p2,freq[minFr:maxFr],abs.(rfft(dataBG)[minFr:maxFr]) / length(dataBG),
                  ls, linewidth=2, ylog=true)
    end
    display(m.cTD ,p1)
    display(m.cFD ,p2)


    ### Harmonic Viewer ###
    if  get_gtk_property(m["cbHarmonicViewer",CheckButtonLeaf], :active, Bool)
      for l=1:5
        f = get_gtk_property(m.harmViewAdj[l], :value, Int64)
        push!(m.harmBuff[l], freqdata[f])

        p = Winston.semilogy(m.harmBuff[l],"b-o", linewidth=5)
        Winston.ylabel("Harmonic $f")
        Winston.xlabel("Time")
        display(m.harmViewCanvas[l] ,p)
      end
    end
  end
  return nothing
end


function updateData(m::RawDataWidget, data::Array, deltaT=1.0, fileModus=false)
  m.updatingData = true

  m.data = data
  m.deltaT = deltaT .* 1000 # convert to ms and kHz
  m.fileModus = fileModus

  if !fileModus
    Gtk.@sigatom set_gtk_property!(m["adjFrame",AdjustmentLeaf],:upper,size(data,4))
    if !(1 <= get_gtk_property(m["adjFrame",AdjustmentLeaf],:value,Int64) <= size(data,4))
      Gtk.@sigatom set_gtk_property!(m["adjFrame",AdjustmentLeaf],:value,1)
    end
  end
  Gtk.@sigatom set_gtk_property!(m["adjRxChan",AdjustmentLeaf],:upper,size(data,2))
  if !(1 <= get_gtk_property(m["adjRxChan",AdjustmentLeaf],:value,Int64) <= size(data,2))
    Gtk.@sigatom set_gtk_property!(m["adjRxChan",AdjustmentLeaf],:value,1)
  end
  Gtk.@sigatom set_gtk_property!(m["adjPatch",AdjustmentLeaf],:upper,size(data,3))
  if !(1 <= get_gtk_property(m["adjPatch",AdjustmentLeaf],:value,Int64) <= size(data,3))
    Gtk.@sigatom set_gtk_property!(m["adjPatch",AdjustmentLeaf],:value,1)
  end
  Gtk.@sigatom set_gtk_property!(m["adjMinTP",AdjustmentLeaf],:upper,size(data,1))
  if !(1 <= get_gtk_property(m["adjMinTP",AdjustmentLeaf],:value,Int64) <= size(data,1))
    Gtk.@sigatom set_gtk_property!(m["adjMinTP",AdjustmentLeaf],:value,1)
  end
  Gtk.@sigatom set_gtk_property!(m["adjMaxTP",AdjustmentLeaf],:upper,size(data,1))
  if !(1 <= get_gtk_property(m["adjMaxTP",AdjustmentLeaf],:value,Int64) <= size(data,1))
    Gtk.@sigatom set_gtk_property!(m["adjMaxTP",AdjustmentLeaf],:value,size(data,1))
  end
  Gtk.@sigatom set_gtk_property!(m["adjMinFre",AdjustmentLeaf],:upper,div(size(data,1),2)+1)
  if !(1 <= get_gtk_property(m["adjMinFre",AdjustmentLeaf],:value,Int64) <= div(size(data,1),2)+1)
    Gtk.@sigatom set_gtk_property!(m["adjMinFre",AdjustmentLeaf],:value,1)
  end
  Gtk.@sigatom set_gtk_property!(m["adjMaxFre",AdjustmentLeaf],:upper,div(size(data,1),2)+1)
  if !(1 <= get_gtk_property(m["adjMaxFre",AdjustmentLeaf],:value,Int64) <= div(size(data,1),2)+1)
    Gtk.@sigatom set_gtk_property!(m["adjMaxFre",AdjustmentLeaf],:value,div(size(data,1),2)+1)
  end

  for l=1:5
    Gtk.@sigatom set_gtk_property!(m.harmViewAdj[l],:upper,div(size(data,1),2)+1)
  end

  m.updatingData = false
  showData(C_NULL,m)
end

function updateData(m::RawDataWidget, filename::String)
  m.filenameData = filename
  Gtk.@sigatom set_gtk_property!(m["adjFrame",AdjustmentLeaf],:upper,1)
  Gtk.@sigatom set_gtk_property!(m["adjFrame",AdjustmentLeaf],:value,1)
  loadData(C_NULL, m)
  return nothing
end
