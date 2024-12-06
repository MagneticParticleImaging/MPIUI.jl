"""
    prepareTimeDataForPlotting(data::AbstractMatrix, times = 1:length(data); timeInterval = nothing, maxpoints = length(data), reduceOp = nothing)

Reduces time-series `data` to at most `maxpoints` by either resampling or reducing the data with `reduceOp`. The time-series is defined by `times` and `timeInterval`.
If `timeInterval` is not given, the whole time-series is used. If `reduceOp` is not given, the data is resampled. 
The function returns the reduced time-series `t` and the reduced data `d`.
"""
function prepareTimeDataForPlotting(data::AbstractMatrix, times = 1:length(data); indexInterval = nothing, timeInterval = nothing, maxpoints = length(data), reduceOp = nothing)
  idx1, idx2 = timeSlice(times, indexInterval, timeInterval)
  if length(idx1:idx2) > maxpoints
    t, d = reducePoints(reduceOp, data, times, idx1, idx2, maxpoints)
  else
    t = times[idx1:idx2]
    d = data[idx1:idx2, :]
  end
  return t, d
end
# Main variant is defined for matrices, so we reshape into Nx1 matrix
function prepareTimeDataForPlotting(data::AbstractVector, args...; kwargs...) 
  t, d = prepareTimeDataForPlotting(reshape(data, :, 1), args...; kwargs...)
  return t, vec(d)
end

timeSlice(times, indexInterval, timeInterval) = error("Cannot specify both indexInterval and timeInterval")
timeSlice(times, indexInterval, ::Nothing) = first(indexInterval), last(indexInterval)
function timeSlice(times, ::Nothing, timeInterval)
  t1, t2 = timeInterval
  idx1 = findfirst(t -> (t>t1), times)
  idx2 = findlast(t -> (t<t2), times)
  idx1 = (idx1 == nothing) ? 1 : idx1 
  idx2 = (idx2 == nothing) ? length(times) : idx2
  idx1 = min(max(1,idx1),length(times))
  idx2 = min(max(1,idx2),length(times))
  return idx1, idx2
end
timeSlice(times, ::Nothing) = 1, length(times)

function reducePoints(reduceOp, data, times, idx1, idx2, maxpoints)
  stepsize = round(Int, (length(idx1:idx2)) / maxpoints, RoundUp)
  steps = idx1:stepsize:idx2
  # Sample time
  t = range(times[idx1], times[idx2], length=length(steps))
  # Sample data with reduceOp
  d = zeros(eltype(data), length(t), size(data, 2))
  # Zip generates start and end indices for each step
  for (i, (st, en)) in enumerate(zip(steps, map(i -> min(i + stepsize -1, idx2), steps)))
    d[i, :] = reduceOp(@view data[st:en, :])
    #@info "Reducing data from $st to $en with $(d[i, :])"
  end
  return t, d
end
function reducePoints(::Nothing, data, times, idx1, idx2, maxpoints)
  d = DSP.resample(data[idx1:idx2], maxpoints / length(idx1:idx2))
  t = range(times[idx1], times[idx2], length=length(d))
  return t, d
end

include("BaseViewer.jl")
include("SimpleDataViewer.jl")
include("DataViewer/DataViewer.jl")
include("RawDataViewer.jl")
include("SpectrogramViewer.jl")
include("SFViewerWidget.jl")
include("MagneticFieldViewer/MagneticFieldViewer.jl")
