import Base: getindex

mutable struct SFViewerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  dv::DataViewerWidget
  bSF::MPIFile
  updating::Bool
  maxFreq::Int
  maxChan::Int
  SNR::Array{Float64,3}
  SNRSortedIndices::Array{Float64,1}
  SNRSortedIndicesInverse::Array{Float64,1}
  mixFac::Array{Float64,2}
  mxyz::Array{Float64,1}
  updatingMOWidgets::Bool
  updatingSOWidget::Bool
  grid::GtkGridLeaf
end


getindex(m::SFViewerWidget, w::AbstractString) = G_.object(m.builder, w)

function SFViewerWidget()
  uifile = joinpath(@__DIR__,"builder","mpiLab.ui")

  b = Builder(filename=uifile)
  mainBox = Box(:h) #G_.object(b, "boxSFViewer")

  m = SFViewerWidget(mainBox.handle, b, DataViewerWidget(),
                  BrukerFile(), false, 0, 0, zeros(0,0,0),
                  zeros(0), zeros(0), zeros(0,0), zeros(0), false, false, Grid())
  Gtk.gobject_move_ref(m, mainBox)

  m.grid[1,1] = m.dv
  m.grid[1,2] = Canvas()
  set_gtk_property!(m.grid[1,2], :height_request, 200)
  #set_gtk_property!(m.grid, :row_homogeneous, true)
  #set_gtk_property!(m.grid, :column_homogeneous, true)
  push!(m, m.grid)
  set_gtk_property!(m, :fill, m.grid, true)
  set_gtk_property!(m, :expand, m.grid, true)
  push!(m, m["swSFViewer"])

  function updateSFMixO( widget )
    if !m.updatingMOWidgets && !m.updating
      m.updatingMOWidgets = true
      mx = get_gtk_property(m["adjSFMixX"],:value, Int64)
      my = get_gtk_property(m["adjSFMixY"],:value, Int64)
      mz = get_gtk_property(m["adjSFMixZ"],:value, Int64)

      freq = 0
      m_ = [mx,my,mz]
      for d=1:length(m.mxyz)
       freq += m_[d]*m.mxyz[d]
      end

      freq = clamp(freq,0,m.maxFreq-1)

      Gtk.@sigatom begin
        set_gtk_property!(m["adjSFFreq"],:value, freq)
        m.updatingMOWidgets = false
      end
    end
  end

  function updateSFSignalOrdered( widget )
    if !m.updatingSOWidget && !m.updating
      m.updatingSOWidget = true
      k = m.SNRSortedIndices[get_gtk_property(m["adjSFSignalOrdered"],:value, Int64)]

      recChan = clamp(div(k,m.maxFreq)+1,1,3)
      freq = clamp(mod1(k-1,m.maxFreq),0,m.maxFreq-1)

      Gtk.@sigatom begin
        set_gtk_property!(m["adjSFRecChan"],:value, recChan)
        set_gtk_property!(m["adjSFFreq"],:value, freq)
        m.updatingSOWidget = false
      end
    end
  end

  @time signal_connect(m["cbSFBGCorr"], :toggled) do w
    updateSF(m)
  end
  @time signal_connect(m["adjSFPatch"], "value_changed") do w
    updateSF(m)
  end
  @time signal_connect(m["adjSFRecChan"], "value_changed") do w
    updateSF(m)
  end
  @time signal_connect(m["adjSFFreq"], "value_changed") do w
    updateSF(m)
  end

  for w in Any["adjSFMixX","adjSFMixY","adjSFMixZ"]
    signal_connect(updateSFMixO, m[w], "value_changed")
  end

  signal_connect(updateSFSignalOrdered, m["adjSFSignalOrdered"], "value_changed")

  return m
end

function updateSF(m::SFViewerWidget)
  if !m.updating
    m.updating = true
    freq = get_gtk_property(m["adjSFFreq"],:value, Int64)+1
    recChan = get_gtk_property(m["adjSFRecChan"],:value, Int64)
    period = get_gtk_property(m["adjSFPatch"],:value, Int64)

    bgcorrection = get_gtk_property(m["cbSFBGCorr"],:active, Bool)

    k = freq + m.maxFreq*((recChan-1))
    #  + m.maxChan*(period-1)

    sfData_ = getSF(m.bSF, Int64[k], returnasmatrix = true, bgcorrection=bgcorrection)[1][:,period]
    sfData_[:] ./= rxNumSamplingPoints(m.bSF)

    sfData = reshape(sfData_, calibSize(m.bSF)...)

    Gtk.@sigatom set_gtk_property!(m["entSFSNR"],:text,string(round(m.SNR[freq,recChan,period],digits=2)))
    Gtk.@sigatom set_gtk_property!(m["entSFSNR2"],:text,string(round(calcSNRF(sfData_),digits=2)))

    Gtk.@sigatom begin
      p = Winston.semilogy(vec(m.SNR[:,recChan,period]),"b-",linewidth=5)
      Winston.plot(p,[freq],[m.SNR[freq,recChan,period]],"rx",linewidth=5,ylog=true)
      #Winston.ylabel("u / V")
      #Winston.xlabel("f / kHz")
      Winston.title("SNR")
      display(m.grid[1,2] ,p)
      showall(m)
    end

    Gtk.@sigatom begin
      #updatingMOWidgets = true # avoid circular signals
      set_gtk_property!(m["adjSFMixX"],:value, m.mixFac[freq,1])
      set_gtk_property!(m["adjSFMixY"],:value, m.mixFac[freq,2])
      set_gtk_property!(m["adjSFMixZ"],:value, m.mixFac[freq,3])
      #updatingMOWidgets = false
    end

    Gtk.@sigatom begin
      m.updatingSOWidget = true
      #updatingSOWidget = true # avoid circular signals
      set_gtk_property!(m["adjSFSignalOrdered"],:value, m.SNRSortedIndicesInverse[k] )
      #updatingSOWidget = false
      m.updatingSOWidget = false
    end

    c = reshape(sfData, 1, size(sfData,1), size(sfData,2), size(sfData,3), 1)
    c_ = cat(abs.(c),angle.(c), dims=1)
    im = AxisArray(c_, (:color,:x,:y,:z,:time),
                        tuple(1.0, 1.0, 1.0, 1.0, 1.0),
                        tuple(0.0, 0.0, 0.0, 0.0, 0.0))

    imMeta = ImageMeta(im, Dict{String,Any}())

    updateData!(m.dv, imMeta)
    m.updating = false
  end
end

function calcSNRF(im)
  imFT = fft(im)
  N = size(imFT)
  if ndims(im) == 1
    Noise = mean(abs.(imFT[div(N[1],2):div(N[1],2)+1]))
  elseif ndims(im) == 2
    x = mean(abs.(imFT[div(N[1],2):div(N[1],2)+1,:]))
    y = mean(abs.(imFT[:,div(N[2],2):div(N[2],2)+1]))
    Noise = (x+y)/2
  elseif ndims(im) == 3
    x = mean(abs.(imFT[div(N[1],2):div(N[1],2)+1,:,:]))
    y = mean(abs.(imFT[:,div(N[2],2):div(N[2],2)+1,:]))
    z = mean(abs.(imFT[:,:,div(N[3],2):div(N[3],2)+1]))
    Noise = (x+y+z)/3
  else
    error("not implemented")
  end
  Sig = maximum(abs.(im))
  return Sig / Noise * prod(sqrt.(N))
end

function calcSNR(im)
  im = squeeze(im)
  N = size(im)
  imFilt = im #imfilter(abs.(im), Kernel.gaussian(2))
  Sig = maximum(abs.(im))
  mask = abs.(imFilt)/Sig .< 0.02
  Noise = mean(abs.(im[mask]))
  return Sig / Noise
end



function updateData!(m::SFViewerWidget, filenameSF::String)
  m.bSF = MPIFile(filenameSF)
  m.maxFreq = length(frequencies(m.bSF))
  m.maxChan = rxNumChannels(m.bSF)
  m.updating = true
  set_gtk_property!(m["adjSFFreq"],:value, 2  )
  set_gtk_property!(m["adjSFFreq"],:upper, m.maxFreq-1  )
  set_gtk_property!(m["adjSFSignalOrdered"],:value, 1  )
  set_gtk_property!(m["adjSFSignalOrdered"],:upper, m.maxFreq*m.maxChan  )
  set_gtk_property!(m["adjSFMixX"],:value, 0 )
  set_gtk_property!(m["adjSFMixY"],:value, 0 )
  set_gtk_property!(m["adjSFMixZ"],:value, 0 )
  #set_gtk_property!(m["adjSFMixX"],:upper, 16 )
  #set_gtk_property!(m["adjSFMixY"],:upper, 16 )
  #set_gtk_property!(m["adjSFMixZ"],:upper, 16 )
  set_gtk_property!(m["adjSFRecChan"],:value, 1 )
  set_gtk_property!(m["adjSFRecChan"],:upper, m.maxChan )
  set_gtk_property!(m["adjSFPatch"],:value, 1 )
  set_gtk_property!(m["adjSFPatch"],:upper, acqNumPeriodsPerFrame(m.bSF) )

  m.SNR = calibSNR(m.bSF)[:,:,:]
  #m.SNR = calculateSystemMatrixSNR(m.bSF)
  m.SNRSortedIndices = flipud(sortperm(vec(m.SNR)))
  m.SNRSortedIndicesInverse = sortperm(m.SNRSortedIndices)
  m.mixFac = MPIFiles.mixingFactors(m.bSF)
  mxyz, mask, freqNumber = MPIFiles.calcPrefactors(m.bSF)
  m.mxyz = mxyz
  m.updating = false
  updateSF(m)
end
