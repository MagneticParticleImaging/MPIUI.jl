
mutable struct RobotWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  updating::Bool
  robot::Robot
  timer::Union{Timer, Nothing}
  namedPos::Union{String, Nothing}
end

getindex(m::RobotWidget, w::AbstractString) = G_.object(m.builder, w)



function RobotWidget(robot::Robot)
  uifile = joinpath(@__DIR__,"..","builder","robotWidget.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "mainBox")

  m = RobotWidget(mainBox.handle, b, false, robot, nothing, nothing)
  Gtk.gobject_move_ref(m, mainBox)

  if :namedPositions in fieldnames(typeof(params(robot)))
    @idle_add begin
      for pos in keys(namedPositions(robot))
        push!(m["cmbNamedPos"], pos)
        set_gtk_property!(m["cmbNamedPos"], :active, 1)
      end
      set_gtk_property!(m["cmbNamedPos"], :sensitive, true)
      set_gtk_property!(m["btnMoveNamedPos"], :sensitive, true)
    end
  end

  @idle_add begin
    ranges = axisRange(m.robot)
    # adapt for other dof
    set_gtk_property!(m["entRangeX"], :text, string(ustrip.(u"mm", ranges[1])))
    set_gtk_property!(m["entRangeY"], :text, string(ustrip.(u"mm", ranges[2])))
    set_gtk_property!(m["entRangeZ"], :text, string(ustrip.(u"mm", ranges[3])))
    set_gtk_property!(m["entMoveOrder"], :text, MPIMeasurements.movementOrder(m.robot))
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

  signal_connect(m["btnRobotMove"], :clicked) do w
    try
      robotMove(m)
    catch ex
      showError(ex)
    end
  end

  signal_connect(m["btnReferenceDrive"], :clicked) do w
      referenceDrive(m)
  end
  
  signal_connect(m["cmbNamedPos"], :changed) do w
    @idle_add begin
      m.namedPos = Gtk.bytestring(GAccessor.active_text(m["cmbNamedPos"]))
      pos = namedPosition(m.robot, m.namedPos)
      if length(pos) == 3
        @idle_add begin
          set_gtk_property!(m["entNamedPosX"], :text, string(ustrip(u"mm", pos[1])))
          set_gtk_property!(m["entNamedPosY"], :text, string(ustrip(u"mm", pos[2])))
          set_gtk_property!(m["entNamedPosZ"], :text, string(ustrip(u"mm", pos[3])))
        end
      end
    end
  end

  signal_connect(m["btnMoveNamedPos"], :clicked) do w
    try 
      moveNamedPosition(m, m.namedPos)
    catch ex
      showError(ex)
    end
  end
end

function displayRobotState(m::RobotWidget)
  @idle_add begin
    set_gtk_property!(m["lblRobotState"], :label, string(state(m.robot)))
  end
end

function displayPosition(m::RobotWidget)
  @idle_add begin
    pos = getPosition(m.robot)
    set_gtk_property!(m["entCurrPosX"], :text, string(ustrip(u"mm", pos[1])))
    set_gtk_property!(m["entCurrPosY"], :text, string(ustrip(u"mm", pos[2])))
    set_gtk_property!(m["entCurrPosZ"], :text, string(ustrip(u"mm", pos[3])))
  end
end


function enableRobotMoveButtons(m::RobotWidget, enable::Bool)
    @idle_add begin
      set_gtk_property!(m["btnRobotMove"],:sensitive,enable)
      set_gtk_property!(m["btnMoveNamedPos"], :sensitive, enable)
    end
end
  
function robotMove(m::RobotWidget)
  if !isReferenced(m.robot)
      info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
  return
  end

  entryX = get_gtk_property(m["entMovePosX"], :text, String)
  entryY = get_gtk_property(m["entMovePosY"], :text, String)
  entryZ = get_gtk_property(m["entMovePosZ"], :text, String)
  posFloat = tryparse.(Float64, [entryX, entryY, entryZ])

  if any(posFloat .== nothing) || length(posFloat) != 3
      return
  end
  pos = posFloat.*1Unitful.mm
  @info "enabeling robot"
  enable(m.robot)
  @info "move robot"
  moveAbs(m.robot, pos)
  @info "move robot done"
  disable(m.robot)
  displayPosition(m)
end

function moveNamedPosition(m::RobotWidget, posName::String)
  if !isReferenced(m.robot)
    info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
    return
  end
  @info "enabeling robot"
  enable(m.robot)
  @info "move robot"
  MPIMeasurements.gotoPos(m.robot, posName)
  @info "move robot done"
  disable(m.robot)
  displayPosition(m)
end
  

function referenceDrive(m::RobotWidget)
  robot = m.robot
  if !isReferenced(robot)
    message = """IselRobot is NOT referenced and needs to be referenced! \n
            Remove all attached devices from the robot before the robot will be referenced and move around!\n
            Press \"Ok\" if you have done so """
    if ask_dialog(message, "Cancel", "Ok", mpilab[]["mainWindow"])
      message = """Are you sure you have removed everything and the robot can move
            freely without damaging anything? Press \"Ok\" if you want to continue"""
      if ask_dialog(message, "Cancel", "Ok", mpilab[]["mainWindow"])
        enable(robot)
        doReferenceDrive(robot)
        disable(robot)
        displayPosition(m)
        message = """The robot is now referenced.
            You can mount your sample. Press \"Close\" to proceed. """
        info_dialog(message, mpilab[]["mainWindow"])
        enableRobotMoveButtons(m,true)
        @idle_add set_gtk_property!(m["btnReferenceDrive"],:sensitive,false)
      end
    end
  end
end
  
