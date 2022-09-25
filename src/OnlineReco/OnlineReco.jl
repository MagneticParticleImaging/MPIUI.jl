using Winston
import MPIMeasurements.currentFrame

export onlineRawViewer, onlineReco, currentFrame, finishReco, currentAcquisition

const _acqSimStarted = Ref(false)
const _acqSimStartTime = Ref(now())

# Return the frame that is currently being written
function currentFrame(b::BrukerFile, simulation = false)
  global _acqSimStarted
  global _acqSimStartTime


  if !simulation
    dataFilename = joinpath(b.path,"rawdata.job0")

    nbytes = acqNumAverages(b) == 1 ? 2 : 4
    run(`ls -la $(b.path)`, wait=true)

    framenum = max(div(filesize(dataFilename), nbytes*rxNumChannels(b)*rxNumSamplingPoints(b))-1, 0)
  else
    if !_acqSimStarted[]
      _acqSimStarted[] = true
      _acqSimStartTime[] = now()
    end

    diffTime = now() - _acqSimStartTime[]
    sec = convert(Int,diffTime.value)*1e-3 # Dates.minute(diffTime)*60 + Dates.second(diffTime) + Dates.millisecond(diffTime)*1e-3

    framenum = min.(acqNumFrames(b), floor(Int, sec / 0.0214))
  end
end

function currentFrame(b::MDFFile, simulation = false)
  global _acqSimStarted
  global _acqSimStartTime


  if !_acqSimStarted[]
    _acqSimStarted[] = true
    _acqSimStartTime[] = now()
  end

  diffTime = now() - _acqSimStartTime[]
  sec = convert(Int,diffTime.value)*1e-3 # Dates.minute(diffTime)*60 + Dates.second(diffTime) + Dates.millisecond(diffTime)*1e-3

  framenum = min.(acqNumFrames(b), floor(Int, sec / 0.0214))
end





const dv = Ref{Union{DataViewer,Nothing}}(nothing)

# Important parameter is "skipFrames"
function onlineReco(bSF::MPIFile, b::MPIFile; proj="MIP",
    SNRThresh=-1, minFreq=0, maxFreq=1.25e6, recChannels=1:numReceivers(b), sortBySNR=false,
    sparseTrafo=nothing, redFactor=0.01, bEmpty=nothing, skipFrames=0, startFrame=0, outputdir=nothing,
    numAverages=1, bgFrames=1, recoParamsFile=nothing, currentAcquisitionFile=nothing, 
    spectralLeakageCorrection=false,
    simulation=false,trustedFOV=true, kargs...) 

   global _acqSimStarted
   global dv
   _acqSimStarted[] = false

   if dv[] == nothing
     dv[] = DataViewer()
   end

   canvasHist = Canvas()
   dv[].dvw.grid3D[1:2,3] = canvasHist

   #pb = ProgressBar()
   #dv[].grid3D[1:2,4] = pb
   #set_gtk_property!(pb,:fraction,0.1)
   
   showall(dv[].dvw)

  frequencies = filterFrequencies(bSF, minFreq=minFreq, maxFreq=maxFreq,
                                  recChannels=recChannels, SNRThresh=SNRThresh, sortBySNR=sortBySNR)

  bgCorrection = bEmpty != nothing
  if bgCorrection
    uEmpty = getMeasurementsFD(bEmpty, frequencies=frequencies, frames=bgFrames, 
			       numAverages=length(bgFrames),
			       spectralLeakageCorrection=spectralLeakageCorrection)
  end

  @info "Loading System Matrix ..."

  S, grid = getSF(bSF, frequencies, sparseTrafo, "kaczmarz", bgCorrection=bgCorrection, redFactor=redFactor)
  
  D = shape(grid)
  images = Array{Float32,5}(undef, length(bSF), D[1], D[2], D[3], 0)

  #FOVMask = trustedFOV==true ? trustedFOVMask(bSF)[:] : 1
  frame = startFrame>0 ? startFrame : 0
  lastFrame = 0

  while frame < acqNumFrames(b)-1
    if currentAcquisitionFile != nothing
      if currentAcquisitionFile != currentAcquisition()
        return
      end
    end

    newframe = false
    currFrame = currentFrame(b,simulation)
    if currFrame > frame
      lastFrame = frame
      frame = skipFrames==0 ? currFrame : min.(frame+skipFrames, currFrame) #skip frames, if measurement is fast enough
      newframe = true
      #set_gtk_property!(pb,:fraction, currFrame / acqNumFrames(b))
      #showall(dv[].dvw)
      
    end

    @show currFrame

    if newframe
      # Here we take maximum that number of frames that were acquired since
      # the last reconstruction
      currAverages = max.(min.(min.(frame,numAverages), frame-lastFrame),1)
      frames = (frame-currAverages+1):frame
      @show frames
      @show currAverages
      @show spectralLeakageCorrection
      u = getMeasurementsFD(b, frequencies=frequencies, frames=frames, 
			       numAverages=currAverages, spectralLeakageCorrection=spectralLeakageCorrection)

      bgCorrection ? u .= u .- uEmpty : nothing # subtract background signal
      
      if recoParamsFile == nothing
        c = reconstruction(S, u, sparseTrafo=sparseTrafo ; kargs...)
      else
        r = loadRecoParams(recoParamsFile)
        TR = get(r,:repetitionTime,0.0)
        if TR > 0
          r[:nAverages] = max.(round(Int, TR / (dfCycle(b) * acqNumAverages(b))),1)
        end
        numAverages = r[:nAverages]
        c = reconstruction(S, u; sparseTrafo=sparseTrafo, lambda=r[:lambd],
                          iterations=r[:iterations], solver=r[:solver] )
      end

      cB = permutedims(reshape(c, D[1]*D[2]*D[3], length(bSF)),[2,1])
      cF = reshape(cB,length(bSF),D[1],D[2],D[3],1)

      if !any(isnan.(cF))

        images = cat(cF, images, dims=5)
        image = makeAxisArray(images, spacing(grid), grid.center, 1.0) 

        updateData!(dv[].dvw, ImageMeta(image))
        profile = reverse(vec(maximum(arraydata(image),dims=1:4)))
        p = Winston.plot(profile, "b-", linewidth=7)
        Winston.ylabel("c")
        Winston.xlabel("frame")

        setattr(p.y1, draw_ticks=false)
        setattr(p.y2, draw_ticks=false)
        if length(profile) > 1
          setattr(p.x1, draw_ticks=false,
                 ticks=1:(length(profile)-1):length(profile), ticklabels=["1","$(frame)"])
        end
        display(canvasHist, p)
      else
        @info "Reco contains NaNs. Will not display it"
      end
    end
    sleep(0.2)

  end
end

onlineReco(filenameMeas::AbstractString; kargs...) = onlineReco(BrukerFile(sfPath(BrukerFile(filenameMeas))), BrukerFile(filenameMeas); kargs...)

onlineReco(filenameSF::AbstractString, filenameMeas::AbstractString; kargs...) =
   onlineReco(BrukerFile(filenameSF),BrukerFile(filenameMeas); kargs...)


function currentAcquisition()
   path = open("/opt/mpidata/currentAcquisition.txt","r") do fd
         readline(fd)
        end

  if length(path)>0 && isdir(path[1:end-1])
     return path[1:end-1]
  else
     return nothing
  end
end

function finishReco()
  open("/opt/mpidata/currentAcquisition.txt","w") do fd
  end
end

function onlineReco(simulation::Bool=false)
  global dv

  dv[] = nothing
  while true
    c = currentAcquisition()
    @show c
    if c != nothing
      try
        recoargs = loadRecoParams("/opt/mpidata/currentRecoParams.txt")
        bE = get(recoargs,:bEmpty,nothing)
        recoargs[:bEmpty] = bE == nothing ? nothing : MPIFile(bE)
        b = MPIFile(c)

        if recoargs[:SFPath]==nothing
            bSF = MPIFile(sfPath(b) )
        else
          if length(recoargs[:SFPath]) == 1
            bSF = MPIFile(recoargs[:SFPath][1])
          else
            bSF = MultiContrastFile(recoargs[:SFPath])
          end
        end

        TR = get(recoargs,:repetitionTime,0.0)
        if TR > 0
          recoargs[:numAverages] = max.(round(Int, TR / (dfCycle(b) * acqNumAverages(b))),1)
        end
        onlineReco(bSF, b; currentAcquisitionFile=c, 
			recoParamsFile="/opt/mpidata/currentRecoParams.txt", 
			simulation=simulation, recoargs...)
      catch e
        showError(e)
        @warn "Exception" e
      end
      finishReco()
   end
   sleep(0.4)
  end
end
