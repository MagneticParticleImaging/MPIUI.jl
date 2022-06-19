import Base: getindex

export SpectrogramViewer

mutable struct SpectrogramWidget <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  data::Array{Float32,5}
  dataBG::Array{Float32,5}
  labels::Vector{String}
  cTD::GtkCanvas
  cFD::GtkCanvas
  cSpect::GtkCanvas
  deltaT::Float64
  filenamesData::Vector{String}
  updatingData::Bool
  fileModus::Bool
  rangeTD::NTuple{2,Float64}
  rangeFD::NTuple{2,Float64}
end

getindex(m::SpectrogramWidget, w::AbstractString) = G_.object(m.builder, w)

mutable struct SpectrogramViewer
  w::Gtk4.GtkWindowLeaf
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

  b = GtkBuilder(filename=uifile)
  mainBox = G_.object(b, "boxSpectrogramViewer")

  m = SpectrogramWidget( mainBox.handle, b,
                  zeros(Float32,0,0,0,0,0), zeros(Float32,0,0,0,0,0),
                  [""], GtkCanvas(), GtkCanvas(), GtkCanvas(),
                  1.0, [""], false, false,
                  (0.0,1.0), (0.0,1.0))
  Gtk4.gobject_move_ref(m, mainBox)

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
        @idle_add_guarded set_gtk_property!(m["adjMaxTP"],:value, min(maxValTP,minTP+10))
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
        @idle_add_guarded set_gtk_property!(m["adjMinTP"],:value, max(1,maxTP-10))
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
        @idle_add_guarded set_gtk_property!(m["adjMaxFre"],:value, min(maxValFre,minFre+10))
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
        @idle_add_guarded set_gtk_property!(m["adjMinFre"],:value, max(1,maxFre-10))
      else
        showData(C_NULL, m)
      end
    end
  end

  @guarded function groupingChanged()
    if !m.updatingData
      @idle_add_guarded begin
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

  signal_connect(m["adjGrouping"], "value_changed") do w
    groupingChanged()
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
          groupingChanged()
        end
      else
        @idle_add_guarded groupingChanged()
      end
      oldAdjPatchAvValue = patchAv
      m.updatingData = false
    end
  end

  for cb in ["cbShowBG", "cbSubtractBG", "cbShowFreq"]
    signal_connect(m[cb], :toggled) do w
      showData(C_NULL, m)
    end
    #signal_connect(showData, m[cb], "toggled", Nothing, (), false, m)
  end


  for cb in ["cbShowAllFrames"] #"cbCorrTF","cbSLCorr","cbAbsFrameAverage"
    signal_connect(m[cb], :toggled) do w
      loadData(C_NULL, m)
    end
  end

  for cb in ["adjFrame"]
    signal_connect(m[cb], "value_changed") do w
      loadData(C_NULL, m)
    end
  end

  for sl in ["entTDMinVal","entTDMaxVal","entFDMinVal","entFDMaxVal"]
    signal_connect(m[sl], "changed") do w
      showData(C_NULL, m)
    end
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

  #signal_connect(loadData, m["cbCorrTF"], "toggled", Nothing, (), false, m)
 end
end

@guarded function loadData(widgetptr::Ptr, m::SpectrogramWidget)
  if !m.updatingData
    m.updatingData = true
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

        if get_gtk_property(m["cbShowAllFrames"], :active, Bool)
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
    m.updatingData = false
  end
  return nothing
end

@guarded function getData(m::SpectrogramWidget)
  chan = max(get_gtk_property(m["adjRxChan"], :value, Int64),1)
  group = get_gtk_property(m["adjGrouping"],:value,Int64)
  patchAv = max(get_gtk_property(m["adjPatchAv"], :value, Int64),1)
  numPatches = div(size(m.data,3), patchAv)
  showBG = get_gtk_property(m["cbShowBG"], :active, Bool)
  allFrames = get_gtk_property(m["cbShowAllFrames"],  :active, Bool)

  data_ = mean( reshape(m.data[:,chan,:,:,:], 
               size(m.data,1), patchAv, numPatches, size(m.data,4), : ), dims=(2,))
  if length(m.dataBG) > 0
    dataBG_ = mean( reshape(m.dataBG[:,chan,:,:,:],
              size(m.dataBG,1), patchAv, numPatches, size(m.dataBG,4), : ), dims=(2,4))

    if get_gtk_property(m["cbSubtractBG"], :active, Bool)
      data_ .-= dataBG_
    end
    if showBG
      data_ .= dataBG_
    end
    dataBG_ = vec(dataBG_)
  end

  data_ = vec(data_)
 
  timedata = arraysplit(data_, size(m.data,1)*group, div(size(m.data,1)*group,2))
  sp = DSP.spectrogram(vec(data_), size(m.data,1)*group)

  return timedata, sp
end

################

@guarded function updateData(m::SpectrogramWidget, data::Array, deltaT=1.0, fileModus=false)
  maxValTPOld = get_gtk_property(m["adjMinTP"],:upper, Int64)
  maxValFreOld = get_gtk_property(m["adjMinFre"],:upper, Int64)
  allFrames = get_gtk_property(m["cbShowAllFrames"],  :active, Bool)

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
  maxGrouping = allFrames ? size(m.data,3)*size(m.data,4) : size(m.data,3)

  @idle_add_guarded begin
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

@guarded function updateData(m::SpectrogramWidget, filenames::Vector{<:AbstractString})
  m.filenamesData = filenames
  @idle_add_guarded begin
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

@guarded function updateData(m::SpectrogramWidget, filename::String)
  updateData(m, [filename])
  return nothing
end

################

@guarded function showData(widgetptr::Ptr, m::SpectrogramWidget)
  if length(m.data) > 0 && !m.updatingData
    chan = max(get_gtk_property(m["adjRxChan"], :value, Int64),1)
    patch = max(get_gtk_property(m["adjPatch"], :value, Int64),1)
    minTP = max(get_gtk_property(m["adjMinTP"], :value, Int64),1)
    maxTP = max(get_gtk_property(m["adjMaxTP"], :value, Int64),1)
    minFr = max(get_gtk_property(m["adjMinFre"], :value, Int64),1)
    maxFr = max(get_gtk_property(m["adjMaxFre"], :value, Int64),1)
    group = get_gtk_property(m["adjGrouping"],:value,Int64)
    logVal = get_gtk_property(m["adjLogPlot"],:value, Float64)
    numSignals = size(m.data,5)
    showFD = get_gtk_property(m["cbShowFreq"], :active, Bool)
    numShownFrames = size(m.data,4)

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
    data_ = timedata[patch]
    m.rangeTD = extrema(data_)

    maxFr = min(maxFr,size(sp.power,1))
    maxTP = min(maxTP,size(data_,1))
    minFr = min(minFr,size(sp.power,1))
    minTP = min(minTP,size(data_,1))

    spdata = sp.power[minFr:maxFr,:]
    maxT = m.deltaT*size(m.data,1)*size(m.data,3)*numShownFrames/1000
    
    if size(spdata,1) > 2^15 # Magic number of Winston image display
      sliceFr = 1:ceil(Int,size(spdata,1)/2^15):size(spdata,1)
    else
      sliceFr = Colon()
    end

    if size(spdata,2) > 2^15 # Magic number of Winston image display
      sliceTime = 1:ceil(Int,size(spdata,2)/2^15):size(spdata,2)
    else
      sliceTime = Colon()
    end

    Winston.colormap(convert.(RGB{N0f8},cmap("viridis")))
    psp = Winston.imagesc( (0.0, maxT), 
                           ((minFr-1)/size(sp.power,1) / m.deltaT / 2.0, 
                               (maxFr-1)/size(sp.power,1) / m.deltaT / 2.0 ), 
                          log.(10.0^(-(2+10*logVal)) .+ spdata[sliceFr, sliceTime] ) )

    patch_ = patch/size(sp.power,2) *  maxT
    Winston.add(psp, Winston.Curve([patch_,patch_], [0,(maxFr-1)/size(sp.power,1) / m.deltaT / 2.0], 
                                   kind="solid", color="white", lw=10) )

    Winston.ylabel("freq / kHz")
    Winston.xlabel("t / s")

    @idle_add_guarded display(m.cSpect, psp)

    timePoints = (0:(length(data_)-1)).*m.deltaT
   
    maxPoints = 5000
    sp_ = length(minTP:maxTP) > maxPoints ? round(Int,length(minTP:maxTP) / maxPoints)  : 1
    steps = minTP:sp_:maxTP
   
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
      m.rangeFD = extrema(freqdata)
      spFr = length(minFr:maxFr) > maxPoints ? round(Int,length(minFr:maxFr) / maxPoints)  : 1

      stepsFr = minFr:spFr:maxFr

      p2 = Winston.semilogy(freq[stepsFr],freqdata[stepsFr,patch],color=colors[1],linewidth=3)

      #Winston.ylabel("u / V")
      Winston.xlabel("f / kHz")
      if !autoRangingFD
          Winston.ylim(minValFD, maxValFD)
      end
    else
      @guarded Gtk4.draw(m.cFD) do widget
        
        ctx = getgc(m.cFD)
        h = height(ctx)
        w = width(ctx)
        Cairo.set_source_rgb(ctx,1.0,1.0,1.0)
        Cairo.rectangle(ctx, 0,0,w,h)
        Cairo.paint(ctx)
        Cairo.stroke(ctx)
      end
    end


    @idle_add_guarded display(m.cTD, p1)
    if showFD
      @idle_add_guarded display(m.cFD, p2)
    end

  end
  return nothing
end


