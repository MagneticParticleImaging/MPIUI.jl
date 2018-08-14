import Base: getindex

type SFViewerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder
  dv
  bSF
  updating::Bool
  maxFreq
  maxChan
  SNR
  SNRSortedIndices
  SNRSortedIndicesInverse
  mixFac
  mxyz
  updatingMOWidgets
  updatingSOWidget
  grid
end


getindex(m::SFViewerWidget, w::AbstractString) = G_.object(m.builder, w)

function SFViewerWidget()
  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","mpiLab.ui")

  b = Builder(filename=uifile)
  mainBox = Box(:h) #G_.object(b, "boxSFViewer")

  m = SFViewerWidget(mainBox.handle, b,
                  nothing, nothing, false, nothing,nothing, nothing,
                  nothing, nothing, zeros(0,0,0,0), zeros(0), false, false, nothing)
  Gtk.gobject_move_ref(m, mainBox)

  m.grid = Grid()
  m.dv = DataViewerWidget()
  m.grid[1,1] = m.dv
  m.grid[1,2] = Canvas()
  setproperty!(m.grid[1,2], :height_request, 200)
  #setproperty!(m.grid, :row_homogeneous, true)
  #setproperty!(m.grid, :column_homogeneous, true)
  push!(m, m.grid)
  setproperty!(m, :fill, m.grid, true)
  setproperty!(m, :expand, m.grid, true)
  push!(m, m["swSFViewer"])

  function updateSFMixO( widget )
    if !m.updatingMOWidgets && !m.updating
      m.updatingMOWidgets = true
      mx = getproperty(m["adjSFMixX"],:value, Int64)
      my = getproperty(m["adjSFMixY"],:value, Int64)
      mz = getproperty(m["adjSFMixZ"],:value, Int64)

      freq = 0
      m_ = [mx,my,mz]
      for d=1:length(m.mxyz)
       freq += m_[d]*m.mxyz[d]
      end

      freq = clamp(freq,0,m.maxFreq-1)

      Gtk.@sigatom begin
        setproperty!(m["adjSFFreq"],:value, freq)
        m.updatingMOWidgets = false
      end
    end
  end

  function updateSFSignalOrdered( widget )
    if !m.updatingSOWidget && !m.updating
      m.updatingSOWidget = true
      k = m.SNRSortedIndices[getproperty(m["adjSFSignalOrdered"],:value, Int64)]

      recChan = clamp(div(k,m.maxFreq)+1,1,3)
      freq = clamp(mod1(k-1,m.maxFreq),0,m.maxFreq-1)

      Gtk.@sigatom begin
        setproperty!(m["adjSFRecChan"],:value, recChan)
        setproperty!(m["adjSFFreq"],:value, freq)
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
    freq = getproperty(m["adjSFFreq"],:value, Int64)+1
    recChan = getproperty(m["adjSFRecChan"],:value, Int64)
    period = getproperty(m["adjSFPatch"],:value, Int64)

    bgcorrection = getproperty(m["cbSFBGCorr"],:active, Bool)

    k = freq + m.maxFreq*((recChan-1))
    #  + m.maxChan*(period-1)

    sfData = getSF(m.bSF, Int64[k], returnasmatrix = false, bgcorrection=bgcorrection)[1][:,:,:,period]

    Gtk.@sigatom setproperty!(m["entSFSNR"],:text,string(round(m.SNR[freq,recChan,period],2)))

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
      setproperty!(m["adjSFMixX"],:value, m.mixFac[freq,1])
      setproperty!(m["adjSFMixY"],:value, m.mixFac[freq,2])
      setproperty!(m["adjSFMixZ"],:value, m.mixFac[freq,3])
      #updatingMOWidgets = false
    end

    Gtk.@sigatom begin
      m.updatingSOWidget = true
      #updatingSOWidget = true # avoid circular signals
      setproperty!(m["adjSFSignalOrdered"],:value, m.SNRSortedIndicesInverse[k] )
      #updatingSOWidget = false
      m.updatingSOWidget = false
    end

    c = reshape(sfData, 1, size(sfData,1), size(sfData,2), size(sfData,3), 1)
    c_ = cat(1,abs.(c),angle.(c))
    im = AxisArray(c_, (:color,:x,:y,:z,:time),
                        tuple(1.0, 1.0, 1.0, 1.0, 1.0),
                        tuple(0.0, 0.0, 0.0, 0.0, 0.0))

    imMeta = ImageMeta(im, Dict{String,Any}())

    updateData!(m.dv, imMeta)
    m.updating = false
  end
end

function updateData!(m::SFViewerWidget, filenameSF::String)
  m.bSF = MPIFile(filenameSF)
  m.maxFreq = length(frequencies(m.bSF))
  m.maxChan = rxNumChannels(m.bSF)

  m.updating = true
  setproperty!(m["adjSFFreq"],:value, 2  )
  setproperty!(m["adjSFFreq"],:upper, m.maxFreq-1  )
  setproperty!(m["adjSFSignalOrdered"],:value, 1  )
  setproperty!(m["adjSFSignalOrdered"],:upper, m.maxFreq*m.maxChan  )
  setproperty!(m["adjSFMixX"],:value, 0 )
  setproperty!(m["adjSFMixY"],:value, 0 )
  setproperty!(m["adjSFMixZ"],:value, 0 )
  #setproperty!(m["adjSFMixX"],:upper, 16 )
  #setproperty!(m["adjSFMixY"],:upper, 16 )
  #setproperty!(m["adjSFMixZ"],:upper, 16 )
  setproperty!(m["adjSFRecChan"],:value, 1 )
  setproperty!(m["adjSFRecChan"],:upper, m.maxChan )
  setproperty!(m["adjSFPatch"],:value, 1 )
  setproperty!(m["adjSFPatch"],:upper, acqNumPeriodsPerFrame(m.bSF) )

  m.SNR = calibSNR(m.bSF)[:,:,:]
  m.SNRSortedIndices = flipud(sortperm(vec(m.SNR)))
  m.SNRSortedIndicesInverse = sortperm(m.SNRSortedIndices)
  m.mixFac = MPIFiles.mixingFactors(m.bSF)
  mxyz, mask, freqNumber = MPIFiles.calcPrefactors(m.bSF)
  m.mxyz = mxyz
  m.updating = false
  updateSF(m)
end
