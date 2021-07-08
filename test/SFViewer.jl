@testset "SFViewer" begin
    # Download data
    pathSF = joinpath(calibdir(datasetstore),"1.mdf")
    download_("calibrations/17.mdf", pathSF)

    # Start SFViewer
    s = SFViewer(pathSF)
    sleep(35)
    sf = s.sf     # SFViewerWidget
    dv = s.sf.dv  # DataViewerWidget

    ## Test frequency selections
    @testset "Frequency selection" begin
        # freq and patch
        set_gtk_property!(sf["adjSFFreq"],:value, 3)
        set_gtk_property!(sf["adjSFPatch"],:value, 5)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/adjSFFreqPatch.png")
        @testImg("adjSFFreqPatch.png")

        # Receive channel
        set_gtk_property!(sf["adjSFRecChan"],:value, 2)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/adjSFRecChan.png")
        @testImg("adjSFRecChan.png")
        set_gtk_property!(sf["adjSFRecChan"],:value, 1)
    end

    ## Visualization
    @testset "Visualization" begin
        # Complex blending
        set_gtk_property!(dv["cbComplexBlending"],:active, false)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/cbComplexBlending.png")
        @testImg("cbComplexBlending.png")
        set_gtk_property!(dv["cbBlendChannels"],:active, false)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/cbBlendChannels.png")
        @testImg("cbBlendChannels.png")
    end

    ## Background correction
    @testset "Background" begin
        set_gtk_property!(sf["cbSFBGCorr"],:active, false)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/cbSFBGCorr.png")
        @testImg("cbSFBGCorr.png")
        set_gtk_property!(sf["cbSFBGCorr"],:active, true)
    end

    ## Visualization
    @testset "Visualization DataViewer" begin
        # slices
        xx = get_gtk_property(dv["adjSliceX"],:value,Int64)
        yy = get_gtk_property(dv["adjSliceY"],:value,Int64)
        set_gtk_property!(dv["adjSliceX"], :value, xx+5)
        set_gtk_property!(dv["adjSliceY"], :value, yy+5)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/adjSlice_xy.png")
        @testImg("adjSlice_xy.png")
        write_to_png(getgc(dv.grid3D[1,1]).surface,"img/adjSlice_xz.png")
        @testImg("adjSlice_xz.png")

        # show slices
        set_gtk_property!(dv["cbShowSlices"],:active, false)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/cbShowSlicesFalse.png")
        @testImg("cbShowSlicesFalse.png")

        # MIP 
        set_gtk_property!(dv["cbSpatialMIP"],:active, true)
        sleep(3)
        write_to_png(getgc(dv.grid3D[1,1]).surface,"img/cbSpatialMIP.png")
        @testImg("cbSpatialMIP.png")
        set_gtk_property!(dv["cbSpatialMIP"],:active, false)

        # Coordinate system
        set_gtk_property!(dv["cbShowAxes"], :active, true)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/cbShowAxes.png")
        @testImg("cbShowAxes.png")
        set_gtk_property!(dv["cbShowAxes"], :active, false)

        # Minimum/maximum
        set_gtk_property!(dv["adjCMin"],:value, 0.2)
        set_gtk_property!(dv["adjCMax"],:value, 0.8)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/adjCMinMax.png")
        @testImg("adjCMinMax.png")
        set_gtk_property!(dv["adjCMin"],:value, 0.0)
        set_gtk_property!(dv["adjCMax"],:value, 1.0)

        # channel
        set_gtk_property!(dv["cbChannel"],:active, 1)
        sleep(0.5)
        write_to_png(getgc(dv.grid3D[2,2]).surface,"img/cbChannel.png")
        @testImg("cbChannel.png")
        set_gtk_property!(dv["cbChannel"],:active, 0)

        # click on pixel to change slices

    end

    ## Line plots
    @testset "Line plots" begin
        write_to_png(getgc(dv.grid3D[1,2]).surface,"img/cbProfile_x.png")
        @testImg("cbProfile_x.png")
        set_gtk_property!(dv["cbProfile"],:active, 1) # change to profile along y-axis
        set_gtk_property!(dv["cbShowAxes"],:active, true) #updates profile plot
        write_to_png(getgc(dv.grid3D[1,2]).surface,"img/cbProfile_y.png")
        @testImg("cbProfile_y.png")
        write_to_png(getgc(dv.grid3D[1,2]).surface,"img/cbProfile_y.png")
        write_to_png(getgc(sf.grid[1,2]).surface,"img/SNR.png")
        @testImg("SNR.png")
    end

    # close window
    destroy(s.w)
end