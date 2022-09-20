export SFViewer

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
  SNRSortedIndicesRecChan::Array{Array{Float64,1},1}
  SNRSortedIndicesRecChanInverse::Array{Array{Float64,1},1}
  mixFac::Array{Float64,2}
  mxyz::Array{Float64,1}
  frequencies::Array{Float64,1}
  frequencySelection::Array{Int,1}
  grid::GtkGridLeaf
end

getindex(m::SFViewerWidget, w::AbstractString) = G_.object(m.builder, w)

mutable struct SFViewer
  w::Window
  sf::SFViewerWidget
end

function SFViewer(filename::AbstractString)
  sfViewerWidget = SFViewerWidget()
  w = Window("SF Viewer: $(filename)",800,600)
  push!(w,sfViewerWidget)
  showall(w)
  updateData!(sfViewerWidget, filename)
  return SFViewer(w, sfViewerWidget)
end

function SFViewerWidget()
  uifile = joinpath(@__DIR__,"builder","mpiLab.ui")

  b = Builder(filename=uifile)
  mainBox = Box(:h) #G_.object(b, "boxSFViewer")

  m = SFViewerWidget(mainBox.handle, b, DataViewerWidget(),
                  BrukerFile(), false, 0, 0, zeros(0,0,0),
                  zeros(0), zeros(0), zeros(0), zeros(0), zeros(0,0), zeros(0), zeros(0), zeros(Int,0), Grid())
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
            recChan = clamp(div(k,m.maxFreq)+1,1,3)
	  else
	    # fix the current receive channel for ordered signal
	    recChan = get_gtk_property(m["adjSFRecChan"],:value, Int64)
	    k = m.SNRSortedIndicesRecChan[recChan][get_gtk_property(m["adjSFSignalOrdered"],:value, Int64)]
	  end
          freq = clamp(mod1(k-1,m.maxFreq),0,m.maxFreq-1)
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

  k = freq + m.maxFreq*((recChan-1))
  #  + m.maxChan*(period-1)

  if !measIsFrequencySelection(m.bSF) || k in m.frequencySelection
    sfData_ = getSF(m.bSF, Int64[k], returnasmatrix = true, bgcorrection=bgcorrection)[1][:,period]
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

  p = Winston.semilogy(m.frequencies[stepsFr], snrCompressed,"b-",linewidth=5)
  Winston.plot(p,[m.frequencies[freq]],[m.SNR[freq,recChan,period]],"rx",linewidth=5,ylog=true)
  Winston.xlabel("f / kHz")
  Winston.title("SNR")
  display(m.grid[1,2] ,p)
  showall(m)

  c = reshape(sfData, 1, size(sfData,1), size(sfData,2), size(sfData,3), 1)
  c_ = cat(abs.(c),angle.(c), dims=1)
  im = AxisArray(c_, (:color,:x,:y,:z,:time),
                      tuple(1.0, 1.0, 1.0, 1.0, 1.0),
                      tuple(0.0, 0.0, 0.0, 0.0, 0.0))

  imMeta = ImageMeta(im, Dict{Symbol,Any}())

  updateData!(m.dv, imMeta, ampPhase=true)
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
  #set_gtk_property!(m["adjSFMixX"],:upper, 16 )
  #set_gtk_property!(m["adjSFMixY"],:upper, 16 )
  #set_gtk_property!(m["adjSFMixZ"],:upper, 16 )
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

  #m.SNR = calculateSystemMatrixSNR(m.bSF)
  m.SNRSortedIndices = reverse(sortperm(vec(m.SNR)))
  m.SNRSortedIndicesInverse = sortperm(m.SNRSortedIndices)
  # sort SNR channel-wise
  m.SNRSortedIndicesRecChan = [reverse(sortperm(m.SNR[:,i,1])) for i=1:m.maxChan]
  m.SNRSortedIndicesRecChanInverse = [sortperm(snr) for snr in m.SNRSortedIndicesRecChan]
  m.mixFac = MPIFiles.mixingFactors(m.bSF)
  mxyz, mask, freqNumber = MPIFiles.calcPrefactors(m.bSF)
  m.mxyz = mxyz

  updateMix(m)
  updateSigOrd(m)
  updateSF(m)
  m.updating = false
end
