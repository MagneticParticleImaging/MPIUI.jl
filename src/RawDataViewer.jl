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

getindex(m::RawDataWidget, w::AbstractString) = G_.object(m.builder, w)
#getindex(m::RawDataWidget, w::AbstractString, T::Type) = object_(m.builder, w, T)

function RawDataWidget(filenameConfig=nothing)
  @info "Starting RawDataWidget"
  uifile = joinpath(@__DIR__,"builder","rawDataViewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxRawViewer")

  m = RawDataWidget( mainBox.handle, b,
                  zeros(Float32,0,0,0,0), zeros(Float32,0,0,0,0),
                  Canvas(), Canvas(),
                  1.0, "", false, false, false,
                  G_.object(b,"winHarmonicViewer"),
                  AdjustmentLeaf[], Canvas[], Vector{Vector{Float32}}())
  Gtk.gobject_move_ref(m, mainBox)

  @debug "Type constructed"

  push!(m["boxTD"],m.cTD)
  set_gtk_property!(m["boxTD"],:expand,m.cTD,true)

  push!(m["boxFD"],m.cFD)
  set_gtk_property!(m["boxFD"],:expand,m.cFD,true)

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
    push!(m.harmViewAdj, m["adjHarm$l"] )
    @idle_add set_gtk_property!(m["adjHarm$l"],:value,l+1)
    c = Canvas()

    push!(m["boxHarmView"],c)
    set_gtk_property!(m["boxHarmView"],:expand,c,true)
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
    signal_connect(m[sl], "value_changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Nothing, (), false, m )
  end

  @time for cb in ["cbShowBG","cbSubtractBG","cbShowAllPatches"]
    signal_connect(m[cb], :toggled) do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[cb], "toggled", Nothing, (), false, m)
  end

  @time for cb in ["cbCorrTF","cbSLCorr","cbAbsFrameAverage"]
    signal_connect(m[cb], :toggled) do w
      loadData(C_NULL, m)
    end
  end

  @time for cb in ["adjFrame"]
    signal_connect(m[cb], "value_changed") do w
      loadData(C_NULL, m)
    end
  end

  signal_connect(m["cbHarmonicViewer"], :toggled) do w
      harmViewOn = get_gtk_property(m["cbHarmonicViewer"], :active, Bool)
      @idle_add begin
        if harmViewOn
          clearHarmBuff(m)
          set_gtk_property!(m.winHarmView,:visible, true)
          showall(m.winHarmView)
        else
          set_gtk_property!(m.winHarmView,:visible, false)
        end
      end
  end

  @time for sl in ["entTDMinVal","entTDMaxVal","entFDMinVal","entFDMaxVal"]
    signal_connect(m[sl], "changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Nothing, (), false, m )
  end


  signal_connect(m.winHarmView, "delete-event") do widget, event
    #typeof(event)
    #@show event
    @idle_add set_gtk_property!(m["cbHarmonicViewer"], :active, false)
  end

  #@time signal_connect(loadData, m["cbCorrTF"], "toggled", Nothing, (), false, m)
 end
end



function loadData(widgetptr::Ptr, m::RawDataWidget)
  if !m.loadingData
    m.loadingData = true
    @info "Loading Data ..."


    if m.filenameData != "" && ispath(m.filenameData)
      f = MPIFile(m.filenameData)#, isCalib=false)
      params = MPIFiles.loadMetadata(f)
      params[:acqNumFGFrames] = acqNumFGFrames(f)
      params[:acqNumBGFrames] = acqNumBGFrames(f)

      @idle_add set_gtk_property!(m["adjFrame"], :upper, acqNumFGFrames(f))

      if get_gtk_property(m["cbAbsFrameAverage"], :active, Bool)
        frame = 1:acqNumFGFrames(f)
      else
        frame = max( get_gtk_property(m["adjFrame"], :value, Int64),1)
      end

      timePoints = rxTimePoints(f)
      deltaT = timePoints[2] - timePoints[1]

      u = getMeasurements(f, true, frames=frame,
                  bgCorrection=false, spectralLeakageCorrection = get_gtk_property(m["cbSLCorr"], :active, Bool),
                  tfCorrection=get_gtk_property(m["cbCorrTF"], :active, Bool))

      if acqNumBGFrames(f) > 0
        m.dataBG = getMeasurements(f, false, frames=measBGFrameIdx(f),
              bgCorrection=false, spectralLeakageCorrection = get_gtk_property(m["cbSLCorr"], :active, Bool),
              tfCorrection=get_gtk_property(m["cbCorrTF"], :active, Bool))
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
    chan = max(get_gtk_property(m["adjRxChan"], :value, Int64),1)
    patch = max(get_gtk_property(m["adjPatch"], :value, Int64),1)
    minTP = max(get_gtk_property(m["adjMinTP"], :value, Int64),1)
    maxTP = max(get_gtk_property(m["adjMaxTP"], :value, Int64),1)
    minFr = max(get_gtk_property(m["adjMinFre"], :value, Int64),1)
    maxFr = max(get_gtk_property(m["adjMaxFre"], :value, Int64),1)

    autoRangingTD = true
    autoRangingFD = true
    minValTD_ = tryparse(Float64,get_gtk_property( m["entTDMinVal"] ,:text,String))
    maxValTD_ = tryparse(Float64,get_gtk_property( m["entTDMaxVal"] ,:text,String))
    minValFD_ = tryparse(Float64,get_gtk_property( m["entFDMinVal"] ,:text,String))
    maxValFD_ = tryparse(Float64,get_gtk_property( m["entFDMaxVal"] ,:text,String))

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


    showFD = true
    if get_gtk_property(m["cbShowAllPatches"], :active, Bool)
      showFD = false
      minTP = 1
      maxTP = size(m.data,1)*size(m.data,3)

      data = vec(m.data[:,chan,:,1])

      minFr = 1
      maxFr = (div(length(data),2)+1)

      if length(m.dataBG) > 0 && get_gtk_property(m["cbSubtractBG"], :active, Bool)
        data[:] .-=  vec(mean(m.dataBG[:,chan,:,:],dims=3))
      end
    else
      if get_gtk_property(m["cbAbsFrameAverage"], :active, Bool)
        dataFD = rfft(m.data[:,chan,patch,:],1)
        dataFD_ = vec(mean(abs.(dataFD), dims=2))
        data = irfft(dataFD_, 2*size(dataFD_, 1) -2)

        if length(m.dataBG) > 0
          dataBGFD = rfft(m.dataBG[:,chan,patch,:],1)
          dataBGFD_ = vec(mean(abs.(dataBGFD), dims=2))
          dataBG = irfft(dataBGFD_, 2*size(dataBGFD_, 1) -2)
          if get_gtk_property(m["cbSubtractBG"], :active, Bool)
            data[:] .-=  dataBG
          end
        end
      else
        data = vec(m.data[:,chan,patch,1])
        if length(m.dataBG) > 0
          #dataBG = vec(m.dataBG[:,chan,patch,1] .- mean(m.dataBG[:,chan,patch,:], dims=2))
          dataBG = vec( mean(m.dataBG[:,chan,patch,:],dims=2))
          if get_gtk_property(m["cbSubtractBG"], :active, Bool)
            data[:] .-=  dataBG
          end
        end
      end
    end

    timePoints = (0:(length(data)-1)).*m.deltaT
    numFreq = floor(Int, length(data) ./ 2 .+ 1)

    maxPoints = 300
    sp = length(minTP:maxTP) > maxPoints ? round(Int,length(minTP:maxTP) / maxPoints)  : 1
    p1 = Winston.plot(timePoints[minTP:sp:maxTP],data[minTP:sp:maxTP],"b-",linewidth=5)
    Winston.ylabel("u / V")
    Winston.xlabel("t / ms")
    if !autoRangingTD
      Winston.ylim(minValTD, maxValTD)
    end

    if showFD
      freq = collect(0:(numFreq-1))./(numFreq-1)./m.deltaT./2.0
      freqdata = abs.(rfft(data)) / length(data)

      ls = "b-" #length(minFr:maxFr) > 150 ? "b-" : "b-o"
      p2 = Winston.semilogy(freq[minFr:maxFr],freqdata[minFr:maxFr],ls,linewidth=5)
      #Winston.ylabel("u / V")
      Winston.xlabel("f / kHz")
      if !autoRangingFD
          Winston.ylim(minValFD, maxValFD)
      end
    end

    if length(m.dataBG) > 0 && get_gtk_property(m["cbShowBG"], :active, Bool)
      Winston.plot(p1,timePoints[minTP:maxTP],dataBG[minTP:maxTP],"k--",linewidth=2)

      if showFD
        ls = length(minFr:maxFr) > 150 ? "k-" : "k-x"
        Winston.plot(p2,freq[minFr:maxFr],abs.(rfft(dataBG)[minFr:maxFr]) / length(dataBG),
                  ls, linewidth=2, ylog=true)
      end
    end
    display(m.cTD, p1)
    if showFD
      display(m.cFD, p2)
    end

    ### Harmonic Viewer ###
    if  get_gtk_property(m["cbHarmonicViewer"], :active, Bool) && showFD
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
    @idle_add set_gtk_property!(m["adjFrame"],:upper,size(data,4))
    if !(1 <= get_gtk_property(m["adjFrame"],:value,Int64) <= size(data,4))
      @idle_add set_gtk_property!(m["adjFrame"],:value,1)
    end
  end
  @idle_add set_gtk_property!(m["adjRxChan"],:upper,size(data,2))
  if !(1 <= get_gtk_property(m["adjRxChan"],:value,Int64) <= size(data,2))
    @idle_add set_gtk_property!(m["adjRxChan"],:value,1)
  end
  @idle_add set_gtk_property!(m["adjPatch"],:upper,size(data,3))
  if !(1 <= get_gtk_property(m["adjPatch"],:value,Int64) <= size(data,3))
    @idle_add set_gtk_property!(m["adjPatch"],:value,1)
  end
  @idle_add set_gtk_property!(m["adjMinTP"],:upper,size(data,1))
  if !(1 <= get_gtk_property(m["adjMinTP"],:value,Int64) <= size(data,1))
    @idle_add set_gtk_property!(m["adjMinTP"],:value,1)
  end
  @idle_add set_gtk_property!(m["adjMaxTP"],:upper,size(data,1))
  if !(1 <= get_gtk_property(m["adjMaxTP"],:value,Int64) <= size(data,1))
    @idle_add set_gtk_property!(m["adjMaxTP"],:value,size(data,1))
  end
  @idle_add set_gtk_property!(m["adjMinFre"],:upper,div(size(data,1),2)+1)
  if !(1 <= get_gtk_property(m["adjMinFre"],:value,Int64) <= div(size(data,1),2)+1)
    @idle_add set_gtk_property!(m["adjMinFre"],:value,1)
  end
  @idle_add set_gtk_property!(m["adjMaxFre"],:upper,div(size(data,1),2)+1)
  if !(1 <= get_gtk_property(m["adjMaxFre"],:value,Int64) <= div(size(data,1),2)+1)
    @idle_add set_gtk_property!(m["adjMaxFre"],:value,div(size(data,1),2)+1)
  end

  for l=1:5
    @idle_add set_gtk_property!(m.harmViewAdj[l],:upper,div(size(data,1),2)+1)
  end

  m.updatingData = false
  showData(C_NULL,m)
end

function updateData(m::RawDataWidget, filename::String)
  m.filenameData = filename
  @idle_add set_gtk_property!(m["adjFrame"],:upper,1)
  @idle_add set_gtk_property!(m["adjFrame"],:value,1)
  loadData(C_NULL, m)
  return nothing
end
