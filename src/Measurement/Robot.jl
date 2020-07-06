
function enableRobotMoveButtons(m::MeasurementWidget, enable::Bool)
  @idle_add begin
    set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,enable)
    set_gtk_property!(m["btnMoveAssemblePos",ButtonLeaf],:sensitive,enable)
    set_gtk_property!(m["btnMovePark",ButtonLeaf],:sensitive,enable)
    set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,enable)
  end
end

function robotMove(m::MeasurementWidget)
    if !isReferenced(getRobot(m.scanner))
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
      setEnabled(getRobot(m.scanner), true)
      @info "move robot"
      moveAbs(getRobot(m.scanner),getRobotSetupUI(m), pos)
      @info "move robot done"
    catch ex
      showError(ex)
    end
    #infoMessage(m, "move to $posString")
end

function loadArbPos(m::MeasurementWidget)
      filter = Gtk.GtkFileFilter(pattern=String("*.h5"), mimetype=String("HDF5 File"))
      filename = open_dialog("Select Arbitrary Position File", GtkNullContainer(), (filter, ))
      @idle_add set_gtk_property!(m["entArbitraryPos",EntryLeaf],:text,filename)
end

function MPIMeasurements.movePark(m::MeasurementWidget)
      if !isReferenced(getRobot(m.scanner))
        info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
        return
      end
      setEnabled(getRobot(m.scanner), true)
      movePark(getRobot(m.scanner))
      enableRobotMoveButtons(m, true)
end

function moveAssemblePos(m::MeasurementWidget)
      if !isReferenced(getRobot(m.scanner))
        info_dialog("Robot not referenced! Cannot proceed!", mpilab[]["mainWindow"])
        return
      end
      moveAssemble(getRobot(m.scanner))
      @idle_add set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,false)
      @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,false)
end

function referenceDrive(m::MeasurementWidget)
    robot = getRobot(m.scanner)
    if !isReferenced(robot)
      message = """IselRobot is NOT referenced and needs to be referenced! \n
             Remove all attached devices from the robot before the robot will be referenced and move around!\n
             Press \"Ok\" if you have done so """
      if ask_dialog(message, "Cancle", "Ok", mpilab[]["mainWindow"])
          message = """Are you sure you have removed everything and the robot can move
            freely without damaging anything? Press \"Ok\" if you want to continue"""
         if ask_dialog(message, "Cancle", "Ok", mpilab[]["mainWindow"])
            prepareRobot(robot)
            message = """The robot is now referenced.
               You can mount your sample. Press \"Close\" to proceed. """
            info_dialog(message, mpilab[]["mainWindow"])
            enableRobotMoveButtons(m,true)
            @idle_add set_gtk_property!(m["btnReferenceDrive",ButtonLeaf],:sensitive,false)
       end
    end
  end
end
