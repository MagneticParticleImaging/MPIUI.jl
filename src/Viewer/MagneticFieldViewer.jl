export MagneticFieldViewer

# load new type MagneticFieldCoefficients with additional informations
include("../MagneticFieldUtils.jl")

mutable struct FieldViewerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  coloring::ColoringParams
  updating::Bool
  field # data to be plotted
  centerFFP::Bool # center of plot (FFP (true) or center of measured sphere (false))
  grid::GtkGridLeaf
end

mutable struct MagneticFieldViewerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  fv::FieldViewerWidget
  updating::Bool
  coeffs::MagneticFieldCoefficients 
  coeffsPlot::Array{SphericalHarmonicCoefficients}
  field # Array containing Functions of the field
  patch::Int
  grid::GtkGridLeaf
end

getindex(m::MagneticFieldViewerWidget, w::AbstractString) = G_.object(m.builder, w)
getindex(m::FieldViewerWidget, w::AbstractString) = G_.object(m.builder, w)

mutable struct MagneticFieldViewer
  w::Window
  mf::MagneticFieldViewerWidget
end

function MagneticFieldViewer(filename::AbstractString)
  mfViewerWidget = MagneticFieldViewerWidget()
  w = Window("Magnetic Field Viewer: $(filename)",800,600)
  push!(w,mfViewerWidget)
  showall(w)
  updateData!(mfViewerWidget, filename)
  return MagneticFieldViewer(w, mfViewerWidget)
end

function MagneticFieldViewerWidget()
  uifile = joinpath(@__DIR__,"..","builder","magneticFieldViewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxMagneticFieldViewer")

  m = MagneticFieldViewerWidget(mainBox.handle, b, FieldViewerWidget(),
                     false, MagneticFieldCoefficients(0), [SphericalHarmonicCoefficients(0)],
		     nothing, 1,
                     Grid())
  Gtk.gobject_move_ref(m, mainBox)

  # build up plots
  m.grid = m["gridMagneticFieldViewer"]
  m.grid[1,1:2] = m.fv
  m.grid[1,3] = Canvas()
  # expand plot
  set_gtk_property!(m, :expand, m.grid, true)

  showall(m)

  # set colormaps
  choices = important_cmaps() 
  for c in choices
    push!(m["cbCMaps"], c)
  end
  set_gtk_property!(m["cbCMaps"],:active,5) # default: viridis

  # change discretization
  signal_connect(m["adjDiscretization"], "value_changed") do w
    @idle_add_guarded updateField(m)
  end
  
  # change patch
  signal_connect(m["adjPatches"], "value_changed") do w
    @idle_add_guarded updateField(m)
    @idle_add_guarded updateCoeffsPlot(m)
  end
 
  # change length of arrows
  signal_connect(m["adjArrowLength"], "value_changed") do w
    @idle_add_guarded updateField(m, true)
  end 
 
  # update coeffs plot
  widgets = ["adjL", "adjBarWidth"]
  for ws in widgets 
    signal_connect(m[ws], "value_changed") do w
      @idle_add_guarded updateCoeffsPlot(m)
    end
  end

  # update plot (clicked button)
  signal_connect(m["btnUpdate"], "clicked") do w
    @idle_add_guarded updateIntersection(m)
    @idle_add_guarded updateCoeffsPlot(m)
    @idle_add_guarded updateField(m)
  end

  # update magnetic field plot: 
  # center = center of sphere
  signal_connect(m["btnCenterSphere"], "clicked") do w
    if m.fv.centerFFP
      m.fv.centerFFP = false
      @idle_add_guarded calcCenterCoeffs(m,true)
      @idle_add_guarded updateCoeffsPlot(m)
      @idle_add_guarded updateField(m)
    end
  end
  # center = FFP
  signal_connect(m["btnCenterFFP"], "clicked") do w
    if !(m.fv.centerFFP)
      m.fv.centerFFP = true
      @idle_add_guarded calcCenterCoeffs(m,true)
      @idle_add_guarded updateCoeffsPlot(m)
      @idle_add_guarded updateField(m)
    end
  end

  # go to FFP
  signal_connect(m["btnGoToFFP"], "clicked") do w
    @idle_add_guarded goToFFP(m)
  end
  # go to zero
  signal_connect(m["btnGoToZero"], "clicked") do w
    @idle_add_guarded goToFFP(m,true)
  end

  # change slice
  for slice in ["adjSliceX", "adjSliceY", "adjSliceZ"]
    signal_connect(m[slice], "value_changed") do w
      @idle_add_guarded newSlice(m)
    end
  end

  initCallbacks(m)

  return m
end

function FieldViewerWidget()
  uifile = joinpath(@__DIR__,"..","builder","magneticFieldViewer.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxFieldViewer")

  fv = FieldViewerWidget(mainBox.handle, b, ColoringParams(0,0,0),
                     false, nothing, true,
                      G_.object(b, "gridFieldViewer"),)
  Gtk.gobject_move_ref(fv, mainBox)

  # initialize plots
  fv.grid[1,1] = Canvas()
  fv.grid[1,2] = Canvas()
  fv.grid[2,1] = Canvas()
  fv.grid[2,2] = Canvas()
  # expand plots
  set_gtk_property!(fv, :expand, fv.grid, true)

  return fv
end

function initCallbacks(m_::MagneticFieldViewerWidget)
  let m=m_

  ## update coloring
  function updateCol( widget )
    updateColoring(m)
    updateField(m,true)
  end

  # cmin/cmax
  widgets = ["adjCMin", "adjCMax"]
  for w in widgets
    signal_connect(updateCol, m[w], "value_changed")
  end

  # colormap
  signal_connect(updateCol, m["cbCMaps"], "changed")

  ## reset FOV
  function resetFOV( widget )
    R = m.coeffs.radius # radius  
    set_gtk_property!(m["entFOV"], :text, "$(R*2000) x $(R*2000) x $(R*2000)") # initial FOV
    updateField(m)
  end
  signal_connect(resetFOV, m["btnResetFOV"], "clicked")

  end
end

# load all necessary data and set up the values in the GUI
function updateData!(m::MagneticFieldViewerWidget, filenameCoeffs::String)
  # load magnetic fields
  m.coeffs = MagneticFieldCoefficients(filenameCoeffs) # load coefficients
  m.coeffsPlot = SphericalHarmonicCoefficients(filenameCoeffs) # load coefficients
  @polyvar x y z
  expansion = sphericalHarmonicsExpansion.(m.coeffs.coeffs,[x],[y],[z])
  m.field = fastfunc.(expansion)
  R = m.coeffs.radius # radius
  m.fv.centerFFP = (m.coeffs.ffp != nothing) ?  true : false # if FFP is given, it is the plotting center
 
  # set some values
  set_gtk_property!(m["adjPatches"], :upper, size(m.coeffs.coeffs,2) )
  set_gtk_property!(m["adjL"], :upper, m.coeffs.coeffs[1,1].L )
  set_gtk_property!(m["adjL"], :value, m.coeffs.coeffs[1,1].L )
  set_gtk_property!(m["entRadius"], :text, "$(R*1000)") # show radius of measurement 
  set_gtk_property!(m["entFOV"], :text, "$(R*2000) x $(R*2000) x $(R*2000)") # initial FOV
  set_gtk_property!(m["entInters"], :text, "0.0 x 0.0 x 0.0") # initial FOV
  d = get_gtk_property(m["adjDiscretization"],:value, Int64) # get discretization as min/max for slices
  for w in ["adjSliceX", "adjSliceY", "adjSliceZ"]
    set_gtk_property!(m[w], :lower, -d)
    set_gtk_property!(m[w], :value, 0)
    set_gtk_property!(m[w], :upper, d)
  end


  m.updating = true

  updateField(m)
  updateCoeffsPlot(m)
  showall(m)
  
  m.updating = false
end

# update the coloring params
function updateColoring(m::MagneticFieldViewerWidget)
  cmin = get_gtk_property(m["adjCMin"],:value, Float64)
  cmax = get_gtk_property(m["adjCMax"],:value, Float64)
  cmap = important_cmaps()[get_gtk_property(m["cbCMaps"],:active, Int64)+1]
  m.fv.coloring = ColoringParams(cmin,cmax,cmap)
end

# choose new slice
function newSlice(m::MagneticFieldViewerWidget)
  # get chosen slices
  sl = [get_gtk_property(m[w],:value, Int64) for w in ["adjSliceX", "adjSliceY", "adjSliceZ"]]

  # get current FOV
  fovString = get_gtk_property(m["entFOV"], :text, String) # FOV
  fov = tryparse.(Float64,split(fovString,"x")) ./ 1000

  # calculate voxel size
  discretization = Int(get_gtk_property(m["adjDiscretization"],:value, Int64)*2+1) # odd number of voxel 
  voxel = fov ./ discretization

  # calculate new intersection
  intersection = voxel .* sl

  # set intersection
  interString = round.(intersection .* 1000, digits=1)
  set_gtk_property!(m["entInters"], :text, 
		"$(interString[1]) x $(interString[2]) x $(interString[3])") 

  # update coefficients with new intersection and plot everything
  updateIntersection(m)
  updateCoeffsPlot(m)
  updateField(m)
end

# update slices
function updateSlices(m::MagneticFieldViewerWidget)
  # get current intersection
  intersString = get_gtk_property(m["entInters"], :text, String) # intersection
  intersection = tryparse.(Float64,split(intersString,"x")) ./ 1000 # conversion from mm to m

  # get voxel size
  fovString = get_gtk_property(m["entFOV"], :text, String) # FOV
  fov = tryparse.(Float64,split(fovString,"x")) ./ 1000
  discretization = Int(get_gtk_property(m["adjDiscretization"],:value, Int64)*2+1) # odd number of voxel 
  voxel = fov ./ discretization

  # get slice numbers (rounded)
  sl = round.(Int,intersection ./ voxel)

  # set slice
  for (i,w) in enumerate(["adjSliceX", "adjSliceY", "adjSliceZ"])
    set_gtk_property!(m[w], :value, sl[i])
  end
  
end

# update intersection
function updateIntersection(m::MagneticFieldViewerWidget)
  # get intersection (= new expansion point of coefficients)
  intersString = get_gtk_property(m["entInters"], :text, String) # intersection
  intersection = tryparse.(Float64,split(intersString,"x")) ./ 1000 # conversion from mm to m
  
  updateSlices(m) # update slice numbers
  calcCenterCoeffs(m) # recalculate coefficients regarding to the center
  updateCoeffs(m, -intersection) # shift to intersection
end

function goToFFP(m::MagneticFieldViewerWidget, goToZero=false)
  if m.coeffs.ffp == nothing && !goToZero
    # no FFP given
    return nothing
  end

  # set new intersection
  intersection = (goToZero || m.fv.centerFFP) ? [0.0,0.0,0.0] : m.coeffs.ffp[:,m.patch]
  interString = round.(intersection .* 1000, digits=1)
  set_gtk_property!(m["entInters"], :text, 
		"$(interString[1]) x $(interString[2]) x $(interString[3])") 

  updateSlices(m) # update slice numbers
  calcCenterCoeffs(m) # recalculate coefficients regarding to the center
  updateCoeffs(m, intersection)
  updateCoeffsPlot(m)
  updateField(m)
end

# update coefficients
function updateCoeffs(m::MagneticFieldViewerWidget, shift)

  # translate coefficients
  if size(shift) != size(m.coeffs.coeffs)
    m.coeffsPlot = SphericalHarmonicExpansions.translation.(m.coeffsPlot,[shift])
  else
    for p = 1:size(m.coeffs.coeffs,2)
      m.coeffsPlot[:,p] = SphericalHarmonicExpansions.translation.(m.coeffsPlot[:,p],[shift[:,p]])
    end
  end

end

# move coefficients
function calcCenterCoeffs(m::MagneticFieldViewerWidget,resetIntersection=false)
  
  # reset intersection
  if resetIntersection
    intersection = [0.0,0.0,0.0]
    set_gtk_property!(m["entInters"], :text, 
		"$(intersection[1]*1000) x $(intersection[2]*1000) x $(intersection[3]*1000)") 
  end

  if m.fv.centerFFP || m.coeffs.ffp == nothing
    # just reset coeffs to initial coeffs
    # assumption: initial coeffs are given in the FFP
    m.coeffsPlot = deepcopy(m.coeffs.coeffs)
    
  else
    # translate coefficients from FFP to center of measured sphere
    for p = 1:size(m.coeffs.coeffs,2)
      m.coeffsPlot[:,p] = SphericalHarmonicExpansions.translation.(m.coeffs.coeffs[:,p],[-m.coeffs.ffp[:,p]])
    end
    
  end

  # update field
  @polyvar x y z
  expansion = sphericalHarmonicsExpansion.(m.coeffsPlot,[x],[y],[z])
  m.field = fastfunc.(expansion)
end

# plotting the magnetic field
function updateField(m::MagneticFieldViewerWidget, updateColoring=false)
  discretization = Int(get_gtk_property(m["adjDiscretization"],:value, Int64)*2+1) # odd number of voxel
  R = m.coeffs.radius # radius of measurement data
  center = m.coeffs.center # center of measurement data
  m.patch = get_gtk_property(m["adjPatches"],:value, Int64) # patch
  # ffp = (m.coeffs.ffp == nothing) ? [0.0,0.0,0.0] : m.coeffs.ffp[:,m.patch] # not necessary
  # get current intersection
  intersString = get_gtk_property(m["entInters"], :text, String) # intersection
  intersection = tryparse.(Float64,split(intersString,"x")) ./ 1000 # conversion from mm to m

  # get FOV
  fovString = get_gtk_property(m["entFOV"], :text, String) # FOV
  fov = tryparse.(Float64,split(fovString,"x")) ./ 1000
  intersString = get_gtk_property(m["entInters"], :text, String) # intersection
  intersection = tryparse.(Float64,split(intersString,"x")) ./ 1000

  # Grid
  N = [range(-fov[i]/2-center[i],stop=fov[i]/2-center[i],length=discretization) for i=1:3];

  # calculate field for plot 
  fieldNorm = zeros(discretization,discretization,3);
  fieldxyz = zeros(3,discretization,discretization,3);
  for i = 1:discretization
    for j = 1:discretization
      fieldxyz[:,i,j,1] = [m.field[d,m.patch]([intersection[1],N[2][i],N[3][j]]) for d=1:3]
      fieldNorm[i,j,1] = norm(fieldxyz[:,i,j,1])
      fieldxyz[:,i,j,2] = [m.field[d,m.patch]([N[1][i],intersection[2],N[3][j]]) for d=1:3]
      fieldNorm[i,j,2] = norm(fieldxyz[:,i,j,2])
      fieldxyz[:,i,j,3] = [m.field[d,m.patch]([N[1][i],N[2][j],intersection[3]]) for d=1:3]
      fieldNorm[i,j,3] = norm(fieldxyz[:,i,j,3])
    end
  end

  # coloring params
  if updateColoring
    # use params from GUI
    cmin = m.fv.coloring.cmin
    cmax = m.fv.coloring.cmax
    cmap = m.fv.coloring.cmap
    # set new min/max values
      set_gtk_property!(m["adjCMin"], :upper, 0.99*cmax) # prevent cmin=cmax
      set_gtk_property!(m["adjCMax"], :lower, 1.01*cmin) # prevent cmin=cmax
  else
    # set new coloring params
    cmin, cmax = minimum(fieldNorm), maximum(fieldNorm)
    cmap = important_cmaps()[get_gtk_property(m["cbCMaps"],:active, Int64)+1]
    m.fv.coloring = ColoringParams(cmin, cmax, cmap) # set coloring
    # set cmin and cmax
      set_gtk_property!(m["adjCMin"], :lower, cmin)
      set_gtk_property!(m["adjCMin"], :upper, 0.99*cmax) # prevent cmin=cmax
      set_gtk_property!(m["adjCMax"], :lower, 1.01*cmin) # prevent cmin=cmax
      set_gtk_property!(m["adjCMax"], :upper, cmax)
      @idle_add_guarded set_gtk_property!(m["adjCMin"], :value, cmin)
      @idle_add_guarded set_gtk_property!(m["adjCMax"], :value, cmax)
  end
  Winston.colormap(RGB.(ImageUtils.cmap(cmap))) # set colormap
 
  # plots
  plYZ = Winston.imagesc((N[2][1],N[2][end]),(N[3][end],N[3][1]),fieldNorm[:,:,1]',(cmin,cmax))
  xlabel("y / m"), ylabel("z / m")
  plXZ = Winston.imagesc((N[1][end],N[1][1]),(N[3][end],N[3][1]),fieldNorm[:,:,2]',(cmin,cmax))
  xlabel("x / m"), ylabel("z / m")
  plXY = Winston.imagesc((N[1][1],N[1][end]),(N[2][1],N[2][end]),fieldNorm[:,:,3],(cmin,cmax))
  xlabel("y / m"), ylabel("x / m")

  ## arrows ##
  discr = floor(Int,0.1*discretization) # reduce number of arrows
  ## positioning
  NN = [N[i][1:discr:end] for i=1:3]
  x = repeat(NN[1],1,length(NN[1])) #repeat(range(1,15,length=15),1,15);
  y1 = repeat(transpose(NN[2]),length(NN[2]),1) #repeat(transpose(range(1,15,length=15)),15,1);
  y2 = repeat(NN[2],1,length(NN[2])) #repeat(transpose(range(1,15,length=15)),15,1);
  z = repeat(transpose(NN[3]),length(NN[3]),1) #repeat(transpose(range(1,15,length=15)),15,1);
  ## direction (angle to x-axis with atan2(y,x))
  # vectors (arrows) (adapted to chosen coordinate orientations)
  arYZ = [[fieldxyz[2,i,j,1],fieldxyz[3,i,j,1]] for i=1:discr:discretization, j=1:discr:discretization]
  arXZ = [[fieldxyz[1,i,j,2],fieldxyz[3,i,j,2]] for i=discretization:-discr:1, j=1:discr:discretization]
  arXY = [[fieldxyz[2,i,j,3],fieldxyz[1,i,j,3]] for i=discretization:-discr:1, j=1:discr:discretization]
  #arXY = [[fieldxyz[1,i,j,3],-fieldxyz[2,i,j,3]] for i=1:discr:discretization, j=1:discr:discretization]
  # angle
  dirYZ = [atan(ar[2],ar[1]) for ar in arYZ]  
  dirXZ = [atan(ar[2],ar[1]) for ar in arXZ]  
  dirXY = [atan(ar[2],ar[1]) for ar in arXY]
  # length
  lenYZ = norm.(arYZ)  
  lenXZ = norm.(arXZ)  
  lenXY = norm.(arXY)
  # adapt length so that the maximum is equal to the chosen al:
  al = get_gtk_property(m["adjArrowLength"],:value, Float64) # adapt length of the arrows
  maxlen = maximum(vcat(lenYZ, lenXZ, lenXY))
  lenYZ .*= al/maxlen
  lenXZ .*= al/maxlen
  lenXY .*= al/maxlen
  
  # add arrows to plots
  Winston.add( plYZ, Winston.Arrows(y2, z , dirYZ, lenYZ*al, 
              linewidth=3.0, color="white") )
  Winston.add( plXZ, Winston.Arrows(x, z, dirXZ, lenXZ*al, 
              linewidth=3.0, color="white") )
  Winston.add( plXY, Winston.Arrows(x, y1, dirXY, lenXY*al, 
              linewidth=3.0, color="white") )

  # remove label and ticks
  #for pl in [plYZ, plXZ, plXY]
  #  Winston.setattr(pl.x, draw_ticks=false, ticklabels=[])
  #  Winston.setattr(pl.y, draw_ticks=false, ticklabels=[])
  #end

  # Show slices
  if get_gtk_property(m["cbShowSlices"], :active, Bool)
    # YZ
    s1 = MPIUI.Winston.Slope(0, Tuple(intersection[2:3]), kind="dotted", color="white")
    s2 = MPIUI.Winston.Slope(Inf, Tuple(intersection[2:3]), kind="dotted", color="white")
    Winston.add(plYZ, s1, s2)
    # XZ
    s1 = MPIUI.Winston.Slope(0, Tuple(intersection[[1,3]]), kind="dotted", color="white")
    s2 = MPIUI.Winston.Slope(Inf, Tuple(intersection[[1,3]]), kind="dotted", color="white")
    Winston.add(plXZ, s1, s2)
    # XY
    s1 = MPIUI.Winston.Slope(0, Tuple(intersection[[2,1]]), kind="dotted", color="white")
    s2 = MPIUI.Winston.Slope(Inf, Tuple(intersection[[2,1]]), kind="dotted", color="white")
    Winston.add(plXY, s1, s2)
  end

  # show sphere
  if get_gtk_property(m["cbShowSphere"], :active, Bool)
    # sphere
    ϕ=range(0,stop=2*pi,length=100)
    rr = zeros(100,2)
    for i=1:100
      rr[i,1] = R*sin(ϕ[i]);
      rr[i,2] = R*cos(ϕ[i]);
    end

    # shift sphere to plotting center
    if m.fv.centerFFP && m.coeffs.ffp != nothing
      spYZ = MPIUI.Winston.Curve(rr[:,1].-m.coeffs.ffp[2,m.patch], rr[:,2].-m.coeffs.ffp[3,m.patch], 
				kind="dash", color="white")
      spXZ = MPIUI.Winston.Curve(rr[:,1].-m.coeffs.ffp[1,m.patch], rr[:,2].-m.coeffs.ffp[3,m.patch], 
				kind="dash", color="white")
      spXY = MPIUI.Winston.Curve(rr[:,1].-m.coeffs.ffp[2,m.patch], rr[:,2].-m.coeffs.ffp[1,m.patch], 
				kind="dash", color="white")
    else
      spYZ = MPIUI.Winston.Curve(rr[:,1], rr[:,2], kind="dash", color="white")
      spXZ = MPIUI.Winston.Curve(rr[:,1], rr[:,2], kind="dash", color="white")
      spXY = MPIUI.Winston.Curve(rr[:,1], rr[:,2], kind="dash", color="white")
    end

    # add to plots
    for (pl,sp) in [(plYZ,spYZ), (plXZ,spXZ), (plXY,spXY)]
      Winston.add(pl, sp)
    end
  end

  # show fields
  display(m.fv.grid[1,1], plXZ)
  display(m.fv.grid[2,1], plYZ)
  display(m.fv.grid[2,2], plXY)

end

# plotting the coefficients
function updateCoeffsPlot(m::MagneticFieldViewerWidget)

  # TODO: x-axis labels/ticks

  # normalize coefficients
  p = get_gtk_property(m["adjPatches"],:value, Int64) # patch
  L = get_gtk_property(m["adjL"],:value, Int64) # L
  L² = (L+1)^2 # number of coeffs
  R = m.coeffs.radius
  c = normalize.(m.coeffsPlot[:,p], 1/R)

  # create plot
  pl = Winston.FramedPlot(xlabel="[l,m]", ylabel="\\gamma^R_{l,m} / T")

  # x values
  y = range(1,L²,length=L²)
  x = y .- 0.2
  z = y .+ 0.2

  # create bars for each direction
  w = get_gtk_property(m["adjBarWidth"],:value, Int64) # width of the bars
  xx = Winston.Stems(x, c[1].c[1:L²], color=(0.0,0.2862,0.5725), width=w)
  yy = Winston.Stems(y, c[2].c[1:L²], color=(0.5412,0.7412,0.1412), width=w)
  zz = Winston.Stems(z, c[3].c[1:L²], color=(1.0,0.8745,0.0), width=w)

  # add bars to plot
  Winston.add(pl,xx, yy, zz)

  # xtick labels
  xticklabel = ["[$l,$m]" for l=0:L for m=-l:l]
#  setattr(pl.x1, ticklabels=["[$l,$m]" for l=0:L for m=-l:l][1:4:end])

  # legend
  Winston.setattr(xx, label="x")
  Winston.setattr(yy, label="y")
  Winston.setattr(zz, label="z")
  l = Winston.Legend(.95, .9, [xx,yy,zz])
  Winston.add(pl, l)

  # show coeffs
  display(m.grid[1,3], pl)
end
