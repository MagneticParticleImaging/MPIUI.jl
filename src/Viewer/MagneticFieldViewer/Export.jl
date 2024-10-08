## Export magnetic fields

# link buttons to corresponding functions
function initExportCallbacks(m::MagneticFieldViewerWidget)
  # export shown plots as png
  @guarded signal_connect(m["btnExportImages"], "clicked") do widget
    exportCanvas(m)
  end
  # CSV: Export Coeffs
  @guarded signal_connect(m["btnExportCoeffsCSV"], "clicked") do widget
    saveCoeffsAsCSV(m)
  end
  # CSV: Export Field
  @guarded signal_connect(m["btnExportFieldCSV"], "clicked") do widget
    saveFieldAsCSV(m)
  end
  # Tikz
  @guarded signal_connect(m["btnExportTikz"], "clicked") do widget
    saveTikz(m)
  end
end

# Export plots as pngs
function exportCanvas(m::MagneticFieldViewerWidget)
  # choose destination
  filter = Gtk4.GtkFileFilter(pattern=String("*.png"), mimetype=String("image/png"))
  diag = save_dialog("Select Export File", nothing, (filter, )) do filename
    if filename != ""
      @info "Export Image as" filename

      # get only filename
      file, ext = splitext(filename)
      # Field plots
      if get_gtk_property(m["cbFieldExport"],:active,Bool)
        write_to_png(getgc(m.fv.grid[1,1]).surface,file*"_xz.png")
        write_to_png(getgc(m.fv.grid[2,1]).surface,file*"_yz.png")
        write_to_png(getgc(m.fv.grid[2,2]).surface,file*"_xy.png")
      end
      # Coefficients
      if get_gtk_property(m["cbCoeffsExport"],:active,Bool)
        write_to_png(getgc(m.grid[1,3]).surface,file*"_coeffs.png")
      end
      # Profile
      if get_gtk_property(m["cbProfileExport"],:active,Bool)
        write_to_png(getgc(m.fv.grid[1,2]).surface,file*"_profile.png")
      end

      return filename
    end 
  end
  diag.modal = true
end

#################
# Export as csv #
#################
# export coefficients

function saveCoeffsAsCSV(m::MagneticFieldViewerWidget)
  # choose destination
  filter = Gtk4.GtkFileFilter(pattern=String("*.csv"), mimetype=String("image/csv"))
  diag = save_dialog("Select Export File", nothing, (filter, )) do filename
    if filename != ""
      @info "Export coefficients as" filename

      saveCoeffsAsCSV(m, filename)

      return filename
    end 
  end
  diag.modal = true
end

function saveCoeffsAsCSV(m::MagneticFieldViewerWidget, filename)
  # get only filename
  file, ext = splitext(filename)

  # get some values
  p = get_gtk_property(m["adjPatches"],:value, Int64) # patch
  L = get_gtk_property(m["adjL"],:value, Int64) # L
  L² = (L+1)^2 # number of coefficients to be saved
  R = m.coeffs.radius # radius for normalization

  # Create Array with the data
  coeffsSave = ["num" "x" "y" "z"]
  coeffsSave = vcat(coeffsSave,zeros(L²,4)) # length(coeffs[1,1].c) = (L+1)^2
  coeffsSave[2:end,1] = 1:L²
  for j=1:3
    coeffsSave[2:end,j+1] = normalize(m.coeffsPlot[j,p],1/R).c[1:L²]
  end 

  # save
  writedlm(file*".csv",coeffsSave,';');
end

# export magnetic field
function saveFieldAsCSV(m::MagneticFieldViewerWidget)
  # choose destination
  filter = Gtk4.GtkFileFilter(pattern=String("*.csv"), mimetype=String("image/csv"))
  diag = save_dialog("Select Export File", nothing, (filter, )) do filename
    if filename != ""
      @info "Export field as" filename

      saveFieldAsCSV(m, filename)

      return filename
    end 
  end
  diag.modal = true
end

function saveFieldAsCSV(m::MagneticFieldViewerWidget, filename)
  # get only filename
  file, ext = splitext(filename)
 
  # load all parameters
  discretization = Int(get_gtk_property(m["adjDiscretization"],:value, Int64)*2+1) # odd number of voxel
  R = m.coeffs.radius # radius of measurement data

  # get FOV
  fovString = get_gtk_property(m["entFOV"], :text, String) # FOV
  fov = tryparse.(Float64,split(fovString,"x")) ./ 1000

  # Grid
  N = [range(-fov[i]/2,stop=fov[i]/2,length=discretization) for i=1:3];

  # calculate field for plot 
  fieldNorm = zeros(discretization,discretization,3);
  fieldxyz = zeros(3,discretization,discretization,3);
  setPatch!(m.field,m.patch) # set selected patch
  for i = 1:discretization
    for j = 1:discretization
      fieldxyz[:,i,j,1] = m.field[m.fv.intersection[1],N[2][i],N[3][j]]
      fieldNorm[i,j,1] = norm(fieldxyz[:,i,j,1])
      fieldxyz[:,i,j,2] = m.field[N[1][i],m.fv.intersection[2],N[3][j]]
      fieldNorm[i,j,2] = norm(fieldxyz[:,i,j,2])
      fieldxyz[:,i,j,3] = m.field[N[1][i],N[2][j],m.fv.intersection[3]]
      fieldNorm[i,j,3] = norm(fieldxyz[:,i,j,3])
    end 
  end

  # collect all coordinates for export to tikz
  Nyz = hcat([[N[2][i],N[3][j]] for i=1:discretization for j=1:discretization]...)
  Nxz = hcat([[N[1][i],N[3][j]] for i=1:discretization for j=1:discretization]...)
  Nxy = hcat([[N[1][i],N[2][j]] for i=1:discretization for j=1:discretization]...)

  # create DataFrame
  df = DataFrame("PlaneYZ_y"=> Nyz[1,:],
        "PlaneYZ_z" => Nyz[2,:],
        "PlaneYZ_f" => vec(permutedims(fieldNorm[:,:,1],[2,1])),
        "PlaneXZ_x" => Nxz[1,:],
        "PlaneXZ_z" => Nxz[2,:],
        "PlaneXZ_f" => vec(permutedims(fieldNorm[:,:,2],[2,1])),
        "PlaneXY_x" => Nxy[1,:],
        "PlaneXY_y" => Nxy[2,:],
        "PlaneXY_f" => vec(permutedims(fieldNorm[:,:,3],[2,1]))
        )

  # save as csv
  CSV.write(file*".csv",df);

  ############
  ## Quiver ##
  ############
  discr = floor(Int,0.1*discretization) # reduce number of arrows
  fieldxyz = [fieldxyz[d,1:discr:end,1:discr:end,:] for d=1:3]

  # collect all coordinates for export to tikz
  Nyz = hcat([[N[2][i],N[3][j]] for i=1:discr:discretization for j=1:discr:discretization]...)
  Nxz = hcat([[N[1][i],N[3][j]] for i=1:discr:discretization for j=1:discr:discretization]...)
  Nxy = hcat([[N[1][i],N[2][j]] for i=1:discr:discretization for j=1:discr:discretization]...)

  # create DataFrame
  df = DataFrame("PlaneYZ_y"=> Nyz[1,:],
        "PlaneYZ_z" => Nyz[2,:],
        "quiver_yzu" => vec(permutedims(fieldxyz[2][:,:,1],[2,1])), # "PlaneYZ_u"
        "quiver_yzv" => vec(permutedims(fieldxyz[3][:,:,1],[2,1])), # "PlaneYZ_v"
        "PlaneXZ_x" => Nxz[1,:],
        "PlaneXZ_z" => Nxz[2,:],
        "PlaneXZ_u" => vec(permutedims(fieldxyz[1][:,:,2],[2,1])),
        "PlaneXZ_v" => vec(permutedims(fieldxyz[3][:,:,2],[2,1])),
        "PlaneXY_x" => Nxy[1,:],
        "PlaneXY_y" => Nxy[2,:],
        "Xyu" => vec(permutedims(fieldxyz[1][:,:,3]',[2,1])), # "PlaneXY_u"
        "Xyv" => vec(permutedims(fieldxyz[2][:,:,3]',[2,1])), # "PlaneXY_v"
	)

  # save as csv
  CSV.write(file*"_quiver"*".csv",df);
end

###############
# Export tikz #
###############
# export plots as tex-file
function saveTikz(m::MagneticFieldViewerWidget)
  # choose destination
  filter = Gtk4.GtkFileFilter(pattern=String("*.tex"), mimetype=String("image/tex"))
  diag = save_dialog("Select Export File", nothing, (filter, )) do filename
    if filename != ""
      @info "Export tikz as" filename

      saveTikz(m, filename)

      return filename
    end 
  end
  diag.modal = true
end

function saveTikz(m::MagneticFieldViewerWidget, filename)
  # get only filename
  file, ext = splitext(filename)

  # load parameter
  cmin = m.fv.coloring.cmin
  cmax = m.fv.coloring.cmax
  discretization = Int(get_gtk_property(m["adjDiscretization"],:value, Int64)*2+1) # odd number of voxel
  arrowLength = get_gtk_property(m["adjArrowLength"],:value, Int64)
  R = m.coeffs.radius
  L = m.coeffs.coeffs[1].L 
  # get tex code
  tex = exportTikz(file,cmin,cmax,discretization,arrowLength,R,L)

  # export data
  saveCoeffsAsCSV(m, file*"_coeffs")
  saveFieldAsCSV(m, file*"_field")

  # save tex-file
  write(file*".tex",tex)
  
  # compile tex-file
  if get_gtk_property(m["cbBuildPdf"], :active, Bool)
    # get output folder
    path, = splitdir(file)
    run(`pdflatex -output-directory=$(path) $(file).tex`)
  end
end