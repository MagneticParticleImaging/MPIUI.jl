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
    # use radius = 0.042 as default value
    return MagneticFieldCoefficients(shcoeffs, 0.042)
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

  h5open(path,"cw") do file
      write(file, "/coeffs", coeffsArray)
      write(file, "/normalization", R)
      write(file, "/solid", solid)
      write(file, "/radius", radius)
      write(file, "/center", center)
      # write(file, "/coeffs/ffp", ffp)
  end
end


"""
   magneticField(tDesign::SphericalTDesign, field::Union{AbstractArray{T,2},AbstractArray{T,3}}, 
		       x::Variable, y::Variable, z::Variable;
		       L::Int=Int(tDesign.T/2),
		       calcSolid::Bool=true) where T <: Real
*Description:*  Calculation of the spherical harmonic coefficients and expansion based on the measured t-design\\
 \\
*Input:*
- `tDesign`	- Measured t-design (type: SphericalTDesign)
- `field`       - Measured field (size = (J,N,C)) with J <= 3
- `x, y, z`     - Cartesian coordinates
**kwargs:**
- `L`           - Order up to which the coeffs be calculated (default: t/2)
- `calcSolid`   - Boolean (default: true)\\
    false -> spherical coefficients\\
    true -> solid coefficients

*Output:*
- `coeffs`    - spherical/solid coefficients, type: Array{SphericalHarmonicCoefficients}(3,C)
- `expansion` - related expansion (Cartesian polynomial), type: Array{AbstractPolynomialLike}(3,C)
- `func`      - expansion converted to a function, type: Array{Function}(3,C)
"""
function magneticField(tDesign::SphericalTDesign, field::Union{AbstractArray{T,2},AbstractArray{T,3}}, 
		       x::Variable, y::Variable, z::Variable;
		       L::Int=Int(floor(tDesign.T/2)),
		       calcSolid::Bool=true) where T <: Real

  # get tDesign positions [m] and removing the unit
  # coordinates
  coords = Float64.(ustrip.(Unitful.m.(hcat([p for p in tDesign]...))))

  # radius
  R = Float64(ustrip(Unitful.m(tDesign.radius)))

  # center
  center = Float64.(ustrip.(Unitful.m.(tDesign.center)))
  
  return magneticField(coords, field, 
		       R, center, L,
		       x, y, z,
		       calcSolid)
end
  


function magneticField(coords::AbstractArray{T,2}, field::Union{AbstractArray{T,2},AbstractArray{T,3}}, 
		       R::T, center::Vector{T}, L::Int,
		       x::Variable, y::Variable, z::Variable, 
		       calcSolid::Bool=true) where T <: Real

  # transpose coords if its dimensions do not fit
  if size(coords,1) != 3
    coords = coords'
  end

  # test dimensions of field array
  if size(field,1) > 3
    throw(DimensionMismatch("The measured field has more than 3 entries in the first dimension: $(size(field,1))"))
  elseif size(field,2) != size(coords,2)
    throw(DimensionMismatch("The field vector does not match the size of the tdesign: $(size(field,2)) != $(size(coords,2))"))
  end

  func= Array{Function}(undef,size(field,1),size(field,3))
  expansion = Array{Polynomial}(undef,size(field,1),size(field,3))
  coeffs = Array{SphericalHarmonicCoefficients}(undef,size(field,1),size(field,3))

  # rescale coordinates to t-design on unit sphere
  coords = coords .- center
  coords *= 1/R
  for c = 1:size(field,3)
    # calculation of the coefficients
    for j = 1:size(field,1)

        coeffs[j,c] = SphericalHarmonicExpansions.sphericalQuadrature(field[j,:,c],coords',L);
        coeffs[j,c].R = R

        normalize!(coeffs[j,c],R)

	# convert spherical into solid coefficients
        if calcSolid
            solid!(coeffs[j,c])
        end

        # calculation of the expansion
        expansion[j,c] = sphericalHarmonicsExpansion(coeffs[j,c],x,y,z) + 0*x;
        func[j,c] = @fastfunc expansion[j,c]+0*x+0*y+0*z
    end
  end

  return coeffs, expansion, func
end

# calculate the FFP for a given expansion
"""
    ffp = findFFP(expansion::AbstractArray{T}, 
    x::Variable, y::Variable, z::Variable; 
    returnasmatrix::Bool=true) where T <: Polynomial
*Description:*  Newton method to find the FFPs of the expansions of the magnetic fields\\
 \\
*Input:*
- `expansion`   - expansions of the magnetic fields (size = (3,N))
- `x,y,z`       - Cartesian coordinates
**kwargs:**
- `returnasmatrix` - Boolean\\
        true  -> return FFPs as Matrix with size (3,N) (default)\\
        false -> return FFPs as Array of NLsolve.SolverResults with size N
*Output:*
- `ffp` - FFPs of the expansion
"""
function findFFP(expansion::AbstractArray{T}, 
                 x::Variable, y::Variable, z::Variable; 
                 returnasmatrix::Bool=true) where T <: Polynomial

    size(expansion,1) == 3 || throw(DimensionMismatch("Size of expansion needs to be (3,N) but it is $(size(expansion))."))
    ndims(expansion) <= 2 || throw(DimensionMismatch("Dimension of expansion needs to be ≦ 2 but it is $(ndims(expansion))."))

    # return all FFPs in a matrix or as array with the solver results
    ffp = returnasmatrix ? zeros(size(expansion)) : Array{NLsolve.SolverResults{Float64}}(undef,size(expansion,2))
    for c=1:size(expansion,2)

        px = expansion[1,c]
        py = expansion[2,c]
        pz = expansion[3,c]
        dpx = differentiate.(px,(x,y,z))
        dpy = differentiate.(py,(x,y,z))
        dpz = differentiate.(pz,(x,y,z))

        function f!(fvec, xx)
            fvec[1] = px((x,y,z)=>(xx[1],xx[2],xx[3]))
            fvec[2] = py((x,y,z)=>(xx[1],xx[2],xx[3]))
            fvec[3] = pz((x,y,z)=>(xx[1],xx[2],xx[3]))
        end

        function g!(fjac, xx)
            fjac[1,1] = dpx[1]((x,y,z)=>(xx[1],xx[2],xx[3]))
            fjac[1,2] = dpx[2]((x,y,z)=>(xx[1],xx[2],xx[3]))
            fjac[1,3] = dpx[3]((x,y,z)=>(xx[1],xx[2],xx[3]))
            fjac[2,1] = dpy[1]((x,y,z)=>(xx[1],xx[2],xx[3]))
            fjac[2,2] = dpy[2]((x,y,z)=>(xx[1],xx[2],xx[3]))
            fjac[2,3] = dpy[3]((x,y,z)=>(xx[1],xx[2],xx[3]))
            fjac[3,1] = dpz[1]((x,y,z)=>(xx[1],xx[2],xx[3]))
            fjac[3,2] = dpz[2]((x,y,z)=>(xx[1],xx[2],xx[3]))
            fjac[3,3] = dpz[3]((x,y,z)=>(xx[1],xx[2],xx[3]))
        end

        if returnasmatrix
            ffp[:,c] = nlsolve(f!,g!,[0.0;0.0;0.0],method=:newton,ftol=1e-16).zero
        else
            ffp[c] = nlsolve(f!,g!,[0.0;0.0;0.0],method=:newton,ftol=1e-16);
        end
    end

    return ffp
end

winstonColormaps = ["Blues","Greens","Grays","Oranges","Purples","Reds","RdBu","jet"];
