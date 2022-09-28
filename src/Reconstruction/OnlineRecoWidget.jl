

mutable struct OnlineRecoWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  field::Symbol
  params::ReconstructionParameter
  systemMatrix
  freq
  recoGrid


  function OnlineRecoWidget(field::Symbol, params=defaultRecoParams()) #, value::Sequence, scanner::MPIScanner)
    uifile = joinpath(@__DIR__, "..", "builder", "reconstructionParams.ui")
    b = Builder(filename=uifile)
  
    #box = Box(:v)
    #exp = Expander(box, "Reconstruction")
    #push!(exp, recoParams)

    recoParams = ReconstructionParameter(params) 
    #push!(box, recoParams)

    #addTooltip(object_(pw.builder, "lblSequence", GtkLabel), tooltip)
    m = new(recoParams.handle, b, field, recoParams, nothing, nothing, nothing) 
    Gtk.gobject_move_ref(m, recoParams)


    initCallbacks(m)
    return m
  end
  
end

getindex(m::OnlineRecoWidget, w::AbstractString) = G_.object(m.builder, w)


function initCallbacks(m::OnlineRecoWidget)

end



# THIS is a copy from Offline Widget
function updateSF(m::OnlineRecoWidget)
  params = getParams(m.params)

  bgcorrection = (params[:emptyMeasPath] != nothing) || params[:bgCorrectionInternal]
                 
  m.freq = filterFrequencies(m.params.bSF, minFreq=params[:minFreq], maxFreq=params[:maxFreq],
                             SNRThresh=params[:SNRThresh], recChannels=params[:recChannels],
                             numPeriodAverages = params[:numPeriodAverages], 
                             numPeriodGrouping = params[:numPeriodGrouping],
                             maxMixingOrder = params[:maxMixingOrder])


  @info "Reloading SF"
 
  m.systemMatrix, m.recoGrid = getSF(m.params.bSF, m.freq, params[:sparseTrafo], params[:solver], bgcorrection=bgcorrection,
                      loadasreal = params[:loadasreal], loadas32bit = params[:loadas32bit],
                      redFactor = params[:redFactor], numPeriodAverages = params[:numPeriodAverages], 
                      numPeriodGrouping = params[:numPeriodGrouping], gridsize = params[:gridShape])

  m.params.sfParamsChanged = false

  return nothing
end


function execute_(m::OnlineRecoWidget, data, dv)
  @tspawnat 2 execute__(m, data, dv)
  #execute_(m, data, dv)
end

@guarded function execute__(m::OnlineRecoWidget, data, dv)
  
  @info "Performing Reconstruction"

  params = getParams(m.params)

  if m.params.sfParamsChanged
    updateSF(m)
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  #if params[:emptyMeasPath] != nothing
  #  params[:bEmpty] = MPIFile( params[:emptyMeasPath] )
  #end

  # If S is processed and fits not to the measurements because of numPeriodsGrouping
  # or numPeriodAverages being applied we need to set these so that the 
  # measurements are loaded correctly

  @info "$(rxNumSamplingPoints(m.params.bSF[1]))   $(size(data,1))"

  if rxNumSamplingPoints(m.params.bSF[1]) > size(data,1)
    data = reshape(data, rxNumSamplingPoints(m.params.bSF[1]), size(data,2), :, size(data,3))
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  @info "$(acqNumPeriodsPerFrame(m.params.bSF[1]))   $(size(data,3))"

  if acqNumPeriodsPerFrame(m.params.bSF[1]) < size(data,3)
    #params[:numPeriodAverages] = acqNumPeriodsPerFrame(m.bMeas) ÷ (acqNumPeriodsPerFrame(m.params.bSF[1]) * params[:numPeriodGrouping])
    error("Implement me!")
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  # apply FFT
  if measIsFourierTransformed(m.params.bSF[1])
    data = rfft(data, 1)
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"


  #=if tfCorrection && !measIsTFCorrected(f)
    tf = rxTransferFunction(f)
    inductionFactor = rxInductionFactor(f)
    data[2:end,:,:,:] ./= tf[2:end,:,:,:]
    @warn "This measurement has been corrected with a Transfer Function. Name of TF: $(rxTransferFunctionFileName(f))"
    if inductionFactor != nothing
       	for k=1:length(inductionFactor)
       		data[:,k,:,:] ./= inductionFactor[k]
       	end
    end
  end =#

  if m.freq != nothing
    # here we merge frequencies and channels
    data = reshape(data, size(data,1)*size(data,2), size(data,3), size(data,4))
    data = data[m.freq, :, :]
  end

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  if eltype(m.systemMatrix) <: Real
    data = MPIFiles.returnasreal(data)
  end

  data = reshape(data, :, size(data,3))

  @info "Size SM = $(size(m.systemMatrix)),   Size data = $(size(data))"

  c = MPIReco.reconstruction(m.systemMatrix, data; shape=shape(m.recoGrid), params...)

  #conc = MPIReco.reconstruction(m.systemMatrix, m.params.bSF, m.bMeas, m.freq, m.recoGrid; params...)

  D = shape(m.recoGrid)
  numChan = length(m.params.bSF)
  cB = permutedims(reshape(c, D[1]*D[2]*D[3], numChan),[2,1])
  cF = reshape(cB, numChan, D[1], D[2], D[3], 1)

  #images = cat(cF, images, dims=5)
  cF = makeAxisArray(cF, spacing(m.recoGrid), m.recoGrid.center, 1.0) 

  cF = ImageMeta(cF)

  #m.recoResult = conc
  #m.recoResult.recoParams = getParams(m.params)

  @idle_add_guarded begin
    updateData!(dv, cF)
  end

  return nothing
end

#=
@guarded function updateData!(m::OfflineRecoWidget, filenameMeas, study=nothing, experiment=nothing)
  if filenameMeas != nothing
    m.bMeas = MPIFile(filenameMeas)
    set_gtk_property!(m.params["adjFrame"],:upper, acqNumFrames(m.bMeas))
    set_gtk_property!(m.params["adjLastFrame"],:upper, acqNumFrames(m.bMeas))
    try
      if filepath(m.params.bSF[1])=="" #&& isdir( sfPath(m.bMeas) )
        #setSF(m, sfPath(m.bMeas)  )
      elseif isdir( filepath(m.params.bSF[1]) ) || isfile( filepath(m.params.bSF[1]) )
        setSF(m.params, filepath(m.params.bSF[1]) )
      end
    catch e
      @show e
    end
    initBGSubtractionWidgets(m.params, study, experiment)
    m.currentStudy = study
    m.currentExperiment = experiment
  end
  return nothing
end
=#