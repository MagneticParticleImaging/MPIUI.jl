
mutable struct RobotWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  updating::Bool
  robot::Robot
end

getindex(m::RobotWidget, w::AbstractString) = G_.object(m.builder, w)



function RobotWidget(robot::Robot)
  uifile = joinpath(@__DIR__,"..","builder","robotWidget.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "mainBox")

  m = RobotWidget(mainBox.handle, b, false,robot)
  Gtk.gobject_move_ref(m, mainBox)

  initCallbacks(m)

  return m
end

function initCallbacks(m::RobotWidget)

    signal_connect(m["btnRobotMove"], :clicked) do w
        robotMove(m)
    end

    signal_connect(m["btnMovePark"], :clicked) do w
        try
            movePark(m)
        catch ex
            showError(ex)
        end
    end

    signal_connect(m["btnMoveAssemblePos"], :clicked) do w
        moveAssemblePos(m)
    end

    signal_connect(m["btnReferenceDrive"], :clicked) do w
        referenceDrive(m)
    end  
end




function enableRobotMoveButtons(m::RobotWidget, enable::Bool)
    @idle_add begin
      set_gtk_property!(m["btnRobotMove"],:sensitive,enable)
      set_gtk_property!(m["btnMoveAssemblePos"],:sensitive,enable)
      set_gtk_property!(m["btnMovePark"],:sensitive,enable)
      #set_gtk_property!(m["tbCalibration"],:sensitive,enable)
    end
  end
  

function robotMove(m::RobotWidget)
    if !isReferenced(m.robot)
        info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
    return
    end

    posString = get_gtk_property(m["entCurrPos",EntryLeaf], :text, String)
    pos_ = tryparse.(Float64,split(posString,"x"))

    if any(pos_ .== nothing) || length(pos_) != 3
    return
    end
    pos = pos_.*1Unitful.mm
    try
    @info "enabeling robot"
    setEnabled(m.robot, true)
    @info "move robot"
    #moveAbs(m.robot,getRobotSetupUI(m), pos)
    @info "move robot done"
    catch ex
    showError(ex)
    end
    #infoMessage(m, "move to $posString")
end
  
  
function MPIMeasurements.movePark(m::RobotWidget)
    if !isReferenced(m.robot)
        info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
        return
    end
    setEnabled(m.robot, true)
    movePark(m.robot)
    enableRobotMoveButtons(m, true)
end
  
function moveAssemblePos(m::RobotWidget)
    if !isReferenced(m.robot)
        info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
        return
    end
    moveAssemble(m.robot)
    @idle_add set_gtk_property!(m["btnRobotMove"],:sensitive,false)
    #@idle_add set_gtk_property!(m["tbCalibration"],:sensitive,false)
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
            prepareRobot(robot)
            message = """The robot is now referenced.
                You can mount your sample. Press \"Close\" to proceed. """
            info_dialog(message, mpilab[]["mainWindow"])
            enableRobotMoveButtons(m,true)
            @idle_add set_gtk_property!(m["btnReferenceDrive"],:sensitive,false)
        end
    end
end
end
  
