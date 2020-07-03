
function doCalibration(m::MeasurementWidget)
    shpString = get_gtk_property(m["entGridShape",EntryLeaf], :text, String)
    shp_ = tryparse.(Int64,split(shpString,"x"))
    fovString = get_gtk_property(m["entFOV",EntryLeaf], :text, String)
    fov_ = tryparse.(Float64,split(fovString,"x"))
    centerString = get_gtk_property(m["entCenter",EntryLeaf], :text, String)
    center_ = tryparse.(Float64,split(centerString,"x"))

    velRobString = get_gtk_property(m["entVelRob",EntryLeaf], :text, String)
    velRob_ = tryparse.(Int64,split(velRobString,"x"))

    numBGMeas = get_gtk_property(m["adjNumBGMeasurements",AdjustmentLeaf], :value, Int64)

    if any(shp_ .== nothing) || any(fov_ .== nothing) || any(center_ .== nothing) || any(velRob_ .== nothing) ||
       length(shp_) != 3 || length(fov_) != 3 || length(center_) != 3 || length(velRob_) != 3
      @idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
      return
    end

    shp = shp_
    fov = fov_ .*1Unitful.mm
    ctr = center_ .*1Unitful.mm
    velRob = velRob_

    if get_gtk_property(m["cbUseArbitraryPos",CheckButtonLeaf], :active, Bool) == false
        cartGrid = RegularGridPositions(shp,fov,ctr)#
    else
        filename = get_gtk_property(m["entArbitraryPos"],EntryLeaf,:text,String)
        if filename != ""
            cartGrid = h5open(filename, "r") do file
                positions = Positions(file)
            end
        else
          error("Filename Arbitrary Positions empty!")
        end
    end
    if numBGMeas == 0
      positions = cartGrid
    else
      bgIdx = round.(Int64, range(1, stop=length(cartGrid)+numBGMeas, length=numBGMeas ) )
      bgPos = parkPos(getRobot(m.scanner))
      positions = BreakpointGridPositions(cartGrid, bgIdx, bgPos)
    end

    for pos in positions
      isValid = checkCoords(getRobotSetupUI(m), pos, getMinMaxPosX(getRobot(m.scanner)))
    end

    params = merge!(getGeneralParams(m.scanner),getParams(m))
    calibObj = SystemMatrixRobotMeas(m.scanner, getRobotSetupUI(m), positions, params,
              waitTime = get_gtk_property(m["adjPause",AdjustmentLeaf],:value,Float64))

    # the following spawns a task
    @info "perform calibration"
    calibState = startCalibration(m.calibState, calibObj, m.mdfstore, params)

    @idle_add set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,true)
    #@idle_add set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf],:sensitive,false)
    @idle_add set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,false)

end

function displayCalibration(m::MeasurementWidget, timerCalibration::Timer)
  try
      calibState = m.calibState
      positions = calibState.calibObj.positions

      if calibState.calibrationActive
        if 1 <= calibState.currPos <= calibState.numPos
            pos = Float64.(ustrip.(uconvert.(Unitful.mm, positions[calibState.currPos])))
            posStr = @sprintf("%.2f x %.2f x %.2f", pos[1],pos[2],pos[3])
            infoMessage(m, "$(calibState.currPos) / $(calibState.numPos) ($posStr mm)", "green")

            daq = calibState.calibObj.daq
            deltaT = daq.params.dfCycle / daq.params.numSampPerPeriod
            if !calibState.consumed && !isempty(calibState.currentMeas)
              uMeas = calibState.currentMeas
              updateData(m.rawDataWidget, uMeas, deltaT)
              calibState.consumed = true
            end

            #Lauft nicht

            #temp = getTemperatures(su)
            #while maximum(temp[1:2]) > params["maxTemperature"]
            # infoMessage(m, "System Cooling Down! $(calibState.currPos) / $(calibState.numPos) ($posStr mm)", "red")
            # sleep(20)
            # temp = getTemperatures(su)
            # @info "Temp = $temp"
            #end
          end

          if istaskdone(calibState.task)
            infoMessage(m, "", "red")
            @idle_add begin
              set_gtk_property!(m["tbCalibration",ToggleToolButtonLeaf], :active, false)
              set_gtk_property!(m["tbCancel",ToolButtonLeaf],:sensitive,false)
              set_gtk_property!(m["btnRobotMove",ButtonLeaf],:sensitive,true)
            end

            close(timerCalibration)

            updateData!(mpilab[].sfBrowser, m.mdfstore)
            updateExperimentStore(mpilab[], mpilab[].currentStudy)
            return false
          end
      end
      sleep(0.1)
    catch ex
      close(timerCalibration)
      showError(ex)
    end
end
