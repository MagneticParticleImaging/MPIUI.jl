import Base: getindex

type RawDataWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder
  data
  dataBG
  params
  cTD
  cFD
  deltaT
  filenameData
  loadingData
end

getindex(m::RawDataWidget, w::AbstractString) = G_.object(m.builder, w)

function RawDataWidget(filenameConfig=nothing)
  println("Starting RawDataWidget")
  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","rawDataViewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxRawViewer")

  m = RawDataWidget( mainBox.handle, b,
                  nothing, nothing, nothing, nothing, nothing,
                  nothing, nothing, false)
  Gtk.gobject_move_ref(m, mainBox)

  println("Type constructed")

  m.cTD = Canvas()
  m.cFD = Canvas()

  push!(m["boxTD"],m.cTD)
  setproperty!(m["boxTD"],:expand,m.cTD,true)

  push!(m["boxFD"],m.cFD)
  setproperty!(m["boxFD"],:expand,m.cFD,true)

  println("InitCallbacks")

  initCallbacks(m)

  println("Finished")

  return m
end



function initCallbacks(m::RawDataWidget)

  @time for sl in ["adjFrame", "adjPatch","adjRxChan","adjMinTP","adjMaxTP",
                   "adjMinFre","adjMaxFre"]
    signal_connect(m[sl], "value_changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Void, (), false, m )
  end

  @time for cb in ["cbShowBG", "cbAverage","cbSubtractBG","cbShowAllPatches"]
    signal_connect(m[cb], :toggled) do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[cb], "toggled", Void, (), false, m)
  end

  signal_connect(m["cbCorrTF"], :toggled) do w
    loadData(C_NULL, m)
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

    if m.filenameData != nothing && ispath(m.filenameData)
      f = MPIFile(m.filenameData)
      params = MPIFiles.loadMetadata(f)
      params["acqNumFGFrames"] = acqNumFGFrames(f)
      params["acqNumBGFrames"] = acqNumBGFrames(f)
      #setParams(m, params)

      #u = getMeasurements(f, false, frames=measFGFrameIdx(f),
      #            fourierTransform=false, bgCorrection=false,
      #             tfCorrection=getproperty(m["cbCorrTF"], :active, Bool))

      frames = 1:min(acqNumFGFrames(f),100)

      u = getMeasurements(f, true, frames=frames,
                  bgCorrection=false,
                  tfCorrection=getproperty(m["cbCorrTF"], :active, Bool))

      timePoints = rxTimePoints(f)
      deltaT = timePoints[2] - timePoints[1]

      if acqNumBGFrames(f) > 0
        #m.dataBG = MPIFiles.measDataConv(f)[:,:,:,measBGFrameIdx(f)]
        m.dataBG = getMeasurements(f, false, frames=measBGFrameIdx(f),
              bgCorrection=false,
              tfCorrection=getproperty(m["cbCorrTF"], :active, Bool))
      end
      updateData(m, u, deltaT)
    end
    m.loadingData = false
  end
  return nothing
end


function showData(widgetptr::Ptr, m::RawDataWidget)

  if m.data != nothing && !updating[]
    frame = getproperty(m["adjFrame"], :value, Int64)
    chan = getproperty(m["adjRxChan"], :value, Int64)
    patch = getproperty(m["adjPatch"], :value, Int64)
    minTP = getproperty(m["adjMinTP"], :value, Int64)
    maxTP = getproperty(m["adjMaxTP"], :value, Int64)
    minFr = getproperty(m["adjMinFre"], :value, Int64)
    maxFr = getproperty(m["adjMaxFre"], :value, Int64)

    if getproperty(m["cbShowAllPatches"], :active, Bool)
      minTP = 1
      maxTP = size(m.data,1)*size(m.data,3)
      if getproperty(m["cbAverage"], :active, Bool)
        data = vec(mean(m.data,4)[:,chan,:,1])
      else
        data = vec(m.data[:,chan,:,frame])
      end
      if m.dataBG != nothing && getproperty(m["cbSubtractBG"], :active, Bool)
        data[:] .-=  vec(mean(m.dataBG[:,chan,:,:],3))
      end
    else
      if getproperty(m["cbAverage"], :active, Bool)
        data = vec(mean(m.data,4)[:,chan,patch,1])
      else
        data = vec(m.data[:,chan,patch,frame])
      end
      if m.dataBG != nothing && getproperty(m["cbSubtractBG"], :active, Bool)
        data[:] .-=  vec(mean(m.dataBG[:,chan,patch,:],2))
      end
    end

    timePoints = (0:(length(data)-1)).*m.deltaT
    numFreq = floor(Int, length(data) ./ 2 .+ 1)
    freq = collect(0:(numFreq-1))./(numFreq-1)./m.deltaT./2.0

    p1 = Winston.plot(timePoints[minTP:maxTP],data[minTP:maxTP],"b-",linewidth=5)
    Winston.ylabel("u / V")
    Winston.xlabel("t / ms")
    p2 = Winston.semilogy(freq[minFr:maxFr],abs.(rfft(data)[minFr:maxFr]),"b-o", linewidth=5)
    #Winston.ylabel("u / V")
    Winston.xlabel("f / kHz")
    if m.dataBG != nothing && getproperty(m["cbShowBG"], :active, Bool)
      mid = div(size(m.dataBG,4),2)
      #dataBG = vec(m.dataBG[:,chan,patch,1] .- mean(m.dataBG[:,chan,patch,:],2))
      dataBG = vec( mean(m.dataBG[:,chan,patch,:],2))

      Winston.plot(p1,timePoints[minTP:maxTP],dataBG[minTP:maxTP],"k--",linewidth=2)
      Winston.plot(p2,freq[minFr:maxFr],abs.(rfft(dataBG)[minFr:maxFr]),"k-x",
                   linewidth=2, ylog=true)
    end
    display(m.cTD ,p1)
    display(m.cFD ,p2)

  end
  return nothing
end

global const updating = Ref{Bool}(false)

function updateData(m::RawDataWidget, data::Array, deltaT=1.0)
  updating[] = true

  m.data = data
  m.deltaT = deltaT .* 1000 # convert to ms and kHz

  Gtk.@sigatom setproperty!(m["adjFrame"],:upper,size(data,4))
  Gtk.@sigatom setproperty!(m["adjFrame"],:value,1)
  Gtk.@sigatom setproperty!(m["adjRxChan"],:upper,size(data,2))
  Gtk.@sigatom setproperty!(m["adjRxChan"],:value,1)
  Gtk.@sigatom setproperty!(m["adjPatch"],:upper,size(data,3))
  Gtk.@sigatom setproperty!(m["adjPatch"],:value,1)
  Gtk.@sigatom setproperty!(m["adjMinTP"],:upper,size(data,1))
  Gtk.@sigatom setproperty!(m["adjMinTP"],:value,1)
  Gtk.@sigatom setproperty!(m["adjMaxTP"],:upper,size(data,1))
  Gtk.@sigatom setproperty!(m["adjMaxTP"],:value,size(data,1))
  Gtk.@sigatom setproperty!(m["adjMinFre"],:upper,div(size(data,1),2)+1)
  Gtk.@sigatom setproperty!(m["adjMinFre"],:value,1)
  Gtk.@sigatom setproperty!(m["adjMaxFre"],:upper,div(size(data,1),2)+1)
  Gtk.@sigatom setproperty!(m["adjMaxFre"],:value,div(size(data,1),2)+1)

  updating[] = false
  showData(C_NULL,m)
end

function updateData(m::RawDataWidget, filename::String)
  m.filenameData = filename
  loadData(C_NULL, m)
  return nothing
end
