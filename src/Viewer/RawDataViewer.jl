import Base: getindex

mutable struct RawDataWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::Builder
  data::Array{Float32,5}
  dataBG::Array{Float32,5}
  labels::Vector{String}
  cTD::Canvas
  cFD::Canvas
  deltaT::Float64
  filenamesData::Vector{String}
  loadingData::Bool
  updatingData::Bool
  fileModus::Bool
  winHarmView::WindowLeaf
  harmViewAdj::Vector{AdjustmentLeaf}
  harmViewCanvas::Vector{Canvas}
  harmBuff::Vector{Vector{Float32}}
  rangeTD::NTuple{2,Float64}
  rangeFD::NTuple{2,Float64}
end

getindex(m::RawDataWidget, w::AbstractString) = G_.object(m.builder, w)

function RawDataWidget(filenameConfig=nothing)
  @info "Starting RawDataWidget"
  uifile = joinpath(@__DIR__,"..","builder","rawDataViewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxRawViewer")

  m = RawDataWidget( mainBox.handle, b,
                  zeros(Float32,0,0,0,0,0), zeros(Float32,0,0,0,0,0),
                  [""], Canvas(), Canvas(),
                  1.0, [""], false, false, false,
                  G_.object(b,"winHarmonicViewer"),
                  AdjustmentLeaf[], Canvas[], Vector{Vector{Float32}}(),
                  (0.0,1.0), (0.0,1.0))
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
    @idle_add_guarded set_gtk_property!(m["adjHarm$l"],:value,l+1)
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
  for sl in ["adjPatch","adjRxChan"]
    signal_connect(m[sl], "value_changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Nothing, (), false, m )
  end

  signal_connect(m["adjMinTP"], "value_changed") do w
    minTP = get_gtk_property(m["adjMinTP"],:value, Int)
    maxTP = get_gtk_property(m["adjMaxTP"],:value, Int)
    maxValTP = get_gtk_property(m["adjMaxTP"],:upper, Int)
    
    if minTP > maxTP
      @idle_add_guarded set_gtk_property!(m["adjMaxTP"],:value, min(maxValTP,minTP+10))
    else
      showData(C_NULL, m)
    end
  end

  signal_connect(m["adjMaxTP"], "value_changed") do w
    minTP = get_gtk_property(m["adjMinTP"],:value, Int)
    maxTP = get_gtk_property(m["adjMaxTP"],:value, Int)
    
    if minTP > maxTP
      @idle_add_guarded set_gtk_property!(m["adjMinTP"],:value, max(1,maxTP-10))
    else
      showData(C_NULL, m)
    end
  end

  signal_connect(m["adjMinFre"], "value_changed") do w
    minFre = get_gtk_property(m["adjMinFre"],:value, Int)
    maxFre = get_gtk_property(m["adjMaxFre"],:value, Int)
    maxValFre = get_gtk_property(m["adjMaxFre"],:upper, Int)
    
    if minFre > maxFre
      @idle_add_guarded set_gtk_property!(m["adjMaxFre"],:value, min(maxValFre,minFre+10))
    else
      showData(C_NULL, m)
    end
  end

  signal_connect(m["adjMaxFre"], "value_changed") do w
    minFre = get_gtk_property(m["adjMinFre"],:value, Int)
    maxFre = get_gtk_property(m["adjMaxFre"],:value, Int)
    
    if minFre > maxFre
      @idle_add_guarded set_gtk_property!(m["adjMinFre"],:value, max(1,maxFre-10))
    else
      showData(C_NULL, m)
    end
  end

  oldAdjPatchAvValue = 1
  signal_connect(m["adjPatchAv"], "value_changed") do w
    if !m.updatingData
      m.updatingData = true
      patchAv = max(get_gtk_property(m["adjPatchAv"], :value, Int64),1)
      numPatches = size(m.data,3)
      if mod(numPatches, patchAv) != 0
        if 1 < patchAv < numPatches
          while mod(numPatches, patchAv) != 0
            patchAv += sign(patchAv-oldAdjPatchAvValue)*1
          end
        elseif patchAv < 1
          patchAv = 1
        elseif patchAv > numPatches
          patchAv = numPatches
        end
        oldAdjPatchAvValue = patchAv
        
        @idle_add_guarded begin
          set_gtk_property!(m["adjPatchAv"], :value, patchAv)
          showAllPatchesChanged(m)
        end
      else
        @idle_add_guarded showAllPatchesChanged(m)
      end
      oldAdjPatchAvValue = patchAv
      m.updatingData = false
    end
  end

  for cb in ["cbShowBG", "cbSubtractBG", "cbShowFreq", "cbReversePlots"]
    signal_connect(m[cb], :toggled) do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[cb], "toggled", Nothing, (), false, m)
  end

  signal_connect(m["cbShowAllPatches"], :toggled) do w
    @idle_add_guarded begin
      showAllPatchesChanged(m)
    end
  end

  @guarded function showAllPatchesChanged(m)
    m.updatingData = true
    showAllPatches = get_gtk_property(m["cbShowAllPatches"], :active, Bool)
    patchAv = max(get_gtk_property(m["adjPatchAv"], :value, Int64),1)
    numPatches = div(size(m.data,3), patchAv)

    maxValTP = showAllPatches ? size(m.data,1)*numPatches : size(m.data,1)
    maxValFre = div(maxValTP,2)+1

    set_gtk_property!(m["adjMinTP"],:upper,maxValTP)
    set_gtk_property!(m["adjMinTP"],:value,1)
    set_gtk_property!(m["adjMaxTP"],:upper,maxValTP)
    set_gtk_property!(m["adjMaxTP"],:value,maxValTP)

    set_gtk_property!(m["adjMinFre"],:upper,maxValFre)
    set_gtk_property!(m["adjMinFre"],:value,1)
    set_gtk_property!(m["adjMaxFre"],:upper,maxValFre)
    set_gtk_property!(m["adjMaxFre"],:value,maxValFre)
    m.updatingData = false
    showData(C_NULL, m)
  end


  for cb in ["cbCorrTF","cbSLCorr","cbAbsFrameAverage"]
    signal_connect(m[cb], :toggled) do w
      loadData(C_NULL, m)
    end
  end

  for cb in ["adjFrame"]
    signal_connect(m[cb], "value_changed") do w
      loadData(C_NULL, m)
    end
  end

  signal_connect(m["cbHarmonicViewer"], :toggled) do w
      harmViewOn = get_gtk_property(m["cbHarmonicViewer"], :active, Bool)
      @idle_add_guarded begin
        if harmViewOn
          clearHarmBuff(m)
          set_gtk_property!(m.winHarmView,:visible, true)
          showall(m.winHarmView)
        else
          set_gtk_property!(m.winHarmView,:visible, false)
        end
      end
  end

  for sl in ["entTDMinVal","entTDMaxVal","entFDMinVal","entFDMaxVal"]
    signal_connect(m[sl], "changed") do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[sl], "value_changed", Nothing, (), false, m )
  end

  for sl in ["TD", "FD"]
    signal_connect(m["btn$(sl)Apply"], "clicked") do w
      if !m.updatingData
        @idle_add_guarded begin
          m.updatingData = true
          r = (sl == "TD") ? m.rangeTD : m.rangeFD
          set_gtk_property!( m["ent$(sl)MinVal"] ,:text, string(r[1]))
          set_gtk_property!( m["ent$(sl)MaxVal"] ,:text, string(r[2]))
          m.updatingData = false
          showData(C_NULL, m)
        end
      end
    end

    signal_connect(m["btn$(sl)Clear"], "clicked") do w
      if !m.updatingData
        @idle_add_guarded begin
          m.updatingData = true
          set_gtk_property!( m["ent$(sl)MinVal"] ,:text, "")
          set_gtk_property!( m["ent$(sl)MaxVal"] ,:text, "")
          m.updatingData = false
          showData(C_NULL, m)
        end
      end
    end
  end
  
  signal_connect(m.winHarmView, "delete-event") do widget, event
    #typeof(event)
    #@show event
    @idle_add_guarded set_gtk_property!(m["cbHarmonicViewer"], :active, false)
  end

  #signal_connect(loadData, m["cbCorrTF"], "toggled", Nothing, (), false, m)
 end
end



@guarded function loadData(widgetptr::Ptr, m::RawDataWidget)
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

        @idle_add_guarded set_gtk_property!(m["adjFrame"], :upper, numFGFrames)

        if get_gtk_property(m["cbAbsFrameAverage"], :active, Bool)
          frame = 1:numFGFrames
        else
          frame = max( get_gtk_property(m["adjFrame"], :value, Int64), 1)
        end

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


@guarded function showData(widgetptr::Ptr, m::RawDataWidget)

  if length(m.data) > 0 && !m.updatingData
    chan = max(get_gtk_property(m["adjRxChan"], :value, Int64),1)
    patch = max(get_gtk_property(m["adjPatch"], :value, Int64),1)
    minTP = max(get_gtk_property(m["adjMinTP"], :value, Int64),1)
    maxTP = max(get_gtk_property(m["adjMaxTP"], :value, Int64),1)
    minFr = max(get_gtk_property(m["adjMinFre"], :value, Int64),1)
    maxFr = max(get_gtk_property(m["adjMaxFre"], :value, Int64),1)
    patchAv = max(get_gtk_property(m["adjPatchAv"], :value, Int64),1)
    numPatches = div(size(m.data,3), patchAv)
    numSignals = size(m.data,5)
    showFD = get_gtk_property(m["cbShowFreq"], :active, Bool)
    reversePlots = get_gtk_property(m["cbReversePlots"], :active, Bool)

    autoRangingTD = true
    autoRangingFD = true
    minValTD_ = tryparse(Float64,get_gtk_property( m["entTDMinVal"] ,:text,String))
    maxValTD_ = tryparse(Float64,get_gtk_property( m["entTDMaxVal"] ,:text,String))
    minValFD_ = tryparse(Float64,get_gtk_property( m["entFDMinVal"] ,:text,String))
    maxValFD_ = tryparse(Float64,get_gtk_property( m["entFDMaxVal"] ,:text,String))

    @info minValTD_

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

    if get_gtk_property(m["cbShowAllPatches"], :active, Bool)
      data = vec( mean( reshape(m.data[:,chan,:,1,:],:, patchAv, numPatches, numSignals), dims=2) )
      if length(m.dataBG) > 0
        dataBG = vec(mean(reshape(m.dataBG[:,chan,:,:,:],size(m.dataBG,1), patchAv, numPatches, :, numSignals), dims=(2,4)) )

        if get_gtk_property(m["cbSubtractBG"], :active, Bool)
          data[:] .-= dataBG
        end
      end
    else
      if get_gtk_property(m["cbAbsFrameAverage"], :active, Bool)
        dataFD = rfft(m.data[:,chan,patch,:,:],1)
        dataFD_ = reshape(mean(abs.(dataFD), dims=2),:,numSignals)
        data = irfft(dataFD_, 2*size(dataFD_, 1) -2, 1)

        if length(m.dataBG) > 0
          dataBGFD = rfft(m.dataBG[:,chan,patch,:,:], 1)
          dataBGFD_ = reshape(mean(abs.(dataBGFD), dims=2), :, numSignals)
          dataBG = irfft(dataBGFD_, 2*size(dataBGFD_, 1) -2, 1)
          if get_gtk_property(m["cbSubtractBG"], :active, Bool)
            data .-=  dataBG
          end
        end
      else
        data = vec(m.data[:,chan,patch,1,:])
        if length(m.dataBG) > 0
          #dataBG = vec(m.dataBG[:,chan,patch,1] .- mean(m.dataBG[:,chan,patch,:], dims=2))
          dataBG = vec( mean(m.dataBG[:,chan,patch,:,:],dims=2))
          if get_gtk_property(m["cbSubtractBG"], :active, Bool)
            data[:] .-=  dataBG
          end
        end
      end
    end

    data = reshape(data, :, numSignals)
    if reversePlots
      reverse!(data, dims=2)
    end
    if length(m.dataBG) > 0 && get_gtk_property(m["cbShowBG"], :active, Bool)
      dataBG = reshape(dataBG, :, numSignals)
    end
    m.rangeTD = extrema(data)

    #colors = ["blue", "red", "green", "yellow", "black", "cyan", "magenta"]

    timePoints = (0:(size(data,1)-1)).*m.deltaT
    numFreq = floor(Int, size(data,1) ./ 2 .+ 1)

    maxPoints = 5000
    sp = length(minTP:maxTP) > maxPoints ? round(Int,length(minTP:maxTP) / maxPoints)  : 1

    steps = minTP:sp:maxTP
    dataCompressed = zeros(length(steps), size(data,2))
    if sp > 1
      for j=1:size(data,2)
        for l=1:length(steps)
          st = steps[l]
          en = min(st+sp,steps[end])
          med_ = median(data[st:en,j])
          max_ = maximum(data[st:en,j])
          min_ = minimum(data[st:en,j])
          dataCompressed[l,j] = rand(Bool) ? max_ : min_ #abs(max_ - med_) > abs(med_ - min_) ? max_ : min_
        end
      end
    else
      dataCompressed = data[steps,:]
    end

    p1 = Winston.plot(timePoints[steps],dataCompressed[:,1],color=colors[1],linewidth=3)
    for j=2:size(data,2)
      Winston.plot(p1, timePoints[steps],dataCompressed[:,j],color=colors[j],linewidth=3)
    end
    Winston.ylabel("u / V")
    Winston.xlabel("t / ms")
    if !autoRangingTD
      Winston.ylim(minValTD, maxValTD)
    end

    if size(data,2) > 1 && length(m.labels) == size(data,2)
      #legend = Legend(.1, 0.9, legendEntries, halign="right") 
      #add(p1, legend)
      legend(reversePlots ? reverse(m.labels) : m.labels)
    end

    if showFD
      freq = collect(0:(numFreq-1))./(numFreq-1)./m.deltaT./2.0
      freqdata = abs.(rfft(data, 1)) / size(data,1)
      m.rangeFD = extrema(freqdata)
      spFr = length(minFr:maxFr) > maxPoints ? round(Int,length(minFr:maxFr) / maxPoints)  : 1

      stepsFr = minFr:spFr:maxFr
      freqDataCompressed = zeros(length(stepsFr), size(freqdata,2))
      if spFr > 1
        for j=1:size(freqdata,2)
          for l=1:length(stepsFr)
            st = stepsFr[l]
            en = min(st+spFr,stepsFr[end])
            freqDataCompressed[l,j] = maximum(freqdata[st:en,j])
          end
        end
      else
        freqDataCompressed = freqdata[stepsFr,:]
      end

      p2 = Winston.semilogy(freq[stepsFr],freqDataCompressed[:,1],color=colors[1],linewidth=3)
      for j=2:size(data,2)
        Winston.plot(p2, freq[stepsFr], freqDataCompressed[:,j],color=colors[j],linewidth=3)
      end
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

    if length(m.dataBG) > 0 && get_gtk_property(m["cbShowBG"], :active, Bool)
      Winston.plot(p1,timePoints[minTP:sp:maxTP],dataBG[minTP:sp:maxTP,1],"k--",linewidth=3)

      if showFD
        Winston.plot(p2,freq[minFr:spFr:maxFr],abs.(rfft(dataBG,1)[minFr:spFr:maxFr,1]) / size(dataBG,1),
                     "k--", linewidth=3, ylog=true)
      end
    end
    @idle_add_guarded display(m.cTD, p1)
    if showFD
      @idle_add_guarded display(m.cFD, p2)
    end

    ### Harmonic Viewer ###
    if  get_gtk_property(m["cbHarmonicViewer"], :active, Bool) && showFD
      for l=1:5
        f = get_gtk_property(m.harmViewAdj[l], :value, Int64)
        push!(m.harmBuff[l], freqdata[f,1])

        p = Winston.semilogy(m.harmBuff[l], "b-o", linewidth=3)
        Winston.ylabel("Harmonic $f")
        Winston.xlabel("Time")
        display(m.harmViewCanvas[l] ,p)
      end
    end
  end
  return nothing
end

function setBG(m::RawDataWidget, dataBG)
  if ndims(dataBG) == 5
    m.dataBG = dataBG
  else
    m.dataBG = reshape(dataBG, size(dataBG)..., 1)
  end
end

@guarded function updateData(m::RawDataWidget, data::Array, deltaT=1.0, fileModus=false)
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

  showAllPatches = get_gtk_property(m["cbShowAllPatches"], :active, Bool) 
  patchAv = max(get_gtk_property(m["adjPatchAv"], :value, Int64),1)
  numPatches = div(size(m.data,3), patchAv)
  maxValTP = showAllPatches ? size(m.data,1)*numPatches : size(m.data,1)
  maxValFre = div(maxValTP,2)+1

  @idle_add_guarded begin
    m.updatingData = true
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
    set_gtk_property!(m["adjPatch"],:upper,size(data,3))
    if !(1 <= get_gtk_property(m["adjPatch"],:value,Int64) <= size(data,3))
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

    for l=1:5
      set_gtk_property!(m.harmViewAdj[l],:upper,div(size(data,1),2)+1)
    end

    m.updatingData = false
    showData(C_NULL, m)
  end
end

@guarded function updateData(m::RawDataWidget, filenames::Vector{<:AbstractString})
  m.filenamesData = filenames
  @idle_add_guarded begin
    m.updatingData = true
    set_gtk_property!(m["adjFrame"],:upper,1)
    set_gtk_property!(m["adjFrame"],:value,1)
    set_gtk_property!(m["adjPatch"],:upper,1)
    set_gtk_property!(m["adjPatch"],:value,1)
    set_gtk_property!(m["adjPatchAv"],:upper,1)
    set_gtk_property!(m["adjPatchAv"],:value,1)
    m.updatingData = false
    loadData(C_NULL, m)
  end
  return nothing
end

@guarded function updateData(m::RawDataWidget, filename::String)
  updateData(m, [filename])
  return nothing
end