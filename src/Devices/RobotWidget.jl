
mutable struct RobotWidget <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  updating::Bool
  robot::Robot
  timer::Union{Timer, Nothing}
  coordTransferfunction::Function
  coordType::Union{Type{ScannerCoords}, Type{RobotCoords}}
  namedPos::Union{String, Nothing}
end

getindex(m::RobotWidget, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)


#TODO make usable for different dof
function RobotWidget(robot::Robot)
  uifile = joinpath(@__DIR__,"..","builder","robotWidget.ui")

  b = GtkBuilder(uifile)
  mainBox = Gtk4.G_.get_object(b, "mainBox")

  m = RobotWidget(mainBox.handle, b, false, robot, nothing, toScannerCoords, ScannerCoords, nothing)
  Gtk4.GLib.gobject_move_ref(m, mainBox)

  if :namedPositions in fieldnames(typeof(params(robot)))
    @idle_add_guarded begin
      for pos in keys(namedPositions(robot))
        push!(m["cmbNamedPos"], pos)
        set_gtk_property!(m["cmbNamedPos"], :active, 1)
      end
      set_gtk_property!(m["cmbNamedPos"], :sensitive, true)
      set_gtk_property!(m["btnMoveNamedPos"], :sensitive, true)
      displayNamedPosition(m)
    end
  end

  @idle_add_guarded begin
    displayAxisRange(m)
  end

  initCallbacks(m)

  return m
end

function initCallbacks(m::RobotWidget)

  signal_connect(m["tglWatchRobotState"], :toggled) do w
    if !get_gtk_property(w, :active, Bool)
      if !isnothing(m.timer)
        close(m.timer)
        m.timer = nothing
      end
    else 
      m.timer = Timer(displayRobotState(m), 0.0, interval = 0.1)
    end
  end

  signal_connect(m["btnResetRobot"], :clicked) do w
    try
      resetRobot(m)
    catch ex
      showError(ex)
    end
  end

  signal_connect(m["btnRobotMove"], :clicked) do w
    try
      robotMove(m)
    catch ex
      showError(ex)
    end
  end

  signal_connect(m["btnReferenceDrive"], :clicked) do w
    try
      referenceDrive(m)
    catch ex
      showError(ex)
    end
  end

  signal_connect(m["btnScannerOrigin"], :clicked) do w
    try 
      moveScannerOrigin(m)
    catch ex
      showError(ex)
    end
  end 
  
  signal_connect(m["cmbNamedPos"], :changed) do w
    displayNamedPosition(m)
  end

  signal_connect(m["btnMoveNamedPos"], :clicked) do w
    try 
      moveNamedPosition(m, m.namedPos)
    catch ex
      showError(ex)
    end
  end

  signal_connect(m["radScannerCoord"], :toggled) do w
    if get_gtk_property(w, :active, Bool)
      m.coordTransferfunction = toScannerCoords
      updatePositionCoords(m, toScannerCoords, m.coordType)
      m.coordType = ScannerCoords
    end
  end

  signal_connect(m["radRobotCoord"], :toggled) do w
    if get_gtk_property(w, :active, Bool)
      m.coordTransferfunction = toRobotCoords
      updatePositionCoords(m, toRobotCoords, m.coordType)
      m.coordType = RobotCoords
    end
  end

  # TODO implement Name Position button

end

function displayRobotState(m::RobotWidget)
  @idle_add_guarded begin
    set_gtk_property!(m["lblRobotState"], :label, string(state(m.robot)))
  end
end

function floatToPos(m::RobotWidget, posFloat::Vector{Float64})
  return floatToPos(m, posFloat, m.coordType)
end
function floatToPos(m::RobotWidget, posFloat::Vector{Float64}, type::Union{Type{ScannerCoords}, Type{RobotCoords}})
  if length(posFloat) != 3
      return
  end
  pos = posFloat.*1Unitful.mm
  return type(pos)
end

function currentPosition(m::RobotWidget, type=m.coordType)
  entryX = get_gtk_property(m["entCurrPosX"], :text, String)
  entryY = get_gtk_property(m["entCurrPosY"], :text, String)
  entryZ = get_gtk_property(m["entCurrPosZ"], :text, String)
  posFloat = tryparse.(Float64, [entryX, entryY, entryZ])
  return any(isnothing, posFloat) ? nothing : floatToPos(m, posFloat, type)
end

# Always used current robotwidget type
function movePosition(m::RobotWidget)
  entryX = get_gtk_property(m["entMovePosX"], :text, String)
  entryY = get_gtk_property(m["entMovePosY"], :text, String)
  entryZ = get_gtk_property(m["entMovePosZ"], :text, String)
  posFloat = tryparse.(Float64, [entryX, entryY, entryZ])
  return any(isnothing, posFloat) ? nothing : floatToPos(m, posFloat)
end

function namedPosition(m::RobotWidget, type=m.coordType)
  entryX = get_gtk_property(m["entNamedPosX"], :text, String)
  entryY = get_gtk_property(m["entNamedPosY"], :text, String)
  entryZ = get_gtk_property(m["entNamedPosZ"], :text, String)
  posFloat = tryparse.(Float64, [entryX, entryY, entryZ])
  return any(isnothing, posFloat) ? nothing : floatToPos(m, posFloat, type)
end

function displayNamedPosition(m::RobotWidget, pos::Nothing)
  # NOP
end
function displayNamedPosition(m::RobotWidget, pos)
  @idle_add_guarded begin
    set_gtk_property!(m["entNamedPosX"], :text, string(ustrip(u"mm", pos[1])))
    set_gtk_property!(m["entNamedPosY"], :text, string(ustrip(u"mm", pos[2])))
    set_gtk_property!(m["entNamedPosZ"], :text, string(ustrip(u"mm", pos[3])))
  end
end
function displayNamedPosition(m::RobotWidget)
  #m.namedPos = Gtk4.bytestring(Gtk4.active_text(m["cmbNamedPos"]))
  m.namedPos = Gtk4.active_text(m["cmbNamedPos"])

  if m.namedPos != nothing
    pos = m.coordTransferfunction(m.robot, MPIMeasurements.namedPosition(m.robot, m.namedPos))
    @show pos
    if length(pos) == 3
      displayNamedPosition(m, pos)
    end
  end
end

function displayCurrentPosition(m::RobotWidget, pos::Nothing)
  # NOP
end
function displayCurrentPosition(m::RobotWidget, pos)
  @idle_add_guarded begin
    set_gtk_property!(m["entCurrPosX"], :text, string(ustrip(u"mm", pos[1])))
    set_gtk_property!(m["entCurrPosY"], :text, string(ustrip(u"mm", pos[2])))
    set_gtk_property!(m["entCurrPosZ"], :text, string(ustrip(u"mm", pos[3])))
  end
end
function displayCurrentPosition(m::RobotWidget)
  pos = m.coordTransferfunction(m.robot, getPosition(m.robot))
  displayCurrentPosition(m, pos)
end

function displayAxisRange(m::RobotWidget)
  tempRanges = axisRange(m.robot)
  # adapt for other dof
  minPos = m.coordTransferfunction(m.robot, RobotCoords([tempRanges[i][1] for i = 1:3]))
  maxPos = m.coordTransferfunction(m.robot, RobotCoords([tempRanges[i][2] for i = 1:3]))
  ranges = [[minPos[i], maxPos[i]] for i = 1:3]
  set_gtk_property!(m["entRangeX"], :text, string(ustrip.(u"mm", ranges[1])))
  set_gtk_property!(m["entRangeY"], :text, string(ustrip.(u"mm", ranges[2])))
  set_gtk_property!(m["entRangeZ"], :text, string(ustrip.(u"mm", ranges[3])))
  set_gtk_property!(m["entMoveOrder"], :text, MPIMeasurements.movementOrder(m.robot))
end

function updatePositionCoords(m::RobotWidget, transferNewType::Function, oldType::Union{Type{ScannerCoords}, Type{RobotCoords}})
  @idle_add_guarded begin
    currPosOld = currentPosition(m, oldType)
    if !isnothing(currPosOld)
      currPosNew = transferNewType(m.robot, currPosOld)
      displayCurrentPosition(m, currPosNew)
    end
    namedPosOld = namedPosition(m, oldType)
    @show namedPosOld
    if !isnothing(namedPosOld)
      namedPosNew = transferNewType(m.robot, namedPosOld)
      displayNamedPosition(m, namedPosNew)
    end
    displayAxisRange(m)
  end
end


function resetRobot(m::RobotWidget)
  robot = m.robot 
  reset(robot)
  setup(robot)
  @idle_add_guarded set_gtk_property!(m["btnReferenceDrive"],:sensitive, !isReferenced(robot))
end

function enableRobotMoveButtons(m::RobotWidget, enable::Bool)
    @idle_add_guarded begin
      set_gtk_property!(m["btnRobotMove"],:sensitive,enable)
      set_gtk_property!(m["btnMoveNamedPos"], :sensitive, enable)
    end
end
  
function robotMove(m::RobotWidget)
  if !isReferenced(m.robot)
    d = info_dialog(()->nothing, "Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
    d.modal = true
    return
  end

  pos = movePosition(m)
  if !isnothing(pos)
    @info "enabeling robot"
    enable(m.robot)
    @info "move robot"
    moveAbs(m.robot, pos)
    @info "move robot done"
    disable(m.robot)
    displayCurrentPosition(m)
  end
end

function moveNamedPosition(m::RobotWidget, posName::String)
  if !isReferenced(m.robot)
    d = info_dialog(()-> nothing, "Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
    d.modal = true
    return
  end
  @info "enabeling robot"
  enable(m.robot)
  @info "move robot"
  MPIMeasurements.gotoPos(m.robot, posName)
  @info "move robot done"
  disable(m.robot)
  displayCurrentPosition(m)
end

function moveScannerOrigin(m::RobotWidget)
  if !isReferenced(m.robot)
    d = info_dialog(()-> nothing, "Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
    d.modal = true
    return
  end
  @info "enabeling robot"
  enable(m.robot)
  @info "move robot"
  MPIMeasurements.moveScannerOrigin(m.robot)
  @info "move robot done"
  disable(m.robot)
  displayCurrentPosition(m)
end

function referenceDrive(m::RobotWidget)
  robot = m.robot
  message = """ Remove all attached devices from the robot before the robot will be referenced and move around!\n
          Press \"Ok\" if you have done so """
  ask_dialog(message, "Cancel", "Ok", mpilab[]["mainWindow"]) do answer1
    if answer1
      message = """Are you sure you have removed everything and the robot can move
            freely without damaging anything? Press \"Ok\" if you want to continue"""
      ask_dialog(message, "Cancel", "Ok", mpilab[]["mainWindow"]) do answer2
        if answer2
          @info "Enable Robot"
          enable(robot)
          @info "Do reference drive"
          doReferenceDrive(robot)
          if in("park", keys(namedPositions(m.robot)))
            moveNamedPosition(m, "park")
          end
          @info "Disable Robot"
          disable(robot)
          message = """The robot is now referenced.
              You can mount your sample. Press \"Close\" to proceed. """
          info_dialog(message, mpilab[]["mainWindow"]) do 
            displayCurrentPosition(m)
            enableRobotMoveButtons(m, true)            
          end
        end
      end
    end
  end
end
  
