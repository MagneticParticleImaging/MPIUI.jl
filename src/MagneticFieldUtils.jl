###############################
## Utils for Magnetic Fields ##
###############################
import Base.write

# Coefficients of the magnetic field with more information than SphericalHarmonicCoefficients
mutable struct MagneticFieldCoefficients
  coeffs::Array{SphericalHarmonicCoefficients,2}
  radius::Float64
  center::Vector{Float64}
  ffp::Union{Array{Float64,2},Nothing}

  function MagneticFieldCoefficients(coeffs::Array{SphericalHarmonicCoefficients,2}, radius::Float64,
  				     center::Vector{Float64}, ffp::Union{Array{Float64,2},Nothing})
    # test sizes of the arrays
    if size(coeffs,1) != 3
      throw(DimensionMismatch("The coefficient matrix needs 3 entries (x,y,z) in the first dimension, not $(size(coeffs,1))"))
    elseif ffp != nothing
      if size(ffp,1) != 3
        throw(DimensionMismatch("The FFP matrix needs 3 entries (x,y,z) in the first dimension, not $(size(coeffs,1))"))
      elseif size(coeffs,2) != size(ffp,2)
        throw(DimensionMismatch("The number of patches of the coefficients and FFPs does not match: $(size(coeffs,2)) != $(size(ffp,2))"))
      end
    end

    return new(coeffs,radius,center,ffp)
  end

end

# some other constructors
MagneticFieldCoefficients(coeffs::Array{SphericalHarmonicCoefficients,2}) = MagneticFieldCoefficients(coeffs, 0.0)
MagneticFieldCoefficients(coeffs::Array{SphericalHarmonicCoefficients,2}) = MagneticFieldCoefficients(coeffs, 0.0)
MagneticFieldCoefficients(coeffs::Array{SphericalHarmonicCoefficients,2}, radius::Float64) = MagneticFieldCoefficients(coeffs,radius,[0.0,0.0,0.0])
MagneticFieldCoefficients(coeffs::Array{SphericalHarmonicCoefficients,2}, radius::Float64, center::Vector{Float64}) = MagneticFieldCoefficients(coeffs,radius,center,nothing)
MagneticFieldCoefficients(coeffs::Array{SphericalHarmonicCoefficients,2}, radius::Float64, ffp::Array{Float64,2}) = MagneticFieldCoefficients(coeffs,radius,[0.0,0.0,0.0],ffp)

function MagneticFieldCoefficients(L::Int)
  if L<0
    throw(DomainError(L,"Input vector needs to be of size (L+1)², where L ∈ ℕ₀."))
  end
  return MagneticFieldCoefficients(reshape([SphericalHarmonicCoefficients(L),SphericalHarmonicCoefficients(L),SphericalHarmonicCoefficients(L)],3,1))
end
  
# read coefficients from an HDF5-file
function MagneticFieldCoefficients(path::String)
  file = h5open(path,"r")

  # load spherical harmonic coefficients
  shcoeffs = SphericalHarmonicCoefficients(path)

  if haskey(HDF5.root(file), "/radius") 
    # file contains all relevant information
    radius = read(file, "/radius")
    center = read(file, "/center")
    if haskey(HDF5.root(file), "/ffp")
      ffp = read(file, "/ffp")
      return MagneticFieldCoefficients(shcoeffs, radius, center, ffp)
    else
      # field has not FFP -> ffp = nothing
      return MagneticFieldCoefficients(shcoeffs, radius, center)
    end
  else
    # convert file of SphericalHarmonicCoefficients into MagneticFieldCoefficients
    # -> set all additional informations to 0 or nothing
    return MagneticFieldCoefficients(shcoeffs)
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
  for (n,co) in enumerate(coeffs.coeffs)
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

winstonColormaps = ["Blues","Greens","Grays","Oranges","Purples","Reds","RdBu","jet"];
