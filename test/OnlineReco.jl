using MPIUI
using HTTP

filenameSM = "systemMatrix.mdf"
filenameMeas = "measurement.mdf"

if !isfile(filenameSM)
  HTTP.open("GET", "http://media.tuhh.de/ibi/mdfv2/systemMatrix_V2.mdf") do http
    open(filenameSM, "w") do file
        write(file, http)
    end
  end
end
if !isfile(filenameMeas)
  HTTP.open("GET", "http://media.tuhh.de/ibi/mdfv2/measurement_V2.mdf") do http
    open(filenameMeas, "w") do file
        write(file, http)
    end
  end
end

b = MPIFile("measurement.mdf")
bSF = MPIFile("systemMatrix.mdf")

onlineReco(bSF, b, minFreq=80e3,  lambd=1e-2, iterations=20, SNRThresh=2.0, sparseTrafo=nothing,startFrame=1,skipFrames=100,numAverages=100, spectralLeakageCorrection=true)



