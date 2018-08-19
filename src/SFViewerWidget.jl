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

    sfData = getSF(m.bSF, Int64[k], returnasmatrix = false, bgcorrection=bgcorrection)[1][:,:,:,period]

    Gtk.@sigatom set_gtk_property!(m["entSFSNR"],:text,string(round(m.SNR[freq,recChan,period],2)))

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
  m.SNRSortedIndices = flipud(sortperm(vec(m.SNR)))
  m.SNRSortedIndicesInverse = sortperm(m.SNRSortedIndices)
  m.mixFac = MPIFiles.mixingFactors(m.bSF)
  mxyz, mask, freqNumber = MPIFiles.calcPrefactors(m.bSF)
  m.mxyz = mxyz
  m.updating = false
  updateSF(m)
end
