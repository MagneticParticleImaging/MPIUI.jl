import Base: getindex

type RawDataWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::Builder
  data::Array{Float32,4}
  dataBG::Array{Float32,4}
  #params
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
  println("Starting RawDataWidget")
  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","rawDataViewer.ui")

  b = Builder(filename=uifile)
  mainBox = object_(b, "boxRawViewer", BoxLeaf)

  m = RawDataWidget( mainBox.handle, b,
                  zeros(Float32,0,0,0,0), zeros(Float32,0,0,0,0),
                  Canvas(), Canvas(),
                  1.0, "", false, false, false,
                  object_(b,"winHarmonicViewer",WindowLeaf),
                  AdjustmentLeaf[], Canvas[], Vector{Vector{Float32}}())
  Gtk.gobject_move_ref(m, mainBox)

  println("Type constructed")

  push!(m["boxTD",BoxLeaf],m.cTD)
  setproperty!(m["boxTD",BoxLeaf],:expand,m.cTD,true)

  push!(m["boxFD",BoxLeaf],m.cFD)
  setproperty!(m["boxFD",BoxLeaf],:expand,m.cFD,true)

  println("InitCallbacks")

  initHarmView(m)

  initCallbacks(m)

  println("Finished")

  return m
end

function initHarmView(m::RawDataWidget)

  m.harmViewAdj = AdjustmentLeaf[]
  m.harmViewCanvas = Canvas[]
  m.harmBuff = Vector{Vector{Float32}}()

  for l=1:5
    push!(m.harmViewAdj, m["adjHarm$l",AdjustmentLeaf] )
    Gtk.@sigatom setproperty!(m["adjHarm$l",AdjustmentLeaf],:value,l+1)
    c = Canvas()

    push!(m["boxHarmView", BoxLeaf],c)
    setproperty!(m["boxHarmView", BoxLeaf],:expand,c,true)
    push!(m.harmViewCanvas, c)
    push!(m.harmBuff, zeros(Float32,0))
  end

end

function clearHarmBuff(m::RawDataWidget)
  for l=1:5
    m.harmBuff[l] = zeros(Float32,0)
  end
end

function initCallbacks(m::RawDataWidget)

  @time for sl in ["adjPatch","adjRxChan","adjMinTP","adjMaxTP",
                   "adjMinFre","adjMaxFre"]
    signal_connect(m[sl,AdjustmentLeaf], "value_changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Void, (), false, m )
  end

  @time for cb in ["cbShowBG", "cbAverage","cbSubtractBG","cbShowAllPatches"]
    signal_connect(m[cb,CheckButtonLeaf], :toggled) do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[cb], "toggled", Void, (), false, m)
  end

  @time for cb in ["cbCorrTF"]
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
      harmViewOn = getproperty(m["cbHarmonicViewer",CheckButtonLeaf], :active, Bool)
      if harmViewOn
        clearHarmBuff(m)
        @Gtk.sigatom setproperty!(m.winHarmView,:visible, true)
        @Gtk.sigatom showall(m.winHarmView)
      else
        @Gtk.sigatom setproperty!(m.winHarmView,:visible, false)
      end
  end


  signal_connect(m.winHarmView, "delete-event") do widget, event
    #typeof(event)
    #@show event
    @Gtk.sigatom setproperty!(m["cbHarmonicViewer",CheckButtonLeaf], :active, false)
  end

  #@time signal_connect(loadData, m["cbCorrTF"], "toggled", Void, (), false, m)

  #signal_connect(m["cbExpNum"], :changed) do w
  #  loadExperiment(C_NULL, m)
  #end

end



function loadData(widgetptr::Ptr, m::RawDataWidget)
  if !m.loadingData
    m.loadingData = true
    @Gtk.sigatom println("Loading Data ...")


    if m.filenameData != "" && ispath(m.filenameData)
      f = MPIFile(m.filenameData)
      params = MPIFiles.loadMetadata(f)
      params["acqNumFGFrames"] = acqNumFGFrames(f)
      params["acqNumBGFrames"] = acqNumBGFrames(f)

      Gtk.@sigatom setproperty!(m["adjFrame",AdjustmentLeaf], :upper, acqNumFGFrames(f))

      frame = max( getproperty(m["adjFrame",AdjustmentLeaf], :value, Int64),1)

      #setParams(m, params)

      u = getMeasurements(f, true, frames=frame,
                  bgCorrection=false,
                  tfCorrection=getproperty(m["cbCorrTF",CheckButtonLeaf], :active, Bool))

      timePoints = rxTimePoints(f)
      deltaT = timePoints[2] - timePoints[1]

      if acqNumBGFrames(f) > 0
        m.dataBG = getMeasurements(f, false, frames=measBGFrameIdx(f),
              bgCorrection=false,
              tfCorrection=getproperty(m["cbCorrTF",CheckButtonLeaf], :active, Bool))
      end
      updateData(m, u, deltaT, true)
    end
    m.loadingData = false
  end
  return nothing
end


function showData(widgetptr::Ptr, m::RawDataWidget)

  if length(m.data) > 0 && !m.updatingData
    chan = getproperty(m["adjRxChan",AdjustmentLeaf], :value, Int64)
    patch = getproperty(m["adjPatch",AdjustmentLeaf], :value, Int64)
    minTP = getproperty(m["adjMinTP",AdjustmentLeaf], :value, Int64)
    maxTP = getproperty(m["adjMaxTP",AdjustmentLeaf], :value, Int64)
    minFr = getproperty(m["adjMinFre",AdjustmentLeaf], :value, Int64)
    maxFr = getproperty(m["adjMaxFre",AdjustmentLeaf], :value, Int64)

    if getproperty(m["cbShowAllPatches",CheckButtonLeaf], :active, Bool)
      minTP = 1
      maxTP = size(m.data,1)*size(m.data,3)

      data = vec(m.data[:,chan,:,1])
      if length(m.dataBG) > 0 && getproperty(m["cbSubtractBG",CheckButtonLeaf], :active, Bool)
        data[:] .-=  vec(mean(m.dataBG[:,chan,:,:],3))
      end
    else
      data = vec(m.data[:,chan,patch,1])
      if length(m.dataBG) > 0 && getproperty(m["cbSubtractBG",CheckButtonLeaf], :active, Bool)
        data[:] .-=  vec(mean(m.dataBG[:,chan,patch,:],2))
      end
    end

    timePoints = (0:(length(data)-1)).*m.deltaT
    numFreq = floor(Int, length(data) ./ 2 .+ 1)
    freq = collect(0:(numFreq-1))./(numFreq-1)./m.deltaT./2.0

    freqdata = abs.(rfft(data))

    p1 = Winston.plot(timePoints[minTP:maxTP],data[minTP:maxTP],"b-",linewidth=5)
    Winston.ylabel("u / V")
    Winston.xlabel("t / ms")
    p2 = Winston.semilogy(freq[minFr:maxFr],freqdata[minFr:maxFr],"b-o", linewidth=5)
    #Winston.ylabel("u / V")
    Winston.xlabel("f / kHz")
    if length(m.dataBG) > 0 && getproperty(m["cbShowBG",CheckButtonLeaf], :active, Bool)
      mid = div(size(m.dataBG,4),2)
      #dataBG = vec(m.dataBG[:,chan,patch,1] .- mean(m.dataBG[:,chan,patch,:],2))
      dataBG = vec( mean(m.dataBG[:,chan,patch,:],2))

      Winston.plot(p1,timePoints[minTP:maxTP],dataBG[minTP:maxTP],"k--",linewidth=2)
      Winston.plot(p2,freq[minFr:maxFr],abs.(rfft(dataBG)[minFr:maxFr]),"k-x",
                   linewidth=2, ylog=true)
    end
    display(m.cTD ,p1)
    display(m.cFD ,p2)


    ### Harmonic Viewer ###
    if  getproperty(m["cbHarmonicViewer",CheckButtonLeaf], :active, Bool)
      for l=1:5
        f = getproperty(m.harmViewAdj[l], :value, Int64)
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
    Gtk.@sigatom setproperty!(m["adjFrame",AdjustmentLeaf],:upper,size(data,4))
    if !(1 <= getproperty(m["adjFrame",AdjustmentLeaf],:value,Int64) <= size(data,4))
      Gtk.@sigatom setproperty!(m["adjFrame",AdjustmentLeaf],:value,1)
    end
  end
  Gtk.@sigatom setproperty!(m["adjRxChan",AdjustmentLeaf],:upper,size(data,2))
  if !(1 <= getproperty(m["adjRxChan",AdjustmentLeaf],:value,Int64) <= size(data,2))
    Gtk.@sigatom setproperty!(m["adjRxChan",AdjustmentLeaf],:value,1)
  end
  Gtk.@sigatom setproperty!(m["adjPatch",AdjustmentLeaf],:upper,size(data,3))
  if !(1 <= getproperty(m["adjPatch",AdjustmentLeaf],:value,Int64) <= size(data,3))
    Gtk.@sigatom setproperty!(m["adjPatch",AdjustmentLeaf],:value,1)
  end
  Gtk.@sigatom setproperty!(m["adjMinTP",AdjustmentLeaf],:upper,size(data,1))
  if !(1 <= getproperty(m["adjMinTP",AdjustmentLeaf],:value,Int64) <= size(data,1))
    Gtk.@sigatom setproperty!(m["adjMinTP",AdjustmentLeaf],:value,1)
  end
  Gtk.@sigatom setproperty!(m["adjMaxTP",AdjustmentLeaf],:upper,size(data,1))
  if !(1 <= getproperty(m["adjMaxTP",AdjustmentLeaf],:value,Int64) <= size(data,1))
    Gtk.@sigatom setproperty!(m["adjMaxTP",AdjustmentLeaf],:value,size(data,1))
  end
  Gtk.@sigatom setproperty!(m["adjMinFre",AdjustmentLeaf],:upper,div(size(data,1),2)+1)
  if !(1 <= getproperty(m["adjMinFre",AdjustmentLeaf],:value,Int64) <= div(size(data,1),2)+1)
    Gtk.@sigatom setproperty!(m["adjMinFre",AdjustmentLeaf],:value,1)
  end
  Gtk.@sigatom setproperty!(m["adjMaxFre",AdjustmentLeaf],:upper,div(size(data,1),2)+1)
  if !(1 <= getproperty(m["adjMaxFre",AdjustmentLeaf],:value,Int64) <= div(size(data,1),2)+1)
    Gtk.@sigatom setproperty!(m["adjMaxFre",AdjustmentLeaf],:value,div(size(data,1),2)+1)
  end

  for l=1:5
    Gtk.@sigatom setproperty!(m.harmViewAdj[l],:upper,div(size(data,1),2)+1)
  end

  m.updatingData = false
  showData(C_NULL,m)
end

function updateData(m::RawDataWidget, filename::String)
  m.filenameData = filename
  Gtk.@sigatom setproperty!(m["adjFrame",AdjustmentLeaf],:upper,1)
  Gtk.@sigatom setproperty!(m["adjFrame",AdjustmentLeaf],:value,1)
  loadData(C_NULL, m)
  return nothing
end
