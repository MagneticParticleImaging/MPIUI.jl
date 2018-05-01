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
end


getindex(m::SFViewerWidget, w::AbstractString) = G_.object(m.builder, w)

function SFViewerWidget()
  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","main.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxSFViewer")

  m = SFViewerWidget(mainBox.handle, b,
                  nothing, nothing, false, nothing,nothing, nothing,
                  nothing, nothing)
  Gtk.gobject_move_ref(m, mainBox)

  m.dv = DataViewerWidget()
  push!(m["boxSFViewer"], m.dv)
  setproperty!(m["boxSFViewer"], :fill, m.dv, true)
  setproperty!(m["boxSFViewer"], :expand, m.dv, true)


  #MoList = MixingOrder(bSF)

  #updatingMOWidgets = false
  updatingSOWidget = false

  #=
  function updateSFMixO( widget )
    if !updatingMOWidgets
      mx = getproperty(m["adjSFMixX"],:value, Int64)
      my = getproperty(m["adjSFMixY"],:value, Int64)
      mz = getproperty(m["adjSFMixZ"],:value, Int64)

      freq = mixFactorToFreq(bSF, mx, my, mz)

      freq = clamp(freq,0,maxFreq-1)

      Gtk.@sigatom setproperty!(m["adjSFFreq"],:value, freq)
    end
  end=#

  function updateSFSignalOrdered( widget )
    if !updatingSOWidget
      k = SNRSortedIndices[getproperty(m["adjSFSignalOrdered"],:value, Int64)]

      recChan = clamp(div(k,maxFreq)+1,1,3)
      freq = clamp(mod1(k-1,maxFreq),0,maxFreq-1)

      Gtk.@sigatom setproperty!(m["adjSFRecChan"],:value, recChan)
      Gtk.@sigatom setproperty!(m["adjSFFreq"],:value, freq)
    end
  end

  #updateSF( nothing )

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

  #for w in Any["adjSFMixX","adjSFMixY","adjSFMixZ"]
  #  signal_connect(updateSFMixO, m[w], "value_changed")
  #end

  #signal_connect(updateSFSignalOrdered, m["adjSFSignalOrdered"], "value_changed")


  #w = m["sfViewerWindow"]
  #G_.transient_for(w, mpilab["mainWindow"])
  #G_.modal(w,true)
  #showall(w)

  return m
end

function updateSF(m::SFViewerWidget)
  if !m.updating
    freq = getproperty(m["adjSFFreq"],:value, Int64)+1
    recChan = getproperty(m["adjSFRecChan"],:value, Int64)
    period = getproperty(m["adjSFPatch"],:value, Int64)

    bgcorrection = getproperty(m["cbSFBGCorr"],:active, Bool)

    k = freq + m.maxFreq*((recChan-1) + m.maxChan*(period-1))

    sfData = getSF(m.bSF, Int64[k], returnasmatrix = false, bgcorrection=bgcorrection)

    Gtk.@sigatom setproperty!(m["entSFSNR"],:text,string(round(m.SNR[freq,recChan,period],2)))

    #Gtk.@sigatom begin
    #updatingMOWidgets = true # avoid circular signals
    #setproperty!(m["adjSFMixX"],:value, MoList[freq,2])
    #setproperty!(m["adjSFMixY"],:value, MoList[freq,3])
    #setproperty!(m["adjSFMixZ"],:value, MoList[freq,4])
    #updatingMOWidgets = false
    #end

    Gtk.@sigatom begin
      updatingSOWidget = true # avoid circular signals
      setproperty!(m["adjSFSignalOrdered"],:value, m.SNRSortedIndicesInverse[k] )
      updatingSOWidget = false
    end


    c = reshape(abs.(sfData), 1, size(sfData,1), size(sfData,2), size(sfData,3), 1)

    im = AxisArray(c, (:color,:x,:y,:z,:time),
                        tuple(1.0, 1.0, 1.0, 1.0, 1.0),
                        tuple(0.0, 0.0, 0.0, 0.0, 0.0))

    imMeta = ImageMeta(im, Dict{String,Any}())

    updateData!(m.dv, imMeta)
  end
end

function updateData!(m::SFViewerWidget, filenameSF::String)
  m.bSF = MPIFile(filenameSF)
  m.maxFreq = length(frequencies(m.bSF))
  m.maxChan = rxNumChannels(m.bSF)

  m.updating = true
  setproperty!(m["adjSFFreq"],:upper, m.maxFreq-1  )
  setproperty!(m["adjSFSignalOrdered"],:upper, m.maxFreq*3  )
  setproperty!(m["adjSFFreq"],:value, 2097  )
  setproperty!(m["adjSFMixX"],:upper, 16 )
  setproperty!(m["adjSFMixY"],:upper, 16 )
  setproperty!(m["adjSFMixZ"],:upper, 16 )
  setproperty!(m["adjSFRecChan"],:upper, m.maxChan )
  setproperty!(m["adjSFPatch"],:upper, acqNumPeriodsPerFrame(m.bSF) )

  m.SNR = calibSNR(m.bSF)[:,:,:]
  m.SNRSortedIndices = flipud(sortperm(vec(m.SNR)))
  m.SNRSortedIndicesInverse = sortperm(m.SNRSortedIndices)
  m.updating = false
  updateSF(m)
end
