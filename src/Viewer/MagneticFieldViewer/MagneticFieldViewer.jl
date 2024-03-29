export MagneticFieldViewer

# load new type MagneticFieldCoefficients with additional informations
include("MagneticFieldUtils.jl")

mutable struct FieldViewerWidget <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  coloring::ColoringParams
  updating::Bool
  field # data to be plotted
  centerFFP::Bool # center of plot (FFP (true) or center of measured sphere (false))
  grid::Gtk4.GtkGridLeaf
end

mutable struct MagneticFieldViewerWidget <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  fv::FieldViewerWidget
  updating::Bool
  coeffsInit::MagneticFieldCoefficients
  coeffs::MagneticFieldCoefficients 
  coeffsPlot::Array{SphericalHarmonicCoefficients}
  field # Array containing Functions of the field
  patch::Int
  grid::Gtk4.GtkGridLeaf
  cmapsTree::Gtk4.GtkTreeModelFilter
end

getindex(m::MagneticFieldViewerWidget, w::AbstractString) = G_.get_object(m.builder, w)
getindex(m::FieldViewerWidget, w::AbstractString) = G_.get_object(m.builder, w)

mutable struct MagneticFieldViewer
  w::Gtk4.GtkWindowLeaf
  mf::MagneticFieldViewerWidget
end

# export functions
include("Export.jl")

# Viewer can be started with MagneticFieldCoefficients or with a path to a file with some coefficients
function MagneticFieldViewer(filename::Union{AbstractString,MagneticFieldCoefficients})
  mfViewerWidget = MagneticFieldViewerWidget()
  w = GtkWindow("Magnetic Field Viewer: $(filename)",800,600)
  push!(w,mfViewerWidget)
  show(w)
  updateData!(mfViewerWidget, filename)
  return MagneticFieldViewer(w, mfViewerWidget)
end

function FieldViewerWidget()
  uifile = joinpath(@__DIR__,"..","..","builder","magneticFieldViewer.ui")

  b = GtkBuilder(uifile)
  mainBox = G_.get_object(b, "boxFieldViewer")

  fv = FieldViewerWidget(mainBox.handle, b, ColoringParams(0,0,0),
                     false, nothing, true,
                      G_.get_object(b, "gridFieldViewer"),)
  Gtk4.GLib.gobject_move_ref(fv, mainBox)

  # initialize plots
  fv.grid[1,1] = GtkCanvas()
  fv.grid[1,2] = GtkCanvas()
  fv.grid[2,1] = GtkCanvas()
  fv.grid[2,2] = GtkCanvas()

  fv.grid.hexpand = fv.grid.vexpand = true
  # expand plots
  ### set_gtk_property!(fv, :expand, fv.grid, true)

  return fv
end

function MagneticFieldViewerWidget()
  uifile = joinpath(@__DIR__,"..","..","builder","magneticFieldViewer.ui")

  b = GtkBuilder(uifile)
  mainBox = G_.get_object(b, "boxMagneticFieldViewer")

  m = MagneticFieldViewerWidget(mainBox.handle, b, FieldViewerWidget(),
                     false, MagneticFieldCoefficients(0), MagneticFieldCoefficients(0), 
                     [SphericalHarmonicCoefficients(0)], nothing, 1,
                     GtkGrid(), GtkTreeModelFilter(GtkListStore(Bool)))
  Gtk4.GLib.gobject_move_ref(m, mainBox)

  # build up plots
  m.grid = m["gridMagneticFieldViewer"]
  m.grid[1,1:2] = m.fv
  m.grid[1,3] = GtkCanvas()
  # expand plot
  ### set_gtk_property!(m, :expand, m.grid, true)
  
  show(m)

  ## setup colormap search
  # create list
  ls = GtkListStore(String, Bool)
  for c in existing_cmaps()
    push!(ls,(c,true))
  end
  # create TreeViewColumn
  rTxt = GtkCellRendererText()
  c = GtkTreeViewColumn("Colormaps", rTxt, Dict([("text",0)]), sort_column_id=0) # column
  # add column to TreeView
  m.cmapsTree = GtkTreeModelFilter(ls)
  G_.set_visible_column(m.cmapsTree,1)
  tv = GtkTreeView(GtkTreeModel(m.cmapsTree))
  push!(tv, c)
  # add to popover
  push!(m["boxCMaps"],tv)
  show(m["boxCMaps"])

  # set important colormaps
  choices = important_cmaps() 
  for c in choices
    push!(m["cbCMaps"], c)
  end
  set_gtk_property!(m["cbCMaps"],:active,5) # default: viridis
  m.fv.coloring = ColoringParams(0,1,important_cmaps()[6]) # set default colormap

  # searching for specific colormaps
  signal_connect(m["entCMaps"], "changed") do w
    @idle_add_guarded begin
      searchText = get_gtk_property(m["entCMaps"], :text, String)
      if searchText == "Martin"
        searchText = "jet1"
      end
      for l=1:length(ls)
        showMe = true
        if length(searchText) > 0
          showMe = showMe && occursin(lowercase(searchText), lowercase(ls[l,1]))
        end
        ls[l,2] = showMe
      end
    end
  end


  # Allow to change between gradient and offset output
  for c in ["Gradient:","Offset:", "Singular values:"]
    push!(m["cbGradientOffset"], c)
  end
  set_gtk_property!(m["cbGradientOffset"],:active,0) # default: Gradient

  # change discretization
  signal_connect(m["adjDiscretization"], "value_changed") do w
    @idle_add_guarded begin
      # adapt min/max slice
      d = get_gtk_property(m["adjDiscretization"],:value, Int64) 
      for w in ["adjSliceX", "adjSliceY", "adjSliceZ"]
        set_gtk_property!(m[w], :value, 0)
        set_gtk_property!(m[w], :lower, -d)
        set_gtk_property!(m[w], :upper, d)
      end
      # update plot
      updateField(m)
    end
  end
  
  # change patch
  signal_connect(m["adjPatches"], "value_changed") do w
    @idle_add_guarded begin
      m.patch = get_gtk_property(m["adjPatches"],:value, Int64) # update patch
      stayInFFP(m)
    end
  end
 
  # change length of arrows
  signal_connect(m["adjArrowLength"], "value_changed") do w
    @idle_add_guarded updateField(m)
  end 

  # change fontsize
  signal_connect(m["adjFontsize"], "value_changed") do w
    @idle_add_guarded updateCoeffsPlot(m)
    if get_gtk_property(m["cbShowAxes"], :active, Bool) # update field plots only if axes shown
      @idle_add_guarded updateField(m)
    end
  end
  
  # change unit
  signal_connect(m["cbUseMilli"], "toggled") do w
    @idle_add_guarded updateCoeffsPlot(m)
    if get_gtk_property(m["cbShowAxes"], :active, Bool) # update field plots only if axes shown
      @idle_add_guarded updateField(m)
    end
  end
 
  # update coeffs plot
  widgets = ["adjL"]
  for ws in widgets 
    signal_connect(m[ws], "value_changed") do w
      @idle_add_guarded updateCoeffsPlot(m)
    end
  end
  signal_connect(m["cbShowLegend"], "toggled") do w
    @idle_add_guarded updateCoeffsPlot(m)
  end
  signal_connect(m["cbScaleR"], "toggled") do w
    @idle_add_guarded normalizeCoeffs(m)
  end

  # update plot (clicked button)
  signal_connect(m["btnUpdate"], "clicked") do w
    @idle_add_guarded begin
      updateIntersection(m)
      updateCoeffsPlot(m)
      updateField(m)
    end
  end

  # update magnetic field plot: 
  # center = center of sphere
  signal_connect(m["btnCenterSphere"], "clicked") do w
    if m.fv.centerFFP
      @idle_add_guarded begin
        set_gtk_property!(m["btnCenterSphere"],:sensitive,false) # disable button
        set_gtk_property!(m["btnCenterFFP"],:sensitive,true) # enable button
        m.fv.centerFFP = false
        calcCenterCoeffs(m,true)
        stayInFFP(m)
      end
    end
  end
  # center = FFP
  signal_connect(m["btnCenterFFP"], "clicked") do w
    if !(m.fv.centerFFP)
      @idle_add_guarded begin
        set_gtk_property!(m["btnCenterFFP"],:sensitive,false) # disable button
        set_gtk_property!(m["btnCenterSphere"],:sensitive,true) # enable button
        m.fv.centerFFP = true
        calcCenterCoeffs(m,true)
        updateCoeffsPlot(m)
        updateField(m)
      end
    end
  end

  # go to FFP
  signal_connect(m["btnGoToFFP"], "clicked") do w
    @idle_add_guarded begin
      m.updating = true 
      goToFFP(m)
      m.updating = false
    end
  end
  # go to zero
  signal_connect(m["btnGoToZero"], "clicked") do w
    @idle_add_guarded begin
      m.updating = true 
      goToFFP(m,true)
      m.updating = false
    end
  end
  
  # calculate FFP
  signal_connect(m["btnCalcFFP"], "clicked") do w
    @idle_add_guarded calcFFP(m)
  end

  # reset everything -> reload Viewer
  signal_connect(m["btnReset"], "clicked") do w
    @idle_add_guarded updateData!(m, m.coeffsInit)
  end

  # checkbuttons changed
  for cb in ["cbShowSphere", "cbShowSlices", "cbShowAxes"]
    signal_connect(m[cb], "toggled") do w
      updateField(m)
    end
  end
  signal_connect(m["cbStayFFP"], "toggled") do w
    if get_gtk_property(m["cbStayFFP"], :active, Bool) # go to FFP only if active
      @idle_add_guarded begin
        goToFFP(m)
      end  
    end
  end
  # checkbutton cmin = 0
  signal_connect(m["cbCMin"], "toggled") do w
    @idle_add_guarded begin
      if get_gtk_property(m["cbCMin"], :active, Bool) # cmin = 0 
        set_gtk_property!(m["adjCMin"], :lower, 0)
        set_gtk_property!(m["adjCMin"], :value, 0)
        set_gtk_property!(m["vbCMin"], :sensitive, false) # disable changing cmin
      else
        set_gtk_property!(m["vbCMin"], :sensitive, true) # enable changing cmin
        updateField(m)
      end
      # updateCol done automatically since value changed for adjCMin
    end
  end
  # checkbutton keeping cmin/cmax
  signal_connect(m["cbKeepC"], "toggled") do w
    @idle_add_guarded begin
      if get_gtk_property(m["cbKeepC"], :active, Bool) # keep the values
        set_gtk_property!(m["vbCMin"], :sensitive, false) # disable changing cmin
        set_gtk_property!(m["vbCMax"], :sensitive, false) # disable changing cmax
      else
        set_gtk_property!(m["vbCMin"], :sensitive, true) # enable changing cmin
        set_gtk_property!(m["vbCMax"], :sensitive, true) # enable changing cmax
      end
    end
  end 

  # update measurement infos
  signal_connect(m["cbGradientOffset"], "changed") do w
    @idle_add_guarded updateInfos(m) 
  end

  initCallbacks(m)

  return m
end


function initCallbacks(m::MagneticFieldViewerWidget)

  ## update coloring
  function updateCol(widget , importantCMaps::Bool=true)

    # update plots
    @idle_add_guarded updateColoring(m,importantCMaps)
    @idle_add_guarded updateField(m,true)
  end
  

  # choose new slice
  function newSlice(widget)
    if !m.updating # don't update slices if they are set by other functions
      m.updating = true
     
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

      m.updating = false
    end
  end

  # cmin/cmax
  widgets = ["adjCMin", "adjCMax"]
  for w in widgets
    signal_connect(m[w], "value_changed") do widget
      @idle_add_guarded updateColLims(m) # update color range
      @idle_add_guarded updateField(m,true)
    end
  end

  # colormap
  signal_connect(updateCol, m["cbCMaps"], "changed")
  signal_connect(G_.get_selection( Gtk4.next_sibling(Gtk4.first_child(m["boxCMaps"]))), "changed") do widget
    updateCol( widget, false )
  end

  ## reset FOV
  function resetFOV( widget )
    R = m.coeffs.radius # radius  
    set_gtk_property!(m["entFOV"], :text, "$(R*2000) x $(R*2000) x $(R*2000)") # initial FOV
    updateField(m)
  end
  signal_connect(resetFOV, m["btnResetFOV"], "clicked")
  
  # change slice
  widgets = ["adjSliceX", "adjSliceY", "adjSliceZ"]
  for w in widgets
    signal_connect(newSlice, m[w], "value_changed")
  end

  ## click on image to choose a slice
  function on_pressed(controller, n_press, x, y)
    if get_gtk_property(m["cbShowAxes"], :active, Bool)
      @info "Disable axes to change the intersection with a mouse click." 
    else
      # position on the image: (x,y)
      # calculate actual position in the fields coordinates to update intersection
      # get image size
      w = widget(controller) # get current widget
      ctx = getgc(w) 
      hh = height(ctx) # height of the plot
      ww = width(ctx) # width of the plot
      # calculate pixel size
      d = get_gtk_property(m["adjDiscretization"],:value, Int64) # number of voxel 
      hpix = hh / (d*2+1) # height of pixel
      wpix = ww / (d*2+1) # width of pixel
      # position (pixel) (counted from the upper left corner)
      pixel = [floor(Int, x / wpix), floor(Int, y / hpix)]

      # update intersection (depending on the image)
      @idle_add_guarded begin
        if w == m.fv.grid[1,1] # XZ
          set_gtk_property!(m["adjSliceX"], :value, -pixel[1]+d)
          set_gtk_property!(m["adjSliceZ"], :value, -pixel[2]+d)
        elseif w == m.fv.grid[2,1] # YZ
          set_gtk_property!(m["adjSliceY"], :value, pixel[1]-d)
          set_gtk_property!(m["adjSliceZ"], :value, -pixel[2]+d)
        else # YX
          set_gtk_property!(m["adjSliceY"], :value, pixel[1]-d)
          set_gtk_property!(m["adjSliceX"], :value, pixel[2]-d)
        end
      end
    end
  end

  for c in [m.fv.grid[1,1], m.fv.grid[2,1], m.fv.grid[2,2]]
    # add the event controller for mouse clicks to the widget
    g = GtkGestureClick()
    push!(c,g)
    # call function
    @idle_add_guarded signal_connect(on_pressed, g, "pressed")
  end


  # export images/data
  initExportCallbacks(m)
end

# load all necessary data and set up the values in the GUI
updateData!(m::MagneticFieldViewerWidget, filenameCoeffs::String) = updateData!(m, MagneticFieldCoefficients(filenameCoeffs))

function updateData!(m::MagneticFieldViewerWidget, coeffs::MagneticFieldCoefficients)
  
  m.coeffsInit = deepcopy(coeffs) # save initial coefficients for reloading

  # load magnetic fields
  m.coeffs = coeffs # load coefficients
  m.coeffsPlot = deepcopy(m.coeffs.coeffs) # load coefficients

  @polyvar x y z
  expansion = sphericalHarmonicsExpansion.(m.coeffs.coeffs,[x],[y],[z])
  m.field = fastfunc.(expansion)
  m.patch = 1
  R = m.coeffs.radius # radius
  center = m.coeffs.center # center of the measurement
  m.fv.centerFFP = (m.coeffs.ffp != nothing) ?  true : false # if FFP is given, it is the plotting center
  set_gtk_property!(m["btnCenterFFP"],:sensitive,false) # disable button
 
  m.updating = true

  # set some values
  set_gtk_property!(m["adjPatches"], :upper, size(m.coeffs.coeffs,2) )
  set_gtk_property!(m["adjPatches"], :value, m.patch )
  set_gtk_property!(m["adjL"], :upper, m.coeffs.coeffs[1].L )
  set_gtk_property!(m["adjL"], :value, min(m.coeffs.coeffs[1].L,3) ) # use L=3 as maximum
  set_gtk_property!(m["entRadius"], :text, "$(round(R*1000,digits=1))") # show radius of measurement 
  centerText = round.(center .* 1000, digits=1)
  set_gtk_property!(m["entCenterMeas"], :text, "$(centerText[1]) x $(centerText[2]) x $(centerText[3])") # show center of measurement
  if m.coeffs.ffp != nothing
    ffpText = round.((center + m.coeffs.ffp[:,m.patch]) .* 1000, digits=1) 
    set_gtk_property!(m["entFFP"], :text, "$(ffpText[1]) x $(ffpText[2]) x $(ffpText[3])") # show FFP of current patch
  else
    set_gtk_property!(m["entFFP"], :text, "no FFP")
  end
  set_gtk_property!(m["entFOV"], :text, "$(R*2000) x $(R*2000) x $(R*2000)") # initial FOV
  set_gtk_property!(m["entInters"], :text, "0.0 x 0.0 x 0.0") # initial FOV
  d = get_gtk_property(m["adjDiscretization"],:value, Int64) # get discretization as min/max for slices
  for w in ["adjSliceX", "adjSliceY", "adjSliceZ"]
    set_gtk_property!(m[w], :lower, -d)
    set_gtk_property!(m[w], :value, 0)
    set_gtk_property!(m[w], :upper, d)
  end

  # if no FFPs are given, don't show the buttons
  if m.coeffs.ffp == nothing
    set_gtk_property!(m["btnGoToFFP"],:visible,false) # FFP as intersection not available
    set_gtk_property!(m["btnCenterFFP"],:visible,false) # FFP as center not available
    set_gtk_property!(m["btnCenterSphere"],:sensitive,false) # Center of sphere automatically plotting center
    set_gtk_property!(m["btnCalcFFP"],:sensitive,true) # FFP can be calculated
  else
    # disable the calcFFP button
    set_gtk_property!(m["btnCalcFFP"],:sensitive,false) # FFP already calculated
  end

  # disable buttons that have no functions at the moment
  set_gtk_property!(m["btnFrames"],:sensitive,false) # disable button with unused popover
  set_gtk_property!(m["btnExportTikz"],:sensitive,false) # tikz export not yet supported

  # start with invisible axes for field plots
  #set_gtk_property!(m["cbShowAxes"], :active, 1) # axes are always shown

  # update measurement infos
  if m.coeffs.ffp == nothing
    # default: show the offset field values if no FFP is given
    set_gtk_property!(m["cbGradientOffset"],:active,1) 
  end
  updateInfos(m)

  # plotting
  updateField(m)
  updateCoeffsPlot(m)
  show(m)
  
  m.updating = false
end

# update the coloring params
function updateColoring(m::MagneticFieldViewerWidget, importantCMaps::Bool=true)
  if !m.fv.updating
    m.fv.updating = true
    # scale adjCMin/adjCMax with 1000 as values below 1 don't work
    cmin = get_gtk_property(m["adjCMin"],:value, Float64) / 1000
    cmax = get_gtk_property(m["adjCMax"],:value, Float64) / 1000
    if importantCMaps # choice happend within the important colormaps
      idx = get_gtk_property(m["cbCMaps"],:active, Int64)+1
      if idx <= 4 # first 4 colormaps not available
        idx = 6
        set_gtk_property!(m["cbCMaps"], :active, 5)
      end
      cmap = important_cmaps()[idx]
    else # choice happened within all colormaps
      selection = G_.get_selection( Gtk4.next_sibling(Gtk4.first_child(m["boxCMaps"])) ) ### G_.get_selection(m["boxCMaps"][2])
      if hasselection(selection)
        chosenCMap = selected(selection)
        cmap = GtkTreeModel(m.cmapsTree)[chosenCMap,1]
      else # use last choice of important colormaps
        cmap = important_cmaps()[get_gtk_property(m["cbCMaps"],:active, Int64)+1]
      end
    end
    m.fv.coloring = ColoringParams(cmin,cmax,cmap)
    m.fv.updating = false
  end
end

# Coloring: Update cmin/cmax only
function updateColLims(m::MagneticFieldViewerWidget)
  if !m.fv.updating
    m.fv.updating = true
    cmin = get_gtk_property(m["adjCMin"],:value, Float64) / 1000
    cmax = get_gtk_property(m["adjCMax"],:value, Float64) / 1000
    m.fv.coloring = ColoringParams(cmin,cmax,m.fv.coloring.cmap) # keep cmap
    m.fv.updating = false
  end
end


# update slices
function updateSlices(m::MagneticFieldViewerWidget)
  # get current intersection
  intersString = get_gtk_property(m["entInters"], :text, String) # intersection
  intersection = tryparse.(Float64,split(intersString,"x")) ./ 1000 # conversion from mm to m

  # get voxel size
  fovString = get_gtk_property(m["entFOV"], :text, String) # FOV
  fov = tryparse.(Float64, split(fovString,"x")) ./ 1000 # conversion from mm to m
  discretization = Int(get_gtk_property(m["adjDiscretization"], :value, Int64)*2+1) # odd number of voxel 
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
  updateCoeffs(m, intersection) # shift to intersection
end

function goToFFP(m::MagneticFieldViewerWidget, goToZero=false)
  if m.coeffs.ffp == nothing && !goToZero
    # no FFP given
    return nothing
  end

  m.updating = true

  # set new intersection
  intersection = (goToZero || m.fv.centerFFP) ? [0.0,0.0,0.0] : m.coeffs.ffp[:,m.patch]
  interString = round.(intersection .* 1000, digits=1)
  set_gtk_property!(m["entInters"], :text, 
		"$(interString[1]) x $(interString[2]) x $(interString[3])") 

  updateSlices(m) # update slice numbers
  calcCenterCoeffs(m) # recalculate coefficients regarding to the center
  updateCoeffs(m, intersection) # shift coefficients into new intersection 
  updateCoeffsPlot(m)
  updateField(m)

  m.updating = false
end

# calculate the FFP of the given coefficients
function calcFFP(m::MagneticFieldViewerWidget)
  
  # calculate the FFP 
  @polyvar x y z
  expansion = sphericalHarmonicsExpansion.(m.coeffs.coeffs,[x],[y],[z])
  m.coeffs.ffp = findFFP(expansion,x,y,z)
  
  # show FFP
  ffpText = round.((m.coeffs.center + m.coeffs.ffp[:,m.patch]) .* 1000, digits=1) 
  set_gtk_property!(m["entFFP"], :text, "$(ffpText[1]) x $(ffpText[2]) x $(ffpText[3])") # show FFP of current patch
    
  # translate coefficients center of measured sphere into the FFP
  for p = 1:size(m.coeffs.coeffs,2)
    m.coeffs.coeffs[:,p] = SphericalHarmonicExpansions.translation.(m.coeffs.coeffs[:,p],[m.coeffs.ffp[:,p]])
  end

  # show FFP regarding buttons
  set_gtk_property!(m["btnGoToFFP"],:visible,true) # FFP as intersection
  set_gtk_property!(m["btnCenterFFP"],:visible,true) # FFP as center
  set_gtk_property!(m["btnCenterFFP"],:sensitive,true) # FFP as center
  # disable calcFFP button
  set_gtk_property!(m["btnCalcFFP"],:sensitive,false) # FFP already calculated
#  set_gtk_property!(m["btnCenterSphere"],:sensitive,false) # Center of sphere automatically plotting center
end

# if button "Stay in FFP" true, everything is shifted into FFP, else the plots are updated
function stayInFFP(m::MagneticFieldViewerWidget)
  # update plots
  if get_gtk_property(m["cbStayFFP"], :active, Bool) && m.coeffs.ffp != nothing
    # stay in (resp. got to) the FFP with the plot
    goToFFP(m)
  else 
    # use intersection and just update both plots 
    updateField(m)
    updateCoeffsPlot(m)
  end
end

# normalize coefficients with radius
function normalizeCoeffs(m::MagneticFieldViewerWidget)
  # set some default values if the checkbutton is changed
  if get_gtk_property(m["cbScaleR"], :active, Bool)
    set_gtk_property!(m["adjL"], :value, min(m.coeffs.coeffs[1].L,3) ) # use L=3 as maximum
    set_gtk_property!(m["cbUseMilli"], :active, true) # use mT
  else
    set_gtk_property!(m["adjL"], :value, 1 ) # use L=1 for coefficients scaled with R
    set_gtk_property!(m["cbUseMilli"], :active, false) # use T/m^l
  end

  updateCoeffsPlot(m) # update plot
end

# update coefficients
function updateCoeffs(m::MagneticFieldViewerWidget, shift)

  # translate coefficients
  for p = 1:size(m.coeffs.coeffs,2)
    if size(shift) != size(m.coeffs.coeffs) # same shift for all coefficients
      m.coeffsPlot[:,p] = SphericalHarmonicExpansions.translation.(m.coeffsPlot[:,p],[shift])
    else
      m.coeffsPlot[:,p] = SphericalHarmonicExpansions.translation.(m.coeffsPlot[:,p],[shift[:,p]])
    end
  end

  # update measurement infos
  updateInfos(m)

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

  # update measurement infos
  updateInfos(m)
end

# updating the measurement informations
function updateInfos(m::MagneticFieldViewerWidget)
  # return new FFP
  if m.coeffs.ffp != nothing
    ffpText = round.((m.coeffs.center + m.coeffs.ffp[:,m.patch]) .* 1000, digits=1) 
    set_gtk_property!(m["entFFP"], :text, "$(ffpText[1]) x $(ffpText[2]) x $(ffpText[3])") # show FFP of current patch
  end

  # update gradient/offset information
  if get_gtk_property(m["cbGradientOffset"],:active, Int) == 0 # show gradient
    # gradient
    set_gtk_property!(m["entGradientX"], :text, "$(round(m.coeffsPlot[1,m.patch][1,1],digits=3))") # show gradient in x
    set_gtk_property!(m["entGradientY"], :text, "$(round(m.coeffsPlot[2,m.patch][1,-1],digits=3))") # show gradient in y
    set_gtk_property!(m["entGradientZ"], :text, "$(round(m.coeffsPlot[3,m.patch][1,0],digits=3))") # show gradient in z
    # unit
    for i=1:3
      set_gtk_property!(m["labelTpm$i"], :label, "T/m")
      set_gtk_property!(m["labelGradient$i"], :label, ["x","y","z"][i]) 
    end
  elseif get_gtk_property(m["cbGradientOffset"],:active, Int) == 1 # show offset field
    for (i,x) in enumerate(["X","Y","Z"])
      # offset
      set_gtk_property!(m["entGradient"*x], :text, "$(round(m.coeffsPlot[i,m.patch][0,0]*1000,digits=1))") # show gradient in x
      # unit
      set_gtk_property!(m["labelTpm$i"], :label, "mT")
      set_gtk_property!(m["labelGradient$i"], :label, ["x","y","z"][i]) 
    end
  else # show singular values
    # calculate jacobian matrix
    @polyvar x y z
    expansion = sphericalHarmonicsExpansion.(m.coeffsPlot,[x],[y],[z])
    jexp = differentiate(expansion[:,m.patch],[x,y,z]);
    J = [jexp[i,j]((x,y,z) => [0.0,0.0,0.0]) for i=1:3, j=1:3] # jacobian matrix
    # get singular values
    sv = svd(J).S 
    # show values
    for (i,x) in enumerate(["X","Y","Z"])
      set_gtk_property!(m["entGradient"*x], :text, "$(round(sv[i],digits=3))") # singular values
      set_gtk_property!(m["labelTpm$i"], :label, "T/m") # unit
      set_gtk_property!(m["labelGradient$i"], :label, "$i") 
    end
  end

end

##############
## Plotting ##
##############
# plotting the magnetic field
function updateField(m::MagneticFieldViewerWidget, updateColoring=false)

  useMilli = get_gtk_property(m["cbUseMilli"], :active, Bool) # convert everything to mT or mm
  discretization = Int(get_gtk_property(m["adjDiscretization"],:value, Int64)*2+1) # odd number of voxel
  R = m.coeffs.radius # radius of measurement data
  # center = m.coeffs.center # center of measurement data (TODO: adapt axis with measurement center)
  # m.patch = get_gtk_property(m["adjPatches"],:value, Int64) # patch
  if m.coeffs.ffp != nothing
    ffp = useMilli ? m.coeffs.ffp .* 1000 : m.coeffs.ffp # used for correct positioning of the sphere
  end
  # get current intersection
  intersString = get_gtk_property(m["entInters"], :text, String) # intersection
  intersection = tryparse.(Float64,split(intersString,"x")) ./ 1000 # conversion from mm to m

  # get FOV
  fovString = get_gtk_property(m["entFOV"], :text, String) # FOV
  fov = tryparse.(Float64,split(fovString,"x")) ./ 1000 # conversion from mm to m

  # Grid (fov denotes the size and not the first and last pixel)
  N = [range(-fov[i]/2,stop=fov[i]/2,length=discretization+1) for i=1:3];
  for i=1:3
    N[i] = N[i][1:end-1] .+ Float64(N[i].step)/2
  end

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
      set_gtk_property!(m["adjCMin"], :upper, 0.99*cmax * 1000) # prevent cmin=cmax
      set_gtk_property!(m["adjCMax"], :lower, 1.01*cmin * 1000) # prevent cmin=cmax
  elseif get_gtk_property(m["cbKeepC"], :active, Bool) 
    # don't change min/max if the checkbutton is active
    cmin = m.fv.coloring.cmin
    cmax = m.fv.coloring.cmax
    cmap = m.fv.coloring.cmap
  else
    # set new coloring params
    cmin, cmax = minimum(fieldNorm), maximum(fieldNorm)
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
  CairoMakie.heatmap!(axYZ, N[2], N[3], fieldNorm[:,:,1], colorrange=(cmin,cmax), colormap=cmap)
  # XZ
  figXZ = CairoMakie.Figure(figure_padding=0);
  axXZ = CairoMakie.Axis(figXZ[1,1], xlabel=lab[1], ylabel=lab[3]) 
  axXZ.xreversed = true # reverse x
  CairoMakie.heatmap!(axXZ, N[1], N[3], fieldNorm[:,:,2], colorrange=(cmin,cmax), colormap=cmap)
  # XY
  figXY = CairoMakie.Figure(figure_padding=0);
  axXY = CairoMakie.Axis(figXY[1,1], xlabel=lab[2], ylabel=lab[1])
  CairoMakie.heatmap!(axXY, N[2], N[1], fieldNorm[:,:,3]', colorrange=(cmin,cmax), colormap=cmap)
  axXY.yreversed = true # reverse x
  

  # disable ticks and labels
  if !(get_gtk_property(m["cbShowAxes"], :active, Bool))
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
  arYZ = [[fieldxyz[2,i,j,1],fieldxyz[3,i,j,1]] for i=1:discr:discretization, j=1:discr:discretization]
  arXZ = [[fieldxyz[1,i,j,2],fieldxyz[3,i,j,2]] for i=1:discr:discretization, j=1:discr:discretization]
  arXY = [[fieldxyz[2,i,j,3],fieldxyz[1,i,j,3]] for i=1:discr:discretization, j=1:discr:discretization]
  # adapt length so that the maximum is equal to the chosen al:
  al = get_gtk_property(m["adjArrowLength"],:value, Float64)/2 # adapt length of the arrows
  al = useMilli ? al*1000 : al # adapt length with chosen units
  
  # add arrows to plots
  # YZ
  arYZu = [ar[1] for ar in arYZ]
  arYZv = [ar[2] for ar in arYZ]
  CairoMakie.arrows!(axYZ, NN[2], NN[3], arYZu, arYZv, 
		     color=:white, linewidth=1, arrowsize = 6, lengthscale = 0.1*al)
  # XZ
  arXZu = [ar[1] for ar in arXZ]
  arXZv = [ar[2] for ar in arXZ]
  CairoMakie.arrows!(axXZ, NN[1], NN[3], arXZu, arXZv, 
		     color=:white, linewidth=1, arrowsize = 6, lengthscale = 0.1*al)
  # XY
  arXYu = [ar[1] for ar in arXY]
  arXYv = [ar[2] for ar in arXY]
  CairoMakie.arrows!(axXY, NN[2], NN[1], arXYu', arXYv', 
		     color=:white, linewidth=1, arrowsize = 6, lengthscale = 0.1*al)

  # set fontsize
  fs = get_gtk_property(m["adjFontsize"],:value, Int64) # fontsize
  CairoMakie.set_theme!(CairoMakie.Theme(fontsize = fs)) # set fontsize for the whole plot

  # Show slices
  if get_gtk_property(m["cbShowSlices"], :active, Bool)
    # draw lines to mark 0
    intersec = useMilli ? intersection .*1000 : intersection # scale intersection to the chosen unit
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
    if m.fv.centerFFP && m.coeffs.ffp != nothing
      CairoMakie.lines!(axYZ, rr[:,1].-ffp[2,m.patch], rr[:,2].-ffp[3,m.patch], 
			color=:white, linestyle=:dash, linewidth=1)
      CairoMakie.lines!(axXZ, rr[:,1].-ffp[1,m.patch], rr[:,2].-ffp[3,m.patch], 
			color=:white, linestyle=:dash, linewidth=1)
      CairoMakie.lines!(axXY, rr[:,1].-ffp[2,m.patch], rr[:,2].-ffp[1,m.patch], 
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
end

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
