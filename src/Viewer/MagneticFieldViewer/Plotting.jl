##############
## Plotting ##
##############

# update all plots
function updatePlots(m::MagneticFieldViewerWidget)

      # Coefficients
      updateCoeffsPlot(m)
      # calculate new field values
      calcField(m) 
      # Field
      updateField(m)
      # Profile
      updateProfile(m)
end


##################
# Magnetic field #
##################
# calculate the field (and profiles)
function calcField(m::MagneticFieldViewerWidget)
 
   discretization = Int(get_gtk_property(m["adjDiscretization"],:value, Int64)*2+1) # odd number of voxel

  # get current intersection
  intersString = get_gtk_property(m["entInters"], :text, String) # intersection
  m.fv.intersection = tryparse.(Float64,split(intersString,"x")) ./ 1000 # conversion from mm to m

  # get FOV
  fovString = get_gtk_property(m["entFOV"], :text, String) # FOV
  fov = tryparse.(Float64,split(fovString,"x")) ./ 1000 # conversion from mm to m

  # Grid (fov denotes the size and not the first and last pixel)
  # center = m.coeffs.center # center of measurement data (TODO: adapt axis with measurement center)
  m.fv.positions = [range(-fov[i]/2,stop=fov[i]/2,length=discretization+1) for i=1:3];
  for i=1:3
    m.fv.positions[i] = m.fv.positions[i][1:end-1] .+ Float64(m.fv.positions[i].step)/2
  end
  N = m.fv.positions # renaming

  # calculate field for plot 
  m.fv.fieldNorm = zeros(discretization,discretization,3)
  m.fv.field = zeros(3,discretization,discretization,3)
  m.fv.currentProfile = zeros(4,discretization,3)
  selectPatch(m.field,m.patch) # set selected patch
  for i = 1:discretization
    for j = 1:discretization
      m.fv.field[:,i,j,1] = m.field[m.fv.intersection[1],N[2][i],N[3][j]]
      m.fv.fieldNorm[i,j,1] = norm(m.fv.field[:,i,j,1])
      m.fv.field[:,i,j,2] = m.field[N[1][i],m.fv.intersection[2],N[3][j]]
      m.fv.fieldNorm[i,j,2] = norm(m.fv.field[:,i,j,2])
      m.fv.field[:,i,j,3] = m.field[N[1][i],N[2][j],m.fv.intersection[3]]
      m.fv.fieldNorm[i,j,3] = norm(m.fv.field[:,i,j,3])
    end

    # get current profile
    m.fv.currentProfile[1:3,i,1] = m.field[N[1][i],m.fv.intersection[2],m.fv.intersection[3]] # along x-axis
    m.fv.currentProfile[1:3,i,2] = m.field[m.fv.intersection[1],N[2][i],m.fv.intersection[3]] # along y-axis
    m.fv.currentProfile[1:3,i,3] = m.field[m.fv.intersection[1],m.fv.intersection[2],N[3][i]] # along z-axis
    m.fv.currentProfile[4,i,:] = [norm(m.fv.currentProfile[1:3,i,d]) for d=1:3] # norm along all axes
  end

end

# plotting the magnetic field
function updateField(m::MagneticFieldViewerWidget, updateColoring=false)

  useMilli = get_gtk_property(m["cbUseMilli"], :active, Bool) # convert everything to mT or mm
  discretization = Int(get_gtk_property(m["adjDiscretization"],:value, Int64)*2+1) # odd number of voxel
  R = m.coeffs.radius # radius of measurement data
  if m.coeffs.ffp !== nothing
    ffp = useMilli ? m.coeffs.ffp .* 1000 : m.coeffs.ffp # used for correct positioning of the sphere
  end
  center = useMilli ? m.coeffs.center .* 1000 : m.coeffs.center # center of measured sphere
  N = m.fv.positions

  # coloring params
  if updateColoring
    # use params from GUI
    cmin = m.fv.coloring.cmin
    cmax = m.fv.coloring.cmax
    cmap = m.fv.coloring.cmap
    # set new min/max values
      set_gtk_property!(m["adjCMin"], :upper, 0.99*cmax * 1000) # prevent cmin=cmax
      set_gtk_property!(m["adjCMax"], :lower, 1.01*cmin * 1000) # prevent cmin=cmax
  elseif get_gtk_property(m["cbKeepC"], :active, Bool) 
    # don't change min/max if the checkbutton is active
    cmin = m.fv.coloring.cmin
    cmax = m.fv.coloring.cmax
    cmap = m.fv.coloring.cmap
  elseif get_gtk_property(m["cbWriteC"], :active, Bool)
    # get min/max from entCMin/Max
    cminString = get_gtk_property(m["entCMin"], :text)
    cmin = tryparse.(Float64,cminString) ./ 1000
    cmaxString = get_gtk_property(m["entCMax"], :text)
    cmax = tryparse.(Float64,cmaxString) ./ 1000
    cmap = m.fv.coloring.cmap
    m.fv.coloring = ColoringParams(cmin, cmax, cmap) # set coloring
  else
    # set new coloring params
    cmin, cmax = minimum(m.fv.fieldNorm), maximum(m.fv.fieldNorm)
    cmin = (get_gtk_property(m["cbCMin"], :active, Bool)) ? 0.0 : cmin # set cmin to 0 if checkbutton is active
    cmap = m.fv.coloring.cmap
    m.fv.coloring = ColoringParams(cmin, cmax, cmap) # set coloring
    # set cmin and cmax
      set_gtk_property!(m["adjCMin"], :lower, cmin * 1000)
      set_gtk_property!(m["adjCMin"], :upper, 0.99*cmax * 1000) # prevent cmin=cmax
      set_gtk_property!(m["adjCMax"], :lower, 1.01*cmin * 1000) # prevent cmin=cmax
      set_gtk_property!(m["adjCMax"], :upper, cmax * 1000)
      @idle_add_guarded set_gtk_property!(m["adjCMin"], :value, cmin * 1000)
      @idle_add_guarded set_gtk_property!(m["adjCMax"], :value, cmax * 1000)
  end
  # update coloring infos
  set_gtk_property!(m["entCMin"], :text, "$(round(m.fv.coloring.cmin * 1000, digits=1))")
  set_gtk_property!(m["entCMax"], :text, "$(round(m.fv.coloring.cmax * 1000, digits=1))")

  # convert N to mT
  N = useMilli ? N .* 1000 : N
 
  # heatmap plots
  # label
  lab = [useMilli ? "$i / mm" : "$i / m" for i in ["x", "y", "z"]]
  # YZ
  figYZ = CairoMakie.Figure(figure_padding=0);
  axYZ = CairoMakie.Axis(figYZ[1,1], xlabel=lab[2], ylabel=lab[3])
  CairoMakie.heatmap!(axYZ, N[2], N[3], m.fv.fieldNorm[:,:,1], colorrange=(cmin,cmax), colormap=cmap)
  # XZ
  figXZ = CairoMakie.Figure(figure_padding=0);
  axXZ = CairoMakie.Axis(figXZ[1,1], xlabel=lab[1], ylabel=lab[3]) 
  axXZ.xreversed = true # reverse x
  CairoMakie.heatmap!(axXZ, N[1], N[3], m.fv.fieldNorm[:,:,2], colorrange=(cmin,cmax), colormap=cmap)
  # XY
  figXY = CairoMakie.Figure(figure_padding=0);
  axXY = CairoMakie.Axis(figXY[1,1], xlabel=lab[2], ylabel=lab[1])
  CairoMakie.heatmap!(axXY, N[2], N[1], m.fv.fieldNorm[:,:,3]', colorrange=(cmin,cmax), colormap=cmap)
  axXY.yreversed = true # reverse x
  

  # disable ticks and labels
  if !(get_gtk_property(m["cbShowCS"], :active, Bool))
    for ax in [axYZ, axXZ, axXY]
      ax.xlabelvisible = false; ax.ylabelvisible = false; 
      ax.xticklabelsvisible = false; ax.yticklabelsvisible = false; 
      ax.xticksvisible = false; ax.yticksvisible = false;
    end
  end

  ## arrows ##
  discr = floor(Int,0.1*discretization) # reduce number of arrows
  ## positioning
  NN = [N[i][1:discr:end] for i=1:3]
  # vectors (arrows) (adapted to chosen coordinate orientations)
  arYZ = [[m.fv.field[2,i,j,1],m.fv.field[3,i,j,1]] for i=1:discr:discretization, j=1:discr:discretization]
  arXZ = [[m.fv.field[1,i,j,2],m.fv.field[3,i,j,2]] for i=1:discr:discretization, j=1:discr:discretization]
  arXY = [[m.fv.field[2,i,j,3],m.fv.field[1,i,j,3]] for i=1:discr:discretization, j=1:discr:discretization]
  
  # calculate [u,v] for each arrow
  # YZ
  arYZu = [ar[1] for ar in arYZ]
  arYZv = [ar[2] for ar in arYZ]
  maxYZ = maximum([norm([arYZu[i],arYZv[i]]) for i in eachindex(arYZu)]) # for proper scaling
  # XZ
  arXZu = [ar[1] for ar in arXZ]
  arXZv = [ar[2] for ar in arXZ]
  maxXZ = maximum([norm([arXZu[i],arXZv[i]]) for i in eachindex(arXZu)]) # for proper scaling
  # XY
  arXYu = [ar[1] for ar in arXY]
  arXYv = [ar[2] for ar in arXY]
  maxXY = maximum([norm([arXYu[i],arXYv[i]]) for i in eachindex(arXYu)]) # for proper scaling

  # scale arrows
  al = get_gtk_property(m["adjArrowLength"],:value, Float64)
  al /= max(maxYZ,maxXZ,maxXY)
  al /= useMilli ? 1 : 1000 # scale depends on m resp. mm

  # add arrows to plots
  # YZ
  CairoMakie.arrows!(axYZ, NN[2], NN[3], arYZu, arYZv, 
		     color=:white, linewidth=1, arrowsize = 6, lengthscale = al)
  # XZ
  CairoMakie.arrows!(axXZ, NN[1], NN[3], arXZu, arXZv, 
		     color=:white, linewidth=1, arrowsize = 6, lengthscale = al)
  # XY
  CairoMakie.arrows!(axXY, NN[2], NN[1], arXYu', arXYv', 
		     color=:white, linewidth=1, arrowsize = 6, lengthscale = al)

  # set fontsize
  fs = get_gtk_property(m["adjFontsize"],:value, Int64) # fontsize
  CairoMakie.set_theme!(CairoMakie.Theme(fontsize = fs)) # set fontsize for the whole plot

  # Show slices
  if get_gtk_property(m["cbShowSlices"], :active, Bool)
    # draw lines to mark 0
    intersec = useMilli ? m.fv.intersection .*1000 : m.fv.intersection # scale intersection to the chosen unit
    # YZ
    CairoMakie.hlines!(axYZ, intersec[3], color=:white, linestyle=:dash, linewidth=0.5)
    CairoMakie.vlines!(axYZ, intersec[2], color=:white, linestyle=:dash, linewidth=0.5)
    # XZ
    CairoMakie.hlines!(axXZ, intersec[3], color=:white, linestyle=:dash, linewidth=0.5)
    CairoMakie.vlines!(axXZ, intersec[1], color=:white, linestyle=:dash, linewidth=0.5)
    # XY
    CairoMakie.hlines!(axXY, intersec[1], color=:white, linestyle=:dash, linewidth=0.5)
    CairoMakie.vlines!(axXY, intersec[2], color=:white, linestyle=:dash, linewidth=0.5)
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
    rr = useMilli ? rr .* 1000 : rr # convert from m to mm

    # shift sphere to plotting center
    if m.fv.centerFFP && m.coeffs.ffp !== nothing
      CairoMakie.lines!(axYZ, rr[:,1].-center[2,m.patch], rr[:,2].-center[3,m.patch], 
			color=:white, linestyle=:dash, linewidth=1)
      CairoMakie.lines!(axXZ, rr[:,1].-center[1,m.patch], rr[:,2].-center[3,m.patch], 
			color=:white, linestyle=:dash, linewidth=1)
      CairoMakie.lines!(axXY, rr[:,1].-center[2,m.patch], rr[:,2].-center[1,m.patch], 
			color=:white, linestyle=:dash, linewidth=1)
    else
      CairoMakie.lines!(axYZ, rr[:,1], rr[:,2], color=:white, linestyle=:dash, linewidth=1)
      CairoMakie.lines!(axXZ, rr[:,1], rr[:,2], color=:white, linestyle=:dash, linewidth=1)
      CairoMakie.lines!(axXY, rr[:,1], rr[:,2], color=:white, linestyle=:dash, linewidth=1)
    end

  end

  # show fields
  drawonto(m.fv.grid[1,1], figXZ)
  drawonto(m.fv.grid[2,1], figYZ)
  drawonto(m.fv.grid[2,2], figXY)

  # draw axes (only arrows)
  if get_gtk_property(m["cbShowAxes"], :active, Bool)
    for w in [[m.fv.grid[1,1],"xz"], [m.fv.grid[2,1],"yz"], [m.fv.grid[2,2], "xy"]]
      @idle_add_guarded Gtk4.draw(w[1]) do widget
        ctx = getgc(w[1])
        drawAxes(ctx, w[2])
        set_line_width(ctx, 3.0)
        Cairo.stroke(ctx) 
      end
    end
  end
  
end

################
# Coefficients #
################
# plotting the coefficients
function updateCoeffsPlot(m::MagneticFieldViewerWidget)

  p = get_gtk_property(m["adjPatches"],:value, Int64) # patch
  L = get_gtk_property(m["adjL"],:value, Int64) # L
  L² = (L+1)^2 # number of coeffs
  R = m.coeffs.radius
  useMilli = get_gtk_property(m["cbUseMilli"], :active, Bool) # convert everything to mT or mm
  scaleR = get_gtk_property(m["cbScaleR"], :active, Bool) # normalize coefficients with radius R

  # normalize coefficients
  c = scaleR ? normalize.(m.coeffsPlot[:,p], 1/R) : m.coeffsPlot[:,p]
  cs = vcat([c[d].c[1:L²] for d=1:3]...) # stack all coefficients
  cs = useMilli ? cs .* 1000 : cs # convert to mT
  grp = repeat(1:3, inner=L²) # grouping the coefficients

  # set fontsize
  fs = get_gtk_property(m["adjFontsize"],:value, Int64) # fontsize
  CairoMakie.set_theme!(CairoMakie.Theme(fontsize = fs)) # set fontsize for the whole plot

  # create plot
  fig = CairoMakie.Figure(figure_padding=2)
  xticklabel = ["[$l,$m]" for l=0:L for m=-l:l]
  # ylabel
  if useMilli && scaleR
    ylabel = CairoMakie.L"\gamma^R_{l,m}~/~\text{mT}" 
  elseif !useMilli && scaleR
    ylabel = CairoMakie.L"\gamma^R_{l,m}~/~\text{T}"
  elseif useMilli && !scaleR
    ylabel = CairoMakie.L"\gamma_{l,m}~/~\text{mT/m}^l" 
  else 
    ylabel = CairoMakie.L"\gamma_{l,m}~/~\text{T/m}^l"
  end 
  ax = CairoMakie.Axis(fig[1,1], xticks = (1:L², xticklabel), 
	    #title="Coefficients",
	    xlabel = CairoMakie.L"[l,m]", ylabel = ylabel)

  # x values
  y = range(1,L²,length=L²)
  y = repeat(y, outer=3) # for each direction

  # create bars
  colorsCoeffs = [CairoMakie.RGBf(MPIUI.colors[i]...) for i in [1,3,7]] # use blue, green and yellow
  CairoMakie.barplot!(ax, # axis 
           	      y, cs, # x- and y-values
           	      dodge=grp, color=colorsCoeffs[grp])
  CairoMakie.autolimits!(ax) # auto axis limits

  # draw line to mark 0
  CairoMakie.ablines!(0, 0, color=:black, linewidth=1)

  # legend
  if get_gtk_property(m["cbShowLegend"], :active, Bool)
    labels = ["x","y","z"]
    elements = [CairoMakie.PolyElement(polycolor = colorsCoeffs[i],
				       ) for i in 1:length(labels)]
    CairoMakie.axislegend(ax, elements, labels, position=:rt, patchsize=(15,0.8*fs)) # pos: right, top
  end
 
  # show coeffs
  drawonto(m.grid[1,3], fig)
end


################
# profile plot #
################
# update profile plot data
function updateProfile(m::MagneticFieldViewerWidget)
    # ["Norm","xyz","x","y","z"] # cbFrameProj - field
    # ["all", "x", "y", "z"] # cbProfile - axes
  
    # get chosen profiles
    fields = get_gtk_property(m["cbFrameProj"],:active, Int64)
    axesDir = get_gtk_property(m["cbProfile"],:active, Int64)
  
    # positioning
    useMilli = get_gtk_property(m["cbUseMilli"], :active, Bool) # convert everything to mT or mm
    N = m.fv.positions # renaming
    # convert N to mT
    N = useMilli ? N .* 1000 : N 
  
    # colors
    colorsAll = [CairoMakie.RGBf(MPIUI.colors[i]...) for i in [1,3,7]] # use blue, green and yellow
  
    # label
    xlabel = ["xyz", "x", "y", "z"][axesDir+1]
    xlabel *= useMilli ? " / mm" : " / m"
    ylabel = (fields == 0) ? "||B||" : "B"*["","x","y","z"][fields]
    ylabel *= useMilli ? " / mT" : " / T"
  
    # choose colors and data for the plot
    if fields == 1 || axesDir == 0 
  
      # plot all three fields in one direction or one field/norm in all directions
      colorsPlot = colorsAll # all three colors
  
      # data
      x = (axesDir == 0) ? N : N[axesDir] # x values (all axes or one axis)
      if fields == 1 && axesDir == 0 # all fields in their main direction
        y = vcat([m.fv.currentProfile[j,:,j] for j=1:3]'...)
      elseif fields == 1 # all fields in one direction
        y = m.fv.currentProfile[1:3,:,axesDir]
      elseif fields == 0  # norm in all directions
        y = m.fv.currentProfile[4,:,:]'
      else # one field in all directions
        y = m.fv.currentProfile[fields-1,:,:]'
      end
  
    elseif fields != 0 #|| (fields == 0 && axesDir == 1) 
  
      # plot a field in one direction
      colorsPlot = [colorsAll[fields-1]] # x-direction (field or axis)
  
      # data
      x = N[axesDir] # x values
      y = m.fv.currentProfile[fields-1,:,axesDir] 
  
    else #fields == 0 && axesDir != 0 
  
      # plot norm in one direction
      colorsPlot = [colorsAll[axesDir]] # y-direction (field or axis)
  
      # data
      x = N[axesDir] # x values
      y = m.fv.currentProfile[4,:,axesDir] 
  
    end
  
    y *= useMilli ? 1000 : 1
  
    showProfile(m, x, y, xlabel, ylabel, colorsPlot)
  end
  
  # drawing profile plot
  function showProfile(m::MagneticFieldViewerWidget, dataX, dataY,
               xLabel::String, yLabel::String, 
               colors::Vector{RGB{Float32}})
  
    # set fontsize
    fs = get_gtk_property(m["adjFontsize"],:value, Int64) # fontsize
    CairoMakie.set_theme!(CairoMakie.Theme(fontsize = fs)) # set fontsize for the whole plot
  
    # figure
    fig = CairoMakie.Figure(figure_padding=2)
  
    # axis
    ax = CairoMakie.Axis(fig[1,1], 
          #title="Profile",
          xlabel = xLabel, ylabel = yLabel)
  
    # Plot
    for i = 1:length(colors) # number of profiles
      X = (typeof(dataX) <: Vector) ? dataX[i] : dataX
      Y = (typeof(dataY) <: Vector) ? dataY : dataY[i,:]
      CairoMakie.lines!(ax, X, Y, color=colors[i])
    end
    CairoMakie.autolimits!(ax) # auto axis limits
  
    # draw line to mark 0
    CairoMakie.ablines!(0, 0, color=:black, linewidth=1)
  
    drawonto(m.fv.grid[1,2], fig)
  end