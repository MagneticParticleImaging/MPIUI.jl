
import MPIMeasurements.currentFrame

export onlineRawViewer, onlineReco, currentFrame, finishReco, currentAcquisition

_acqSimStarted = false
_acqSimStartTime = 0.0

# Return the frame that is currently beeing written
function currentFrame(b::BrukerFile, simulation = false)
  global _acqSimStarted
  global _acqSimStartTime


  if !simulation
    dataFilename = joinpath(b.path,"rawdata.job0")

    nbytes = numAverages(b) == 1 ? 2 : 4

    framenum = div(filesize(dataFilename), nbytes*rxNumChannels(b)*rxNumSamplingPoints(b))
  else
    if !_acqSimStarted
      _acqSimStarted = true
      _acqSimStartTime = Dates.unix2datetime(time())
    end

    diffTime = Dates.unix2datetime(time()) - _acqSimStartTime
    sec = convert(Int,diffTime.value)*1e-3 # Dates.minute(diffTime)*60 + Dates.second(diffTime) + Dates.millisecond(diffTime)*1e-3

    framenum = min.(acqNumFrames(b), floor(Int, sec / 0.0214))
  end
end

function currentFrame(b::MDFFile, simulation = false)
  global _acqSimStarted
  global _acqSimStartTime


  if !_acqSimStarted
    _acqSimStarted = true
    _acqSimStartTime = Dates.unix2datetime(time())
  end

  diffTime = Dates.unix2datetime(time()) - _acqSimStartTime
  sec = convert(Int,diffTime.value)*1e-3 # Dates.minute(diffTime)*60 + Dates.second(diffTime) + Dates.millisecond(diffTime)*1e-3

  framenum = min.(acqNumFrames(b), floor(Int, sec / 0.0214))
end





const dv = a=Ref{Union{DataViewerWidget,Nothing}}(nothing)

# Important parameter is "skipFrames"
function onlineReco(bSF::Union{T,Vector{T}}, b::MPIFile; proj="MIP",
    SNRThresh=-1, minFreq=0, maxFreq=1.25e6, recChannels=1:numReceivers(b), sortBySNR=false,
    sparseTrafo=nothing, redFactor=0.01, bEmpty=nothing, skipFrames=0, startFrame=0, outputdir=nothing,
    numAverages=1, bgFrames=1, recoParamsFile=nothing, currentAcquisitionFile=nothing, 
    spectralLeakageCorrection=false,
    simulation=false,trustedFOV=true, kargs...) where {T<:MPIFile}

   global _acqSimStarted
   global dv
   _acqSimStarted = false

   if dv[] == nothing
     dv[] = DataViewer()
   end

   canvasHist = Canvas()
   dv[].grid3D[1:2,3] = canvasHist

   showall(dv[])

   bSFFreq=bSF
   if recoParamsFile != nothing
      recoargs=loadRecoParams(recoParamsFile)
      if recoargs[:SFPathFreq]!=nothing
         bSFFreq = MPIFile(recoargs[:SFPathFreq])
      end
   end

  typeof(bSF)<:MPIFile && (bSF = MPIFile[bSF])

  frequencies = filterFrequencies(bSFFreq, minFreq=minFreq, maxFreq=maxFreq,
                                  recChannels=recChannels, SNRThresh=SNRThresh, sortBySNR=sortBySNR)

  bgCorrection = bEmpty != nothing
  if bgCorrection
    uEmpty = getMeasurementsFD(bEmpty, frequencies=frequencies, frames=bgFrames, 
			       numAverages=length(bgFrames),
			       spectralLeakageCorrection=spectralLeakageCorrection)
  end

  # hack! Pretend everything is multispectral
#  typeof(bSF)==BrukerFile && (bSF = BrukerFile[bSF])
  #typeof(bSF)<:MPIFile && (bSF = MPIFile[bSF])

  S, grid = getSF(bSF, frequencies, sparseTrafo, "kaczmarz", bgCorrection=bgCorrection, redFactor=redFactor)

  #shape = getshape(gridSize(bSF))
  #image = initImage(bSF, b, 1, acqNumAverages(b), grid, true)
  D = shape(grid)
  images = Array{Float32,5}(undef, length(bSF), D[1], D[2], D[3], 0)
  #_assignColor!(image)

  #FOVMask = trustedFOV==true ? trustedFOVMask(bSF)[:] : 1
  frame = startFrame>0 ? startFrame : 0
  lastFrame = 0

  #p = Progress(div(acqNumFrames(b)-startFrame,max.(skipFrames,1)), max.(1,skipFrames), "Online reconstruction...", 50)
  while frame < acqNumFrames(b)
    if currentAcquisitionFile != nothing
      if currentAcquisitionFile != currentAcquisition()
        return
      end
    end

    newframe = false
    currFrame = currentFrame(b,simulation)
    if currFrame>frame
      lastFrame = frame
      frame = skipFrames==0 ? currFrame : min.(frame+skipFrames, currFrame) #skip frames, if measurement is fast enough
      newframe = true
      #while p.counter<div(frame-startFrame,max.(skipFrames,1))
      #  next!(p)
      #end
    end

    @show currFrame

    if newframe
      # Here we take maximum that number of frames that were acquired since
      # the last reconstruction
      currAverages = max.(min.(min.(frame,numAverages), frame-lastFrame),1)
      u = getMeasurementsFD(b, frequencies=frequencies, frames=(frame-currAverages+1):frame, 
			       numAverages=currAverages, spectralLeakageCorrection=spectralLeakageCorrection)
      
      bgCorrection ? u .= u .- uEmpty : nothing # subtract background signal
      
      if recoParamsFile == nothing
        c = reconstruction(S, u, sparseTrafo=sparseTrafo ; kargs...)
      else
        r = loadRecoParams(recoParamsFile)
        TR = get(r,:repetitionTime,0.0)
        if TR > 0
          r[:numAverages] = max.(round(Int, TR / (dfCycle(b) * acqNumAverages(b))),1)
        end
        numAverages = r[:numAverages]
        c = reconstruction(S, u; sparseTrafo=sparseTrafo, lambda=r[:lambd],
                          iterations=r[:iterations], solver=r[:solver] )
      end

      images = cat(reshape(c,length(bSF),D[1],D[2],D[3],1), images, dims=5)
      image = makeAxisArray(images, spacing(grid), grid.center, 1.0) 

      updateData!(dv[], ImageMeta(image))

      p = Winston.plot(reverse(vec(maximum(arraydata(image),dims=1:4))),"b-",linewidth=5)
      Winston.ylabel("c / a.u.")
      Winston.xlabel("t / a.u.")
      display(canvasHist, p)
      
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

function onlineReco()
  while true
    c = currentAcquisition()
    if c != nothing
      try
        recoargs = loadRecoParams("/opt/mpidata/currentRecoParams.txt")
        bE = get(recoargs,:bEmpty,nothing)
        recoargs[:bEmpty] = bE == nothing ? nothing : BrukerFile(bE)
        b = BrukerFile(c)

        if recoargs[:SFPath]==nothing
	         bSF = MPIFile(sfPath(b) )
        else
          bSF = MPIFile(recoargs[:SFPath])
        end

        TR = get(recoargs,:repetitionTime,0.0)
        if TR > 0
          recoargs[:numAverages] = max.(round(Int, TR / (dfCycle(b) * acqNumAverages(b))),1)
        end
        onlineReco(bSF, b; currentAcquisitionFile=c, recoParamsFile="/opt/mpidata/currentRecoParams.txt", recoargs...)
      catch e
        @warn "Exception" e
      end
   end
   finishReco()
   sleep(0.4)
  end
end
