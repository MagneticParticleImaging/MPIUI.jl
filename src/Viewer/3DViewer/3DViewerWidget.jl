mutable struct DataViewer3DWidget{A, C} <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  lscene::LScene
  scene::Scene
  axis::A
  cam::C
  gm::Gtk4Makie.GtkGLMakie
  # Controls
  controlGrid::GtkGrid
  modeCb::GtkComboBoxText
  modeOpt::GtkMenuButton
  frameAdj::GtkAdjustment
  cmapCb::GtkComboBoxText
  # Data
  data::AbstractArray
  # Mode
  modes::Vector{<:Abstract3DViewerMode}
end

function DataViewer3DWidget(; modes = [VolumeMode, SectionalMode])
  grid = GtkGrid()
  handle = grid.handle

  # Setup the controls
  controls = GtkGrid()

  # Mode selection
  # We have to initialize the modeBox and the options later
  # Once the viewer exits we can initialize the modes with the viewer as parent
  # And then fill out our options
  modeBox = GtkComboBoxText()
  controls[1, 1] = GtkLabel("Mode")
  controls[1, 2] = modeBox
  modeOptions = GtkMenuButton()
  controls[2, 2] = modeOptions
  controls[3, 1:2] = GtkSeparator(:v)

  # Frame/Time Selection
  frameAdj = GtkAdjustment(1, 1, 1, 1, 1, 1)
  frameSlider = GtkSpinButton(frameAdj, 1, 0)
  controls[4, 1] = GtkLabel("Frames")
  controls[4, 2] = frameSlider
  controls[5, 1:2] = GtkSeparator(:v)
  
  # Colormap Selection
  colormapBox = GtkComboBoxText()
  cmaps =  ["foo"]#important_colormaps()
  foreach(cm -> push!(colormapBox, cm), cmaps)
  controls[6, 1] = GtkLabel("Colormap")
  controls[6, 2] = colormapBox

  grid[1, 1] = controls

  # Setup the 3D viewing widget
  fig = Figure()
  lscene = LScene(fig[1,1])
  scene = lscene.scene
  cam = scene.camera_controls
  axis = first(scene.plots) # Initial plot is an axis for LScene
  gm = GtkMakieWidget()
  push!(gm, fig)

  grid[1, 2] = gm

  viewer = DataViewer3DWidget(handle, lscene, scene, axis, cam, gm, controls, modeBox, modeOptions, frameAdj, colormapBox, [], Abstract3DViewerMode[])

  # Initialize the modes
  modes = map(mode -> mode(viewer), modes)
  for mode in modes
    push!(modeBox, modeName(mode))
  end
  modeBox.active = 0
  modeOptions.popover = popover(first(modes))
  viewer.modes = modes

  initCallbacks(viewer)

  return viewer
end

function initCallbacks(m::DataViewer3DWidget)
  signal_connect(m.modeCb, "changed") do widget
    @show m.modeCb.active
    m.modeOpt.popover = popover(m.modes[m.modeCb.active + 1])
    showData!(WidgetRedraw(), m)
  end
#
  #signal_connect(m.frameAdj, "value-changed") do widget
  #  showData!(m)
  #end
#
  #signal_connect(m.cmapCb, "changed") do widget
  #  showData!(m)
  #end
end


function updateData!(m::DataViewer3DWidget, file::Union{MDFFile, String})
  imMeta = loadRecoData(file)
  updateData!(m, imMeta)
end

# TODO handle 3 and 4 dim ImageMeta
function updateData!(m::DataViewer3DWidget, imMeta::ImageMeta{T, 5}) where T
  m.data = imMeta
  map(mode -> updateData!(mode, m.data), m.modes)
  showData!(WidgetRedraw(), m)
end

function updateData!(m::DataViewer3DWidget, array::AbstractArray{T, 5}) where T
  m.data = array
  map(mode -> updateData!(mode, m.data), m.modes)
  showData!(WidgetRedraw(), m)
end

showData!(m::DataViewer3DWidget) = showData!(redrawType(m.modes[m.modeCb.active + 1]), m)

function showData!(::WidgetRedraw, m::DataViewer3DWidget)
  # Prepare new GtkMakieWidget
  delete!(m, m[1, 2])
  m.gm = GtkMakieWidget()
  m[1, 2] = m.gm
  
  mode = m.modes[m.modeCb.active + 1]
  frame = round(Int64, m.frameAdj.value)
  data = ustrip.(m.data[1, :, :, :, frame])
  
  lscene = showData!(m.gm, mode, data)

  m.lscene = lscene
  m.scene = lscene.scene
  m.axis = first(m.scene.plots)

  # Set the camera to the old position
  eyeposition = m.cam.eyeposition[]
  upvector = m.cam.upvector[]
  lookat = m.cam.lookat[]
  m.cam = m.scene.camera_controls
  update_cam!(m.scene, eyeposition, lookat, upvector)
  return nothing
end

function showData!(re::ObservableRedraw, m::DataViewer3DWidget)
  # TODO move these into a function
  mode = m.modes[m.modeCb.active + 1]
  frame = round(Int64, m.frameAdj.value)
  data = ustrip.(m.data[1, :, :, :, frame])
  showData!(re, m.lscene, mode, data)
  return nothing
end
