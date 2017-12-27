import Base: getindex

type SFViewer2
  builder
  dv
end

getindex(m::SFViewer2, w::AbstractString) = G_.object(m.builder, w)

function SFViewer2(filenameSF)

  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","main.ui")

  m = SFViewer2( Builder(filename=uifile),
                  nothing)

  m.dv = DataViewerWidget()
  push!(m["boxLR1"], m.dv)
  setproperty!(m["boxLR1"], :fill, m.dv, true)
  setproperty!(m["boxLR1"], :expand, m.dv, true)

  bSF = BrukerFile(filenameSF)
  maxFreq = length(frequencies(bSF))

  setproperty!(m["adjSFFreq"],:upper, maxFreq-1  )
  setproperty!(m["adjSFSignalOrdered"],:upper, maxFreq*3  )
  setproperty!(m["adjSFFreq"],:value, 2097  )
  setproperty!(m["adjSFMixX"],:upper, 16 )
  setproperty!(m["adjSFMixY"],:upper, 16 )
  setproperty!(m["adjSFMixZ"],:upper, 16 )

  SNR = getSNRAllFrequencies(bSF)
  SNRSortedIndices = flipud(sortperm(vec(SNR)))
  SNRSortedIndicesInverse = sortperm(SNRSortedIndices)
  MoList = MixingOrder(bSF)

  updatingMOWidgets = false
  updatingSOWidget = false

  function updateSF( widget )
    freq = getproperty(m["adjSFFreq"],:value, Int64)+1
    recChan = getproperty(m["adjSFRecChan"],:value, Int64)
    bgcorrection = getproperty(m["cbSFBGCorr"],:active, Bool)

    k = freq + (recChan-1)*maxFreq

    sfData = getSF(bSF, Int64[k], returnasmatrix = false, bgcorrection=bgcorrection)

    Gtk.@sigatom setproperty!(m["entSFSNR"],:text,string(round(SNR[freq,recChan],2)))

    Gtk.@sigatom begin
    updatingMOWidgets = true # avoid circular signals
    setproperty!(m["adjSFMixX"],:value, MoList[freq,2])
    setproperty!(m["adjSFMixY"],:value, MoList[freq,3])
    setproperty!(m["adjSFMixZ"],:value, MoList[freq,4])
    updatingMOWidgets = false
    end

    Gtk.@sigatom begin
    updatingSOWidget = true # avoid circular signals
    setproperty!(m["adjSFSignalOrdered"],:value, SNRSortedIndicesInverse[k] )
    updatingSOWidget = false
    end


    c = reshape(abs.(sfData), 1, size(sfData,1), size(sfData,2), size(sfData,3), 1)

    im = AxisArray(c, (:color,:x,:y,:z,:time),
                        tuple(1.0, 1.0, 1.0, 1.0, 1.0),
                        tuple(0.0, 0.0, 0.0, 0.0, 0.0))

    imMeta = ImageMeta(im, Dict{String,Any}())

    updateData!(m.dv, imMeta)

  end

  function updateSFMixO( widget )
    if !updatingMOWidgets
      mx = getproperty(m["adjSFMixX"],:value, Int64)
      my = getproperty(m["adjSFMixY"],:value, Int64)
      mz = getproperty(m["adjSFMixZ"],:value, Int64)

      freq = mixFactorToFreq(bSF, mx, my, mz)

      freq = clamp(freq,0,maxFreq-1)

      Gtk.@sigatom setproperty!(m["adjSFFreq"],:value, freq)
    end
  end

  function updateSFSignalOrdered( widget )
    if !updatingSOWidget
      k = SNRSortedIndices[getproperty(m["adjSFSignalOrdered"],:value, Int64)]

      recChan = clamp(div(k,maxFreq)+1,1,3)
      freq = clamp(mod1(k-1,maxFreq),0,maxFreq-1)

      Gtk.@sigatom setproperty!(m["adjSFRecChan"],:value, recChan)
      Gtk.@sigatom setproperty!(m["adjSFFreq"],:value, freq)
    end
  end

  updateSF( nothing )



  signal_connect(updateSF, m["adjSFFreq"], "value_changed")
  signal_connect(updateSF, m["adjSFRecChan"], "value_changed")
  signal_connect(updateSF, m["cbSFBGCorr"], "toggled")


  for w in Any["adjSFMixX","adjSFMixY","adjSFMixZ"]
    signal_connect(updateSFMixO, m[w], "value_changed")
  end

  signal_connect(updateSFSignalOrdered, m["adjSFSignalOrdered"], "value_changed")


  w = m["sfViewerWindow"]
  G_.transient_for(w, mpilab["mainWindow"])
  G_.modal(w,true)
  showall(w)

  return m
end
