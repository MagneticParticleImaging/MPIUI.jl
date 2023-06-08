###############################
## Utils for Magnetic Fields ##
###############################

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
    for c in axes(expansion,2)

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
