import Base: getindex

mutable struct SpectrogramWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::Builder
  data::Array{Float32,5}
  dataBG::Array{Float32,5}
  labels::Vector{String}
  cTD::Canvas
  cFD::Canvas
  cSpect::Canvas
  deltaT::Float64
  filenamesData::Vector{String}
  loadingData::Bool
  updatingData::Bool
  fileModus::Bool
end

getindex(m::SpectrogramWidget, w::AbstractString) = G_.object(m.builder, w)

mutable struct SpectrogramViewer
  w::Window
  sw::SpectrogramWidget
end

function SpectrogramViewer(filename::AbstractString)
  sw = SpectrogramWidget()
  w = Window("Spectrogram Viewer: $(filename)",800,600)
  push!(w, sw)
  showall(w)
  updateData(sw, filename)
  return SpectrogramViewer(w, sw)
end

function SpectrogramWidget(filenameConfig=nothing)
  @info "Starting SpectrogramWidget"
  uifile = joinpath(@__DIR__,"builder","spectrogramViewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxSpectrogramViewer")

  m = SpectrogramWidget( mainBox.handle, b,
                  zeros(Float32,0,0,0,0,0), zeros(Float32,0,0,0,0,0),
                  [""], Canvas(), Canvas(), Canvas(),
                  1.0, [""], false, false, false)
  Gtk.gobject_move_ref(m, mainBox)

  @debug "Type constructed"

  push!(m["boxTD"],m.cTD)
  set_gtk_property!(m["boxTD"],:expand,m.cTD,true)

  pane = m["paned"]
  set_gtk_property!(pane, :position, 300)

  push!(m["boxSpectro"], m.cSpect)
  set_gtk_property!(m["boxSpectro"],:expand, m.cSpect, true)

  push!(m["boxFD"],m.cFD)
  set_gtk_property!(m["boxFD"],:expand,m.cFD,true)

  @debug "InitCallbacks"

  initCallbacks(m)

  @info "Finished starting SpectrogramWidget"

  return m
end

function initCallbacks(m_::SpectrogramWidget)
 let m=m_
  for sl in ["adjPatch","adjRxChan", "adjLogPlot"]
    signal_connect(m[sl], "value_changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Nothing, (), false, m )
  end

  signal_connect(m["adjMinTP"], "value_changed") do w
    if !m.updatingData
      minTP = get_gtk_property(m["adjMinTP"],:value, Int)
      maxTP = get_gtk_property(m["adjMaxTP"],:value, Int)
      maxValTP = get_gtk_property(m["adjMaxTP"],:upper, Int)
      
      if minTP > maxTP
        @idle_add set_gtk_property!(m["adjMaxTP"],:value, min(maxValTP,minTP+10))
      else
        showData(C_NULL, m)
      end
    end
  end

  signal_connect(m["adjMaxTP"], "value_changed") do w
    if !m.updatingData
      minTP = get_gtk_property(m["adjMinTP"],:value, Int)
      maxTP = get_gtk_property(m["adjMaxTP"],:value, Int)
      
      if minTP > maxTP
        @idle_add set_gtk_property!(m["adjMinTP"],:value, max(1,maxTP-10))
      else
        showData(C_NULL, m)
      end
    end
  end

  signal_connect(m["adjMinFre"], "value_changed") do w
    if !m.updatingData
      minFre = get_gtk_property(m["adjMinFre"],:value, Int)
      maxFre = get_gtk_property(m["adjMaxFre"],:value, Int)
      maxValFre = get_gtk_property(m["adjMaxFre"],:upper, Int)
      
      if minFre > maxFre
        @idle_add set_gtk_property!(m["adjMaxFre"],:value, min(maxValFre,minFre+10))
      else
        showData(C_NULL, m)
      end
    end
  end

  signal_connect(m["adjMaxFre"], "value_changed") do w
    if !m.updatingData
      minFre = get_gtk_property(m["adjMinFre"],:value, Int)
      maxFre = get_gtk_property(m["adjMaxFre"],:value, Int)
      
      if minFre > maxFre
        @idle_add set_gtk_property!(m["adjMinFre"],:value, max(1,maxFre-10))
      else
        showData(C_NULL, m)
      end
    end
  end

  signal_connect(m["adjGrouping"], "value_changed") do w
    
    if !m.updatingData
      @idle_add begin
        m.updatingData = true
        timedata, sp = getData(m)

        maxValTP = length(timedata[1])
        maxValFre = size(sp.power,1)
        numPatches = size(sp.power,2)

        set_gtk_property!(m["adjMinTP"],:upper,maxValTP)
        set_gtk_property!(m["adjMinTP"],:value,1)
        set_gtk_property!(m["adjMaxTP"],:upper,maxValTP)
        set_gtk_property!(m["adjMaxTP"],:value,maxValTP)
    
        set_gtk_property!(m["adjMinFre"],:upper,maxValFre)
        set_gtk_property!(m["adjMinFre"],:value,1)
        set_gtk_property!(m["adjMaxFre"],:upper,maxValFre)
        set_gtk_property!(m["adjMaxFre"],:value,maxValFre)

        set_gtk_property!(m["adjPatch"],:upper,numPatches)
        if get_gtk_property(m["adjPatch"],:value, Int) >= numPatches
          set_gtk_property!(m["adjPatch"],:value, 1)
        end

        m.updatingData = false
        showData(C_NULL, m)
      end
    end
  end

  for cb in ["cbShowBG", "cbSubtractBG", "cbShowFreq"]
    signal_connect(m[cb], :toggled) do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[cb], "toggled", Nothing, (), false, m)
  end


  #=for cb in ["cbCorrTF","cbSLCorr","cbAbsFrameAverage"]
    signal_connect(m[cb], :toggled) do w
      loadData(C_NULL, m)
    end
  end=#

  for cb in ["adjFrame"]
    signal_connect(m[cb], "value_changed") do w
      loadData(C_NULL, m)
    end
  end

  for sl in ["entTDMinVal","entTDMaxVal","entFDMinVal","entFDMaxVal"]
    signal_connect(m[sl], "changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Nothing, (), false, m )
  end

  #signal_connect(loadData, m["cbCorrTF"], "toggled", Nothing, (), false, m)
 end
end



function loadData(widgetptr::Ptr, m::SpectrogramWidget)
  if !m.loadingData
    m.loadingData = true
    @info "Loading Data ..."
    deltaT = 1.0

    if m.filenamesData != [""] && all(ispath.(m.filenamesData))
      fs = MPIFile(m.filenamesData) #, isCalib=false)

      # TODO: Ensure that the measurements fit together (num samples / patches)
      # otherwise -> error
  
      numFGFrames = minimum(acqNumFGFrames.(fs))
      numBGFrames = minimum(acqNumBGFrames.(fs))    
      
      dataFGVec = Any[]
      dataBGVec = Any[]

      for (i,f) in enumerate(fs)
        params = MPIFiles.loadMetadata(f)
        params[:acqNumFGFrames] = acqNumFGFrames(f)
        params[:acqNumBGFrames] = acqNumBGFrames(f)

        @idle_add set_gtk_property!(m["adjFrame"], :upper, numFGFrames)

        frame = max( get_gtk_property(m["adjFrame"], :value, Int64), 1)

        timePoints = rxTimePoints(f)
        deltaT = timePoints[2] - timePoints[1]

        data = getMeasurements(f, true, frames=frame,
                    bgCorrection=false, spectralLeakageCorrection = get_gtk_property(m["cbSLCorr"], :active, Bool),
                    tfCorrection=get_gtk_property(m["cbCorrTF"], :active, Bool))
        push!(dataFGVec, data)

        if acqNumBGFrames(f) > 0
          dataBG = getMeasurements(f, false, frames=measBGFrameIdx(f),
                bgCorrection=false, spectralLeakageCorrection = get_gtk_property(m["cbSLCorr"], :active, Bool),
                tfCorrection=get_gtk_property(m["cbCorrTF"], :active, Bool))
        else
          dataBG = zeros(Float32,0,0,0,0)
        end
        push!(dataBGVec, dataBG)
      end


      m.dataBG = cat(dataBGVec..., dims=5)
      dataFG = cat(dataFGVec..., dims=5)
      m.labels = ["expnum "*string(experimentNumber(f)) for f in fs]

      updateData(m, dataFG, deltaT, true)
    end
    m.loadingData = false
  end
  return nothing
end

function getData(m::SpectrogramWidget)
  chan = max(get_gtk_property(m["adjRxChan"], :value, Int64),1)
  group = get_gtk_property(m["adjGrouping"],:value,Int64)
  showBG = get_gtk_property(m["cbShowBG"], :active, Bool)
  numPatches = size(m.data,3)

  data_ = vec( mean( reshape(m.data[:,chan,:,1,:],:, 1, numPatches, 1), dims=2) )
  if length(m.dataBG) > 0
    dataBG_ = vec(mean(reshape(m.dataBG[:,chan,:,:,:],size(m.dataBG,1), 1, numPatches, :, 1), dims=(2,4)) )

    if get_gtk_property(m["cbSubtractBG"], :active, Bool)
      data_[:] .-= dataBG_
    end
    if showBG
      data_[:] .= dataBG_
    end
  end
 
  timedata = arraysplit(data_, size(m.data,1)*group, div(size(m.data,1)*group,2))
  sp = DSP.spectrogram(vec(data_), size(m.data,1)*group)

  return timedata, sp
end


function showData(widgetptr::Ptr, m::SpectrogramWidget)

  if length(m.data) > 0 && !m.updatingData
    chan = max(get_gtk_property(m["adjRxChan"], :value, Int64),1)
    patch = max(get_gtk_property(m["adjPatch"], :value, Int64),1)
    minTP = max(get_gtk_property(m["adjMinTP"], :value, Int64),1)
    maxTP = max(get_gtk_property(m["adjMaxTP"], :value, Int64),1)
    minFr = max(get_gtk_property(m["adjMinFre"], :value, Int64),1)
    maxFr = max(get_gtk_property(m["adjMaxFre"], :value, Int64),1)
    group = get_gtk_property(m["adjGrouping"],:value,Int64)
    logVal = get_gtk_property(m["adjLogPlot"],:value, Float64)
    numPatches = size(m.data,3)
    numSignals = size(m.data,5)
    showFD = get_gtk_property(m["cbShowFreq"], :active, Bool)

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

    timedata, sp = getData(m)

    maxFr = min(maxFr,size(sp.power,1))
    spdata = sp.power[minFr:maxFr,:]

    maxT = m.deltaT*size(m.data,1)*size(m.data,3)/1000
    
    data_ = timedata[patch]

    Winston.colormap(convert.(RGB{N0f8},cmap("viridis")))
    psp = Winston.imagesc( (0.0, maxT), 
                           ((minFr-1)/size(sp.power,1) / m.deltaT / 2.0, 
                               (maxFr-1)/size(sp.power,1) / m.deltaT / 2.0 ), 
                          log.(10.0^(-(2+10*logVal)) .+ spdata ) )
    patch_ = patch/size(sp.power,2) *  maxT
    Winston.add(psp, Winston.Curve([patch_,patch_], [0,(maxFr-1)/size(sp.power,1) / m.deltaT / 2.0], 
                                   kind="solid", color="white", lw=10) )

    Winston.ylabel("freq / kHz")
    Winston.xlabel("t / s")

    @idle_add display(m.cSpect, psp)

    timePoints = (0:(length(data_)-1)).*m.deltaT
   
    maxPoints = 5000
    sp_ = length(minTP:maxTP) > maxPoints ? round(Int,length(minTP:maxTP) / maxPoints)  : 1
    steps = minTP:sp_:maxTP
  
#    p1 = Winston.plot(timePoints[steps],data_[steps,:],color=colors[1],linewidth=3)   
    p1 = Winston.plot(timePoints[steps], data_[steps], color=colors[1],linewidth=3)

    Winston.ylabel("u / V")
    Winston.xlabel("t / ms")
    if !autoRangingTD
      Winston.ylim(minValTD, maxValTD)
    end


    if showFD
      numFreq = size(sp.power,1)
      freq = collect(0:(numFreq-1))./(numFreq-1)./m.deltaT./2.0
      freqdata = sp.power[:,:]
      spFr = length(minFr:maxFr) > maxPoints ? round(Int,length(minFr:maxFr) / maxPoints)  : 1

      stepsFr = minFr:spFr:maxFr

      p2 = Winston.semilogy(freq[stepsFr],freqdata[stepsFr,patch],color=colors[1],linewidth=3)

      #Winston.ylabel("u / V")
      Winston.xlabel("f / kHz")
      if !autoRangingFD
          Winston.ylim(minValFD, maxValFD)
      end
    else
      @guarded Gtk.draw(m.cFD) do widget
        
        ctx = getgc(m.cFD)
        h = height(ctx)
        w = width(ctx)
        Cairo.set_source_rgb(ctx,1.0,1.0,1.0)
        Cairo.rectangle(ctx, 0,0,w,h)
        Cairo.paint(ctx)
        Cairo.stroke(ctx)
      end
    end


    @idle_add display(m.cTD, p1)
    if showFD
      @idle_add display(m.cFD, p2)
    end

  end
  return nothing
end


function updateData(m::SpectrogramWidget, data::Array, deltaT=1.0, fileModus=false)
  maxValTPOld = get_gtk_property(m["adjMinTP"],:upper, Int64)
  maxValFreOld = get_gtk_property(m["adjMinFre"],:upper, Int64)

  if ndims(data) == 5
    m.data = data
  else
    m.data = reshape(data, size(data)..., 1)
  end
  m.deltaT = deltaT .* 1000 # convert to ms and kHz
  m.fileModus = fileModus

  if !isempty(m.dataBG)
    if size(m.data)[1:3] != size(m.dataBG)[1:3]
      @info "Background data does not fit to foreground data! Dropping BG data."
      @info size(m.data)
      @info size(m.dataBG)
      m.dataBG = zeros(Float32,0,0,0,0,0)
    end
  end

  timedata, sp = getData(m)
  maxValTP = length(timedata[1])
  maxValFre = size(sp.power,1)
  numPatches = size(sp.power,2)
  maxGrouping = div(numPatches,2)

  @idle_add begin
    m.updatingData = true
    set_gtk_property!(m["adjGrouping"],:upper,maxGrouping)
    if !(1 <= get_gtk_property(m["adjGrouping"],:value,Int64) <= maxGrouping)
      set_gtk_property!(m["adjGrouping"],:value, 1)
    end
    if !fileModus
      set_gtk_property!(m["adjFrame"],:upper,size(data,4))
      if !(1 <= get_gtk_property(m["adjFrame"],:value,Int64) <= size(data,4))
        set_gtk_property!(m["adjFrame"],:value,1)
      end
    end
    set_gtk_property!(m["adjRxChan"],:upper,size(data,2))
    if !(1 <= get_gtk_property(m["adjRxChan"],:value,Int64) <= size(data,2))
      set_gtk_property!(m["adjRxChan"],:value,1)
    end
    set_gtk_property!(m["adjPatch"],:upper,numPatches)
    if !(1 <= get_gtk_property(m["adjPatch"],:value,Int64) <= numPatches)
      set_gtk_property!(m["adjPatch"],:value,1)
    end
    set_gtk_property!(m["adjMinTP"],:upper,maxValTP)
    if !(1 <= get_gtk_property(m["adjMinTP"],:value,Int64) <= maxValTP) || maxValTP != maxValTPOld
      set_gtk_property!(m["adjMinTP"],:value,1)
    end
    set_gtk_property!(m["adjMaxTP"],:upper, maxValTP)
    if !(1 <= get_gtk_property(m["adjMaxTP"],:value,Int64) <= maxValTP) || maxValTP != maxValTPOld
      set_gtk_property!(m["adjMaxTP"],:value, maxValTP)
    end
    set_gtk_property!(m["adjMinFre"],:upper, maxValFre)
    if !(1 <= get_gtk_property(m["adjMinFre"],:value,Int64) <= maxValFre) || maxValFre != maxValFreOld
      set_gtk_property!(m["adjMinFre"],:value,1)
    end
    set_gtk_property!(m["adjMaxFre"],:upper, maxValFre)
    if !(1 <= get_gtk_property(m["adjMaxFre"],:value,Int64) <= maxValFre) || maxValFre != maxValFreOld
      set_gtk_property!(m["adjMaxFre"],:value, maxValFre)
    end

    m.updatingData = false
    showData(C_NULL, m)
  end
end

function updateData(m::SpectrogramWidget, filenames::Vector{<:AbstractString})
  m.filenamesData = filenames
  @idle_add begin
    m.updatingData = true
    set_gtk_property!(m["adjFrame"],:upper,1)
    set_gtk_property!(m["adjFrame"],:value,1)
    set_gtk_property!(m["adjPatch"],:upper,1)
    set_gtk_property!(m["adjPatch"],:value,1)
    m.updatingData = false
    loadData(C_NULL, m)
  end
  return nothing
end

function updateData(m::SpectrogramWidget, filename::String)
  updateData(m, [filename])
  return nothing
end
