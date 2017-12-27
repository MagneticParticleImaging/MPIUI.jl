export RecoParamsWidget, RecoParams

import Base: getindex

type RecoParams <: Gtk.GtkBox
  # handle::Ptr{Gtk.GObject}
  builder
  parent
  recoParams
  selectedSFIndex
end

getindex(m::RecoParams, w::AbstractString) = G_.object(m.builder, w)

function getRecoParams(rP::RecoParams)
  return rP.recoParams
end

function RecoParamsWidget(parent, settings, recoParams = defaultRecoParams())
  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","recoParams.ui")
  b = Builder(filename=uifile)
  # mainBox = G_.object(b, "recoParamsChildBox")
  # m = RecoParams( mainBox.handle, b)
  recoParams[:spectralCleaning] = false
  recoParams[:iterations] = 1
  recoParams[:nAverages] = 1
  recoParams[:SFPath] = [string()]
  m = RecoParams(b, parent, recoParams, 1)
  setRecoParams(m)
  # Gtk.gobject_move_ref(m, mainBox)

  entRecoDescrip = m["entRecoDescrip"]
  cbRecoProfiles = m["cbRecoProfiles"]
  btDeleteRecoProfile = ["btDeleteRecoProfile"]
  btSaveRecoParams = m["btSaveRecoParams"]
  adjNumSF = m["adjNumSF"]
  entSF = m["entSF"]
  btBrowseSF = m["btBrowseSF"]
  adjSelectedSF = m["adjSelectedSF"]
  adjMinFreq = m["adjMinFreq"]
  adjMaxFreq = m["adjMaxFreq"]
  adjSNRThresh = m["adjSNRThresh"]
  entNumFreq = m["entNumFreq"]
  cbRecX = m["cbRecX"]
  cbRecY = m["cbRecY"]
  cbRecZ = m["cbRecZ"]
  adjFrame = m["adjFrame"]
  adjLastFrame = m["adjLastFrame"]
  adjAverages = m["adjAverages"]
  cbSubtractBG = m["cbSubtractBG"]
  cbSolver = m["cbSolver"]
  adjIterations = m["adjIterations"]
  adjLambda = m["adjLambda"]
  cbSpectralCleaning = m["cbSpectralCleaning"]
  cbLoadAsReal = m["cbLoadAsReal"]
  cbMatrixCompression = m["cbMatrixCompression"]
  cbSparsityTrafo = m["cbSparsityTrafo"]
  adjRedFactor = m["adjRedFactor"]
  entSF = m["entSF"]
  cbRecoProfiles = m["cbRecoProfiles"]
  btBrowseBG = m["btBrowseBG"]
  entBG = m["entBG"]
  adjFirstFrameBG = m["adjFirstFrameBG"]
  adjLastFrameBG = m["adjLastFrameBG"]



  for c in linearSolverList()# only option 1 was working at the time
    push!(cbSolver, c)
  end
  Gtk.@sigatom setproperty!(cbSolver, :active, 0)
  signal_connect(cbSolver, "changed") do widget
    index = getproperty(cbSolver, :active, Int64) +1
    m.recoParams[:solver] = linearSolverList()[index]
    println(m.recoParams[:solver])
  end

  for c in linearOperatorList()
    push!(cbSparsityTrafo, c)
  end
  Gtk.@sigatom setproperty!(cbSparsityTrafo, :active, 0)
  signal_connect(cbSparsityTrafo, "changed") do widget
      index = getproperty(cbSparsityTrafo, :active, Int64) +1
      matrixCompression = getproperty(cbMatrixCompression, :active, Bool)
      m.recoParams[:sparseTrafo] = matrixCompression ?
             linearOperatorList()[max(getproperty(cbSparsityTrafo, :active, Int64) + 1,1)] : nothing
    println(matrixCompression)
    println(m.recoParams[:sparseTrafo])
  end

  signal_connect(entRecoDescrip, "changed" ) do widget
    println("Des")
  end

  signal_connect(adjNumSF, "value-changed") do widget
    tmpSFPath = copy(m.recoParams[:SFPath])
    resize!(tmpSFPath, getproperty(adjNumSF,:value,Int64))
    if length(tmpSFPath) > length(m.recoParams[:SFPath])
      for i=(length(m.recoParams[:SFPath])+1):length(tmpSFPath)
        tmpSFPath[i] = string()
      end
    end
    m.recoParams[:SFPath] = tmpSFPath
    Gtk.@sigatom setproperty!(adjSelectedSF, :upper, length(tmpSFPath))
  end

  signal_connect(adjSelectedSF, "value-changed") do widget
    m.selectedSFIndex = getproperty(adjSelectedSF, :value, Int64)
    sFPathtxt = m.recoParams[:SFPath][m.selectedSFIndex]
    setproperty!(entSF, :text, sFPathtxt)
  end

  signal_connect(btBrowseSF, "clicked") do widget
    dialog = Dialog("Select System Function", parent, GtkDialogFlags.MODAL,
                          Dict("gtk-cancel" => GtkResponseType.CANCEL,
                               "gtk-ok"=> GtkResponseType.ACCEPT) )

    resize!(dialog, 1024, 1024)
    box = G_.content_area(dialog)
    sfBrowser = SFBrowserWidget()
    push!(box, sfBrowser.box)
    setproperty!(box, :expand, sfBrowser.box, true)
    selection = G_.selection(sfBrowser.tv)
    dlg = SFSelectionDialog(dialog.handle, selection, sfBrowser.store, sfBrowser.tmSorted)
    showall(box)
    Gtk.gobject_move_ref(dlg, dialog)
    ret = run(dlg)
    if ret == GtkResponseType.ACCEPT
      if hasselection(dlg.selection)
        sffilename =  getSelectedSF(dlg)
        println(sffilename)
        recoParams[:SFPath][m.selectedSFIndex] = sffilename
        setproperty!(entSF, :text, sffilename)
        nothing
      end
    end
    destroy(dlg)
  end

  signal_connect(adjMinFreq, "value-changed") do widget
    m.recoParams[:minFreq] = getproperty(adjMinFreq, :value, Float64) *1000
  end
  signal_connect(adjMaxFreq, "value-changed") do widget
    m.recoParams[:maxFreq] = getproperty(adjMaxFreq, :value, Float64) *1000
  end
  signal_connect(adjSNRThresh, "value-changed") do widget
    m.recoParams[:SNRThresh] = getproperty(adjSNRThresh, :value, Float64)
  end
  signal_connect(cbRecX, "toggled") do widget
    m.recoParams[:recChannels] = Gtk.@sigatom getRecoChannels(cbRecX, cbRecY, cbRecZ)
  end
  signal_connect(cbRecY, "toggled") do widget
    m.recoParams[:recChannels] = Gtk.@sigatom getRecoChannels(cbRecX, cbRecY, cbRecZ)
  end
  signal_connect(cbRecZ, "toggled") do widget
    m.recoParams[:recChannels] = Gtk.@sigatom getRecoChannels(cbRecX, cbRecY, cbRecZ)
  end
  signal_connect(adjFrame, "value-changed") do widget
      firstFrame = getproperty(adjFrame, :value, Int64)
      lastFrame = getproperty(adjLastFrame, :value, Int64)
      if firstFrame > lastFrame
        lastFrame = firstFrame
        Gtk.@sigatom setproperty!(adjLastFrame, :value, lastFrame)
      end
    frames = firstFrame:lastFrame
    m.recoParams[:frame] = frames
  end
  signal_connect(adjLastFrame, "value-changed") do widget
      firstFrame = getproperty(adjFrame, :value, Int64)
      lastFrame = getproperty(adjLastFrame, :value, Int64)
      if firstFrame > lastFrame
        firstFrame = lastFrame
        Gtk.@sigatom setproperty!(adjFrame, :value, firstFrame)
      end

    frames = firstFrame:lastFrame
    m.recoParams[:frame] = frames
  end
  signal_connect(adjAverages, "value-changed") do widget
    m.recoParams[:nAverages] = getproperty(adjAverages, :value, Int64)
  end
  signal_connect(cbSubtractBG, "toggled") do widget
      if getproperty(cbSubtractBG, :active, Bool)
        m.recoParams[:emptyMeasPath] = getproperty(entBG, :text, String)
      else
        m.recoParams[:emptyMeasPath] = nothing
      end
  end

  signal_connect(btBrowseBG, "clicked") do widget
    folderPath = open_dialog("Select Background Measurement", parent, action=GtkFileChooserAction.SELECT_FOLDER)
    if !isdir(folderPath)
      println(folderPath * " is not a directory")
    else
      Gtk.@sigatom setproperty!(entBG, :text, folderPath)
      Gtk.@sigatom setproperty!(cbSubtractBG, :active, true)
    end
  end

  signal_connect(adjFirstFrameBG, "value-changed") do widget
    m.recoParams[:firstFrameBG] = getproperty(adjFirstFrameBG, :value, Int64)
  end
  signal_connect(adjLastFrameBG, "value-changed") do widget
    m.recoParams[:lastFrameBG] = getproperty(adjLastFrameBG, :value, Int64)
  end
  signal_connect(adjIterations, "value-changed") do widget
    m.recoParams[:iterations] = getproperty(adjIterations, :value, Int64)
  end
  signal_connect(adjLambda, "value-changed") do widget
    m.recoParams[:lambd] = getproperty(adjLambda, :value, Float64)
  end
  signal_connect(cbSpectralCleaning, "toggled") do widget
    m.recoParams[:spectralCleaning] = getproperty(cbSpectralCleaning, :active, Bool)
    println(m.recoParams[:spectralCleaning])
  end
  signal_connect(cbLoadAsReal, "toggled") do widget
    m.recoParams[:loadasreal] = getproperty(cbLoadAsReal, :active, Bool)
    println(m.recoParams[:loadasreal])
  end
  signal_connect(cbMatrixCompression, "toggled") do widget
    matrixCompression = getproperty(cbMatrixCompression, :active, Bool)
    m.recoParams[:sparseTrafo] = matrixCompression ?
             linearOperatorList()[max(getproperty(cbSparsityTrafo,:active, Int64) + 1,1)] : nothing

    println(matrixCompression)
    println(m.recoParams[:sparseTrafo])
  end
  signal_connect(adjRedFactor, "value-changed") do widget
    m.recoParams[:redFactor] = getproperty(adjRedFactor, :value, Float64)
    println(m.recoParams[:redFactor])
  end

  function loadRecoProfile( widget )

    selectedProfileName = Gtk.bytestring( G_.active_text(cbRecoProfiles))
    println(selectedProfileName)
    if haskey(settings[:recoParams],selectedProfileName)
      Gtk.@sigatom setRecoParams(m,settings[:recoParams][selectedProfileName])
    end

  end
  signalId_cbRecoProfiles = signal_connect(loadRecoProfile, cbRecoProfiles, "changed")

  function saveRecoParams( widget )
    currentRecoParams = recoParams
    key = getproperty(m["entRecoParamsName"], :text, String)

    settings[:recoParams][key] = currentRecoParams
    Gtk.@sigatom save(settings)
    Gtk.@sigatom updateRecoProfiles()
  end
  signal_connect(saveRecoParams, m["btSaveRecoParams"], "clicked")


  function deleteRecoProfile( widget )
    selectedProfileName = Gtk.bytestring( G_.active_text(cbRecoProfiles))

    Gtk.@sigatom println("delete reco profile ", selectedProfileName)

    Gtk.@sigatom delete!(settings[:recoParams], selectedProfileName)
    Gtk.@sigatom save(settings)
    Gtk.@sigatom updateRecoProfiles()
  end
  signal_connect(deleteRecoProfile, m["btDeleteRecoProfile"], "clicked")

  function updateRecoProfiles()
    signal_handler_block(cbRecoProfiles, signalId_cbRecoProfiles)

    empty!(cbRecoProfiles)
    println(typeof(settings))
    for key in keys(settings[:recoParams])
      push!(cbRecoProfiles, key)
    end
    setproperty!(cbRecoProfiles,:active,0)
    signal_handler_unblock(cbRecoProfiles, signalId_cbRecoProfiles)
  end

  #updateRecoProfiles()


  return m
end

function getRecoChannels(cbRecX, cbRecY, cbRecZ)
  params = Int64[]
  if getproperty(cbRecX, :active, Bool)
    push!(params, 1)
  end
  if getproperty(cbRecY, :active, Bool)
    push!(params, 2)
  end
  if getproperty(cbRecZ, :active, Bool)
    push!(params, 3)
  end
  return params
end

function setRecoParams(m::RecoParams, params::Dict{Symbol,Any})
  Gtk.@sigatom setproperty!(m["adjLambda"], :value, params[:lambd])
  Gtk.@sigatom setproperty!(m["adjIterations"], :value, params[:iterations])
  Gtk.@sigatom setproperty!(m["adjSNRThresh"], :value, params[:SNRThresh])
  Gtk.@sigatom setproperty!(m["adjMinFreq"], :value, params[:minFreq] / 1000)
  Gtk.@sigatom setproperty!(m["adjMaxFreq"], :value, params[:maxFreq] / 1000)
  Gtk.@sigatom setproperty!(m["adjAverages"], :value, params[:nAverages])
  Gtk.@sigatom setproperty!(m["adjFrame"], :value, first(params[:frames]))
  Gtk.@sigatom setproperty!(m["adjLastFrame"], :value, last(params[:frames]))
  Gtk.@sigatom setproperty!(m["cbSpectralCleaning"], :active, params[:spectralCleaning])
  Gtk.@sigatom setproperty!(m["cbLoadAsReal"], :active, params[:loadasreal])
  Gtk.@sigatom setproperty!(m["adjRedFactor"], :value, get(params,:redFactor,0.01))
  Gtk.@sigatom setproperty!(m["adjFirstFrameBG"], :value, get(params,:firstFrameBG,1))
  Gtk.@sigatom setproperty!(m["adjLastFrameBG"], :value, get(params,:lastFrameBG,1))
  # for (i,solver) in enumerate(linearSolverList())
  #   if solver == params[:solver]
  #     Gtk.@sigatom setproperty!(m["cbSolver"],:active, i-1)
  #   end
  # end

  sparseTrafo = get(params, :sparseTrafo, nothing)
  Gtk.@sigatom setproperty!(m["cbMatrixCompression"], :active, sparseTrafo != nothing)
  if sparseTrafo != nothing
    for (i,trafo) in enumerate(linearOperatorList())
      if trafo == sparseTrafo
         Gtk.@sigatom setproperty!(m["cbSparsityTrafo"],:active, i-1)
      end
    end
  end

  Gtk.@sigatom setproperty!(m["cbRecX"], :active, in(1,params[:recChannels]))
  Gtk.@sigatom setproperty!(m["cbRecY"], :active, in(2,params[:recChannels]))
  Gtk.@sigatom setproperty!(m["cbRecZ"], :active, in(3,params[:recChannels]))

  Gtk.@sigatom setproperty!(m["entRecoDescrip"], :text, get(params, :description,""))
end

function setRecoParams(m::RecoParams)
  params = getRecoParams(m)
  setRecoParams(m, params)


  # if haskey(params, :SFPath)
  #   if typeof(params[:SFPath]) <: AbstractString
  #     params[:SFPath] = String[params[:SFPath]]
  #   end
  #   numSF = length(params[:SFPath])
  #   Gtk.@sigatom setproperty!(m["adjNumSF"], :value, numSF)
  #   m.bSF = BrukerFile(params[:SFPath])
  # else
  #   Gtk.@sigatom setproperty!(m["adjNumSF"], :value, 1)
  #   m.bSF = BrukerFile[BrukerFile()]
  # end
end
