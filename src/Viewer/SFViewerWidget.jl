export SFViewer

import Base: getindex


mutable struct SFViewerWidget <: Gtk4.GtkPaned
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  dv::DataViewerWidget
  bSF::MPIFile
  updating::Bool
  maxFreq::Int
  maxChan::Int
  SNR::Array{Float64,3}
  freqIndices::Vector{CartesianIndex{2}}
  SNRSortedIndices::Array{Int64,1}
  SNRSortedIndicesInverse::Array{Int64,1}
  SNRSortedIndicesRecChan::Array{Array{Int64,1},1}
  SNRSortedIndicesRecChanInverse::Array{Array{Int64,1},1}
  mixFac::Array{Int64,2}
  mxyz::Array{Int64,1}
  frequencies::Array{Float64,1}
  frequencySelection::Array{Int,1}
  grid::Gtk4.GtkGridLeaf
end

getindex(m::SFViewerWidget, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)

mutable struct SFViewer
  w::Gtk4.GtkWindowLeaf
  sf::SFViewerWidget
end

function SFViewer(filename::AbstractString)
  sfViewerWidget = SFViewerWidget()
  w = GtkWindow("SF Viewer: $(filename)",800,600)
  push!(w,sfViewerWidget)
  show(w)
  updateData!(sfViewerWidget, filename)
  return SFViewer(w, sfViewerWidget)
end

function SFViewerWidget()
  uifile = joinpath(@__DIR__,"..","builder","mpiLab.ui")

  b = GtkBuilder(uifile)
  mainBox = GtkPaned(:h) 

  m = SFViewerWidget(mainBox.handle, b, DataViewerWidget(),
                  BrukerFile(), false, 0, 0, zeros(0,0,0), CartesianIndex{2}[],
                  zeros(0), zeros(0), zeros(0), zeros(0), zeros(0,0), zeros(0), zeros(0), zeros(Int,0), GtkGrid())
  Gtk4.GLib.gobject_move_ref(m, mainBox)

  m.grid[1,1:2] = m.dv
  m.grid[1,3] = GtkCanvas()
  set_gtk_property!(m.grid, :row_homogeneous, true)
  set_gtk_property!(m.grid[1,2], :height_request, 200)

  m[1] = m.grid
  m[2] = m["swSFViewer"]

  Gtk4.resize_start_child(m, true)
  Gtk4.shrink_start_child(m, true)
  Gtk4.resize_end_child(m, false)
  Gtk4.shrink_end_child(m, false)

  G_.set_size_request(m["swSFViewer"], 250, -1)

  function updateSFMixO( widget )
    if !m.updating
      @idle_add_guarded begin
          m.updating = true
          mx = get_gtk_property(m["adjSFMixX"],:value, Int64)
          my = get_gtk_property(m["adjSFMixY"],:value, Int64)
          mz = get_gtk_property(m["adjSFMixZ"],:value, Int64)

          freq = 0
          m_ = [mx,my,mz]
          for d=1:length(m.mxyz)
           freq += m_[d]*m.mxyz[d]
          end

          freq = clamp(freq,0,m.maxFreq-1)
          updateFreq(m, freq)
          updateSigOrd(m)
          updateSF(m)
          m.updating = false
      end
    end
  end

  function updateSFSignalOrdered( widget )
    if !m.updating
      @idle_add_guarded begin
          m.updating = true
	        if !(get_gtk_property(m["cbFixRecChan"],:active, Bool))
            k = m.SNRSortedIndices[get_gtk_property(m["adjSFSignalOrdered"],:value, Int64)]
            recChan = m.freqIndices[k][2]
	        else
	          # fix the current receive channel for ordered signal
	          recChan = get_gtk_property(m["adjSFRecChan"],:value, Int64)
	          k = m.SNRSortedIndicesRecChan[recChan][get_gtk_property(m["adjSFSignalOrdered"],:value, Int64)]
            recChan = m.freqIndices[k][2]
	        end

          freq = m.freqIndices[k][1]
          updateFreq(m, freq)
          updateRecChan(m, recChan)
          updateMix(m)
          updateSF(m)
          m.updating = false

      end
    end
  end

  signal_connect(m["cbSFBGCorr"], :toggled) do w
    @idle_add_guarded updateSF(m)
  end
  
  signal_connect(m["adjSFPatch"], "value_changed") do w
    @idle_add_guarded updateSF(m)
  end
  
  signal_connect(m["adjSNRMinFreq"], "value_changed") do w
    @idle_add_guarded updateSF(m)
  end

  signal_connect(m["adjSNRMaxFreq"], "value_changed") do w
    @idle_add_guarded updateSF(m)
  end

  signal_connect(m["adjSFRecChan"], "value_changed") do w
    if !m.updating
      @idle_add_guarded begin
          m.updating = true
          updateMix(m)
          updateSigOrd(m)
          updateSF(m)
          m.updating = false
      end
    end
  end
  signal_connect(m["adjSFFreq"], "value_changed") do w
    if !m.updating
      @idle_add_guarded begin
          m.updating = true
          updateMix(m)
          updateSigOrd(m)
          updateSF(m)
          m.updating = false
      end
    end
  end

  for w in Any["adjSFMixX","adjSFMixY","adjSFMixZ"]
    signal_connect(updateSFMixO, m[w], "value_changed")
  end

  signal_connect(m["cbFixRecChan"], :toggled) do w
    @idle_add_guarded updateSigOrd(m)
  end
  signal_connect(updateSFSignalOrdered, m["adjSFSignalOrdered"], "value_changed")

  signal_connect(m["btnRecalcSNR"], :clicked) do w
    @idle_add_guarded recalcSNR(m)
  end  

  return m
end


function updateFreq(m::SFViewerWidget, freq)
  set_gtk_property!(m["adjSFFreq"],:value, freq)
end

function updateRecChan(m::SFViewerWidget, recChan)
  set_gtk_property!(m["adjSFRecChan"],:value, recChan)
end

function updateSigOrd(m::SFViewerWidget)
  freq = get_gtk_property(m["adjSFFreq"],:value, Int64)+1
  recChan = get_gtk_property(m["adjSFRecChan"],:value, Int64)
  if !(get_gtk_property(m["cbFixRecChan"],:active, Bool))
    k = freq + m.maxFreq*((recChan-1))
    set_gtk_property!(m["adjSFSignalOrdered"],:value, m.SNRSortedIndicesInverse[k] )
  else 
    # fix the current receive channel for ordered signal
    set_gtk_property!(m["adjSFSignalOrdered"],:value, m.SNRSortedIndicesRecChanInverse[recChan][freq] )
  end
end

function updateMix(m::SFViewerWidget)
  freq = get_gtk_property(m["adjSFFreq"],:value, Int64)+1
  set_gtk_property!(m["adjSFMixX"],:value, m.mixFac[freq,1])
  set_gtk_property!(m["adjSFMixY"],:value, m.mixFac[freq,2])
  set_gtk_property!(m["adjSFMixZ"],:value, m.mixFac[freq,3])
end


function updateSF(m::SFViewerWidget)
  freq = get_gtk_property(m["adjSFFreq"],:value, Int64)+1
  recChan = get_gtk_property(m["adjSFRecChan"],:value, Int64)
  period = get_gtk_property(m["adjSFPatch"],:value, Int64)
  minFr = get_gtk_property(m["adjSNRMinFreq"],:value, Int64)+1
  maxFr = get_gtk_property(m["adjSNRMaxFreq"],:value, Int64)+1

  bgcorrection = get_gtk_property(m["cbSFBGCorr"],:active, Bool)
  # disable BG correction if no BG frames are available
  if maximum(Int.(measIsBGFrame(m.bSF))) == 0
    bgcorrection = false
    set_gtk_property!(m["cbSFBGCorr"],:active,false)
  end

  k = CartesianIndex(freq, recChan)

  if !measIsFrequencySelection(m.bSF) || k in m.frequencySelection
    sfData_ = getSF(m.bSF, [k], returnasmatrix = true, bgcorrection=bgcorrection)[1][:,period]
    sfData_[:] ./= rxNumSamplingPoints(m.bSF)
  else
    # set sfData to one for frequencies ∉ frequencySelection
    sfData_ = ones(ComplexF32,prod(calibSize(m.bSF)))
  end

  sfData = reshape(sfData_, calibSize(m.bSF)...)

  set_gtk_property!(m["entSFSNR"],:text,string(round(m.SNR[freq,recChan,period],digits=2)))
  #set_gtk_property!(m["entSFSNR2"],:text,string(round(calcSNRF(sfData_),digits=2)))
  snr5 = [string(sum(m.SNR[:,d,1] .> 5),"   ") for d=1:size(m.SNR,2)]
  set_gtk_property!(m["entSFSNR2"],:text, prod( snr5 ) )


  maxPoints = 5000
  spFr = length(minFr:maxFr) > maxPoints ? round(Int,length(minFr:maxFr) / maxPoints)  : 1

  stepsFr = minFr:spFr:maxFr
  snrCompressed = zeros(length(stepsFr))
  if spFr > 1
    for l=1:length(stepsFr)
      st = stepsFr[l]
      en = min(st+spFr,stepsFr[end])
      snrCompressed[l] = maximum(m.SNR[st:en,recChan,period])
    end
  else
    snrCompressed = vec(m.SNR[stepsFr,recChan,period])
  end

  fFD, axFD, lFD1 = CairoMakie.lines(m.frequencies[stepsFr], snrCompressed, 
                          figure = (; resolution = (1000, 800), fontsize = 12),
                          axis = (; title = "SNR", yscale=log10),
                          color = CairoMakie.RGBf(colors[1]...))
  CairoMakie.scatter!(axFD, [m.frequencies[freq]], [m.SNR[freq,recChan,period]],
                      markersize=9, color=:red, marker=:xcross)

  CairoMakie.autolimits!(axFD)
  if m.frequencies[stepsFr[end]] > m.frequencies[stepsFr[1]]
    CairoMakie.xlims!(axFD, m.frequencies[stepsFr[1]], m.frequencies[stepsFr[end]])
  end
  axFD.xlabel = "f / kHz"

  drawonto(m.grid[1,3], fFD)

  show(m)

  c = reshape(sfData, 1, size(sfData,1), size(sfData,2), size(sfData,3), 1)
  c_ = cat(abs.(c),angle.(c), dims=1)
  im = AxisArray(c_, (:color,:x,:y,:z,:time),
                      tuple(1.0, 1.0, 1.0, 1.0, 1.0),
                      tuple(0.0, 0.0, 0.0, 0.0, 0.0))

  imMeta = ImageMeta(im, Dict{Symbol,Any}())

  updateData!(m.dv, imMeta, ampPhase=true)
end

function updateData!(m::SFViewerWidget, filenameSF::String)
  m.bSF = MPIFile(filenameSF, fastMode=true)
  m.maxChan = rxNumChannels(m.bSF)
  m.frequencies = rxFrequencies(m.bSF)./1000
  m.maxFreq = length(m.frequencies)
  if measIsFrequencySelection(m.bSF)
    # Workaround for FrequencySelection
    m.frequencySelection = vcat([measFrequencySelection(m.bSF).+i*m.maxFreq for i=0:m.maxChan-1]...)
  end
  m.updating = true
  set_gtk_property!(m["adjSFFreq"],:value, 2  )
  set_gtk_property!(m["adjSFFreq"],:upper, m.maxFreq-1  )
  if measIsFrequencySelection(m.bSF)
    # first frequency of frequencySelection
    set_gtk_property!(m["adjSFFreq"],:value, m.frequencySelection[1]-1 )
  end
  set_gtk_property!(m["adjSFSignalOrdered"],:value, 1  )
  set_gtk_property!(m["adjSFSignalOrdered"],:upper, m.maxFreq*m.maxChan  )
  set_gtk_property!(m["adjSFMixX"],:value, 0 )
  set_gtk_property!(m["adjSFMixY"],:value, 0 )
  set_gtk_property!(m["adjSFMixZ"],:value, 0 )
  set_gtk_property!(m["adjSFRecChan"],:value, 1 )
  set_gtk_property!(m["adjSFRecChan"],:upper, m.maxChan )
  set_gtk_property!(m["adjSFPatch"],:value, 1 )
  set_gtk_property!(m["adjSFPatch"],:upper, acqNumPeriodsPerFrame(m.bSF) )
  set_gtk_property!(m["adjSNRMinFreq"],:upper, m.maxFreq-1 )
  set_gtk_property!(m["adjSNRMaxFreq"],:upper, m.maxFreq-1 )
  set_gtk_property!(m["adjSNRMinFreq"],:value, 0 )
  set_gtk_property!(m["adjSNRMaxFreq"],:value, m.maxFreq-1 )


  m.SNR = calibSNR(m.bSF)[:,:,:]
  if measIsFrequencySelection(m.bSF)
    # set SNR to one for frequencies ∉ frequencySelection
    snr = ones(Float64, m.maxFreq*size(m.SNR,2), size(m.SNR,3))
    snr[m.frequencySelection,:] = reshape(calibSNR(m.bSF), size(m.SNR,1)*size(m.SNR,2), :)
    m.SNR = reshape(snr, m.maxFreq, size(m.SNR,2), size(m.SNR,3))
  end

  m.freqIndices = collect(vec(CartesianIndices((m.maxFreq, m.maxChan))))

  updateDerivedSNRLUTs(m)

  m.mixFac = MPIFiles.mixingFactors(m.bSF)
  mxyz, mask, freqNumber = MPIFiles.calcPrefactors(m.bSF)
  m.mxyz = mxyz

  set_gtk_property!(m["adjSFMixX"],:upper, maximum(m.mixFac[:, 1]))
  set_gtk_property!(m["adjSFMixY"],:upper, maximum(m.mixFac[:, 2]))
  set_gtk_property!(m["adjSFMixZ"],:upper, maximum(m.mixFac[:, 3]))


  # show frequency component with highest SNR
  k = m.freqIndices[m.SNRSortedIndices[1]]
  recChan = k[2]
  freq = k[1]
  updateFreq(m, freq)
  updateRecChan(m, recChan)


  updateMix(m)
  updateSigOrd(m)
  updateSF(m)
  m.updating = false
end

function recalcSNR(m)
  @info "Recalculate SNR"
  m.updating = true
  m.SNR = calculateSystemMatrixSNR(m.bSF)
  updateDerivedSNRLUTs(m)
  m.updating = false
  updateSF(m)
end

function updateDerivedSNRLUTs(m)
  m.SNRSortedIndices = reverse(sortperm(vec(m.SNR)))
  m.SNRSortedIndicesInverse = sortperm(m.SNRSortedIndices)
  # sort SNR channel-wise
  m.SNRSortedIndicesRecChan = [reverse(sortperm(m.SNR[:,i,1])) for i=1:m.maxChan]
  m.SNRSortedIndicesRecChanInverse = [sortperm(snr) for snr in m.SNRSortedIndicesRecChan]
  return
end
