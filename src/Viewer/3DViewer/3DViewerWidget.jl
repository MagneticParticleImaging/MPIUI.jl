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
  channelAdj::GtkAdjustment
  cmapCb::GtkComboBoxText
  cmin::GtkScaleButton
  cmax::GtkScaleButton
  # Data
  data::AbstractArray
  # Mode
  modes::Vector{<:Abstract3DViewerMode}
end

function DataViewer3DWidget(; modes = [VolumeMode, SectionalMode, IsoSurfaceMode])
  grid = GtkGrid()
  handle = grid.handle

  # Setup the controls
  controls = GtkGrid()
  controls.column_spacing = 5
  controls.row_spacing = 5

  # Mode selection
  # We have to initialize the modeBox and the options later
  # Once the viewer exits we can initialize the modes with the viewer as parent
  # And then fill out our options
  modeBox = GtkComboBoxText()
  controls[1, 1] = GtkLabel("Mode")
  controls[1, 2] = modeBox
  modeOptions = GtkMenuButton()
  controls[2, 1] = GtkLabel("Options")
  controls[2, 2] = modeOptions
  controls[3, 1:2] = GtkSeparator(:v)

  # Frame/Time Selection
  frameAdj = GtkAdjustment(1, 1, 1, 1, 1, 1)
  frameSlider = GtkSpinButton(frameAdj, 1, 0)
  controls[4, 1] = GtkLabel("Frames")
  controls[4, 2] = frameSlider
  channelAdj = GtkAdjustment(1, 1, 1, 1, 1, 1)
  channelSlider = GtkSpinButton(channelAdj, 1, 0)
  controls[5, 1] = GtkLabel("Channels")
  controls[5, 2] = channelSlider
  controls[6, 1:2] = GtkSeparator(:v)
  
  # Colormap Selection
  colormapBox = GtkComboBoxText()
  cmaps =  important_cmaps()
  foreach(cm -> push!(colormapBox, cm), cmaps)
  controls[7, 1] = GtkLabel("Colormap")
  controls[7, 2] = colormapBox
  colormapBox.active = 5 # viridis
  cmin = GtkScaleButton(0, 99, 1, ["audio-volume-low"])
  cmax = GtkScaleButton(1, 100, 1, ["audio-volume-high"])
  cmin.value = 0
  cmax.value = 100
  controls[8, 1] = GtkLabel("Min")
  controls[8, 2] = cmin
  controls[9, 1] = GtkLabel("Max")
  controls[9, 2] = cmax

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

  viewer = DataViewer3DWidget(handle, lscene, scene, axis, cam, gm, controls, modeBox, modeOptions, frameAdj, channelAdj, colormapBox, cmin, cmax, [], Abstract3DViewerMode[])

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
    foreach(mode -> mode.active = false, m.modes)
    mode = m.modes[m.modeCb.active + 1]
    mode.active = true
    m.modeOpt.popover = popover(mode)
    showData!(WidgetRedraw(), m)
  end

  signal_connect(m.frameAdj, "value_changed") do widget
    showData!(m)
  end
  signal_connect(m.channelAdj, "value_changed") do widget
    showData!(m)
  end

  signal_connect(m.cmapCb, "changed") do widget
    showData!(m)
  end

  signal_connect(m.cmin, "value_changed") do widget, val
    showData!(m)
  end
  signal_connect(m.cmax, "value_changed") do widget, val
    showData!(m)
  end
end


function updateData!(m::DataViewer3DWidget, file::Union{MDFFile, String})
  imMeta = loadRecoData(file)
  updateData!(m, imMeta)
end

# TODO handle 3 and 4 dim ImageMeta
function updateData!(m::DataViewer3DWidget, imMeta::ImageMeta{T, 5}) where T
  m.data = imMeta
  m.frameAdj.upper = size(m.data, 5)
  m.channelAdj.upper = size(m.data, 1)
  map(mode -> updateData!(mode, m.data), m.modes)
  showData!(WidgetRedraw(), m)
end

function updateData!(m::DataViewer3DWidget, array::AbstractArray{T, 5}) where T
  m.data = array
  m.frameAdj.upper = size(m.data, 5)
  m.channelAdj.upper = size(m.data, 1)
  m.cmin = 0
  m.cmax = 100
  map(mode -> updateData!(mode, m.data), m.modes)
  showData!(WidgetRedraw(), m)
end

function prepareData(m::DataViewer3DWidget)
  frame = round(Int64, m.frameAdj.value)
  channel = round(Int64, m.channelAdj.value)
  data = ustrip.(m.data[channel, :, :, :, frame])
  return data
end

function prepareDrawKwargs(m::DataViewer3DWidget)
  dict = Dict{Symbol, Any}()
  max = maximum(m.data)
  cmin = (m.cmin.value/100) * max
  cmax = (m.cmax.value/100) * max
  dict[:cparams] = ColoringParams(cmin, cmax, Gtk4.active_text(m.cmapCb))
  return dict
end

showData!(m::DataViewer3DWidget) = showData!(redrawType(m.modes[m.modeCb.active + 1]), m)

function showData!(::WidgetRedraw, m::DataViewer3DWidget)
  # Prepare new GtkMakieWidget
  delete!(m, m[1, 2])
  m.gm = GtkMakieWidget()
  m[1, 2] = m.gm
  
  mode = m.modes[m.modeCb.active + 1]
  data = prepareData(m)  
  kwargs = prepareDrawKwargs(m)
  lscene = showData!(m.gm, mode, data; kwargs...)

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
  data = prepareData(m)
  kwargs = prepareDrawKwargs(m)
  showData!(re, m.lscene, mode, data; kwargs...)
  return nothing
end
