###############################
## Utils for Magnetic Fields ##
###############################
winstonColormaps = ["Blues","Greens","Grays","Oranges","Purples","Reds","RdBu","jet"];

# Coefficients of the magnetic field with more information than SphericalHarmonicCoefficients
mutable struct MagneticFieldCoefficients
  coeffs::Array{SphericalHarmonicCoefficients}
  radius::Float64
  center::Vector{Float64}
  ffp::Union{Array{Float64},Nothing}

  function MagneticFieldCoefficients(L::Int)
    if L<0
      throw(DomainError(L,"Input vector needs to be of size (L+1)², where L ∈ ℕ₀."))
    end
    return new([SphericalHarmonicCoefficients(L)], 0.0, [0.0,0.0,0.0], nothing)
  end

  # write and read coefficients to/from an HDF5-file
  function MagneticFieldCoefficients(path::String)
    file = h5open(path,"r")

    if haskey(HDF5.root(file), "/radius") 
      # file contains all relevant information
      radius = read(file, "/radius")
      center = read(file, "/center")
      ffp = read(file, "/ffp")
    else
      # convert file of SphericalHarmonicCoefficients into MagneticFieldCoefficients
      radius = 0.042
      center = [0.0,0.0,0.0]
      ffp = nothing
    end

    shcoeffs = SphericalHarmonicCoefficients(path) # get SHC

    return new(shcoeffs, radius, center, ffp)
  end
end

# write coefficients to an HDF5-file
function write(path::String, coeffs::MagneticFieldCoefficients)

  if size(coeffs.coeffs) != (1,)
      coeffsArray = coeffs.coeffs[1].c'
      for (n,co) in enumerate(coeffs.coeffs[2:end])
          coeffsArray = vcat(coeffsArray,co.c')
      end
      coeffsArray = reshape(coeffsArray,(size(coeffs.coeffs)...,(coeffs.coeffs[1].L+1)^2))
  else
      coeffsArray = coeffs.coeffs[1].c
  end

  R = Array{Float64}(undef,size(coeffs.coeffs))
  solid = Array{Int}(undef,size(coeffs.coeffs))
  for (n,co) in enumerate(coeffs)
      R[n] = co.R
      solid[n] = co.solid ? 1 : 0
  end

  radius = coeffs.radius
  center = coeffs.center
  ffp = coeffs.ffp

  h5open(path,"w") do file
      write(file, "/coeffs", coeffsArray)
      write(file, "/normalization", R)
      write(file, "/solid", solid)
      write(file, "/radius", radius)
      write(file, "/center", center)
      write(file, "/ffp", ffp)
  end
end


