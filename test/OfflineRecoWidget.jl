@testset "OfflineRecoWidget" begin
    # Download data
    study = (getStudies(datasetstore,"BackgroundDrift") == Study[]) ? Study(datasetstore, "BackgroundDrift") : getStudies(datasetstore,"BackgroundDrift")[1]
    pathExp = joinpath(path(study),"1.mdf")
    download_("measurements/backgroundDrift/1.mdf", pathExp)
    exp = getExperiment(study,1)

    # path SF
    pathSF = joinpath(calibdir(datasetstore),"1.mdf")

    # Start OfflineRecoWidget
    r = RecoWindow(pathExp);
    sleep(5)
    rw = r.rw # OfflineRecoWidget

    # add study and experiment to OfflineRecoWidget
    rw.currentStudy = study
    rw.currentExperiment = exp

    @testset "Parameter" begin
        # define a set of parameter 
        params = Dict{Symbol,Any}()
        # Description
        params[:description] = "Test Reconstruction"
        # System function
        params[:SFPath] = pathSF
        #params[:adjNumSF] = 1 # default: length(params[:SFPath]) or 1
        # Frequency Selection
        params[:SNRThresh] = 2.0
        params[:maxMixingOrder] = -1
        params[:minFreq] = 80e3
        params[:maxFreq] = 1.25e6
        params[:recChannels] = [1,2,3] # used to activate cbRecX,cbRecY,cbRecZ
        # Time Window
        params[:nAverages] = 60 # default: 1
        params[:frames] = 1:240 # used for first and last frame 
        # Background Subtraction
        params[:bgCorrectionInternal] = false #default
        # TODO: cb subtract external BG, BG meas, adjFirstFrameBG, lastFrameBG
        # Period Processing
        params[:numPeriodAverages] = 1
        params[:numPeriodGrouping] = 1
        # Solver Parameter
        params[:solver] = "Kaczmarz"
        params[:lambd] = 0.05 # default: 0.01 -> tested in testsubset
        params[:lambdaL1] = 0.0
        params[:lambdaTV] = 0.0
        params[:iterations] = 3 # default: 4
        # Misc
        params[:spectralCleaning] = true
        params[:loadasreal] = false # default
        # Matrix Compression
        # TODO: cb apply matrix compression
        params[:sparseTrafo] = nothing
        params[:redFactor] = 0.0
        
        # set parameter
        MPIUI.setParams(rw,params)
        sleep(1)
        
        # TODO:
        # params[:firstFrameBG] = 1
        # params[:lastFrameBG] = 1
        # params[:sortBySNR] = false
        # params[:repetitionTime] = 0.0
        # params[:denoiseWeight] = 0
        # params[:loadas32bit] = true     
        
        
        paramsTest = MPIUI.getParams(rw) 

        for entry in [:description,:SFPath,
            :SNRThresh,:maxMixingOrder,:minFreq,:maxFreq,:recChannels,# Frequency selection
            :nAverages,:frames,:bgCorrectionInternal,# Time Window and Background
            :numPeriodAverages,:numPeriodGrouping,# Period Processing
            :solver,:lambdaL1,:lambdaTV,:iterations,# Solver Parameter
            :spectralCleaning,:loadasreal,# Misc
            :sparseTrafo,:redFactor] # Matrix Compression

            @test params[entry] == paramsTest[entry]
        end

        @testset "Frames" begin
            # Correct first frame / last frame
        end

        @testset "Solver" begin
            # Different lambda for different solver
            # Kaczmarz
            params[:solver] = "Kaczmarz"
            params[:lambd] = 0.05 # default: 0.01
            params[:lambdaL1] = 0.1 # default: 0.0
            MPIUI.setParams(rw,params)
            sleep(1)
            paramsTest = MPIUI.getParams(rw)
            @test paramsTest[:lambd] ≈ [0.05, 0.1]
            @test paramsTest[:solver] == "Kaczmarz"

            # FusedLasso
            params[:solver] = "fusedlasso"
            params[:lambd] = 0.05 # default: 0.01
            params[:lambdaL1] = 0.1 # default: 0.0
            params[:lambdaTV] = 0.2 # default: 0.0
            MPIUI.setParams(rw,params)
            sleep(1)
            paramsTest = MPIUI.getParams(rw)
            @test paramsTest[:lambd] ≈ [0.1, 0.2]
            @test paramsTest[:solver] == "fusedlasso"
            @test paramsTest[:loadasreal] == true
            
            # CGNR
            params[:solver] = "cgnr"
            MPIUI.setParams(rw,params)
            sleep(1)
            paramsTest = MPIUI.getParams(rw)
            @test paramsTest[:solver] == "cgnr"
            # TODO parameter
        end

        @testset "BGCorrection" begin
            # TODO: write params
            # get params with 
            paramsTest = MPIUI.getParams(rw)
            #params[:emptyMeasPath] # = nothing if cbSubtractBG = false
            #params[:bgCorrectionInternal] # can be set with setParams
            #params[:bgFrames]
        end

        @testset "Load/Save Reco Profil" begin
            set_gtk_property!(rw.params["entRecoParamsName"], :text, "TestParameter")
            # TODO: Access to saveRecoParams and loadRecoParams
        end

        @testset "Browse System Matrix" begin
            # TODO: Not possible on laptop -> Error
        end
    end

    @testset "Perform/Save Reconstruction" begin

        @testset "Setup System Matrix" begin
            params = defaultRecoParams()
            MPIUI.setParams(rw,params)
            sleep(1)
            MPIUI.setSF(rw,pathSF)
            MPIUI.updateSF(rw)
            sleep(20)

            # test SF path and existence of SM
            params = MPIUI.getParams(rw)
            @test params[:SFPath][1] == pathSF 
            @test rw.sysMatrix !== nothing
        end

        MPIUI.performReco(rw)
        sleep(60)
        
        # Save Reco
        @info "saving Reco"
        MPIUI.saveReco(rw)
        sleep(2)
        reco = getReco(datasetstore, study, exp, 1)
        sleep(1)
        @test isfile(reco.path) == true
        remove(reco) # delete reco

        # compare reco result
        write_to_png(getgc(rw.dv.grid3D[2,2]).surface,"img/reco.png")
        @testImg("reco.png")
    end

    @testset "Fusion" begin
        # TODO
    end

    # close window
    destroy(r.w)
end