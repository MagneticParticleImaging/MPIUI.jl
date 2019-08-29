using MPIUI

b = MPIFile("/home/knopp/.julia/dev/MPIReco/test/measurement.mdf")
bSF = MPIFile("/home/knopp/.julia/dev/MPIReco/test/systemMatrix.mdf")

onlineReco(bSF, b, minFreq=80e3,  lambd=1e-2, iterations=20, SNRThresh=2.0, sparseTrafo=nothing,startFrame=1,skipFrames=100,numAverages=100, spectralLeakageCorrection=true)



