export RecoWindow, OfflineRecoWidget

include("ReconstructionParameter.jl")
include("RecoPlanParameter.jl")
include("RecoPlanParameterList.jl")
include("PlanRecoWidget.jl")

mutable struct OfflineRecoWidget <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  builder
  plandd::GtkDropDown
  plan::Union{Nothing, RecoPlan}
  inputs::Union{Nothing, RecoPlanParameters}
  filter::Union{Nothing, RecoPlanParameterFilter}
  list::Union{Nothing, RecoPlanParameterList}
  dv
  bMeas
  sysMatrix
  freq
  recoResult
  recoGrid
  currentStudy
  currentExperiment
end

getindex(m::OfflineRecoWidget, w::AbstractString) = G_.get_object(m.builder, w)

mutable struct RecoWindow
  w::Gtk4.GtkWindowLeaf
  rw::OfflineRecoWidget
end

function RecoWindow(filenameMeas=nothing; plan = nothing)
  w = GtkWindow("Reconstruction",800,600)
  dw = OfflineRecoWidget(filenameMeas, plan = plan)
  push!(w,dw)

  #if isassigned(mpilab)
  #  G_.transient_for(w, mpilab[]["mainWindow"])
  #end
  G_.modal(w,true)
  show(w)

  return RecoWindow(w,dw)
end

function OfflineRecoWidget(filenameMeas=nothing; plan = nothing)

  uifile = joinpath(@__DIR__, "..", "builder", "reconstructionWidget.ui")

  b = GtkBuilder(uifile)
  mainGrid = G_.get_object(b, "gridReco")
  @info "in OfflineRecoWidget"

  choices = map(x -> split(x, ".toml")[1], filter(contains(".toml"), readdir(AbstractImageReconstruction.plandir(MPIReco))))
  plandd = GtkDropDown(choices)
  Gtk4.enable_search(plandd, true)

  m = OfflineRecoWidget( mainGrid.handle, b, plandd,
                  plan, nothing, nothing, nothing,
                  nothing,
                  nothing,
                  nothing, nothing, nothing, nothing,
                  nothing, nothing)
  Gtk4.GLib.gobject_move_ref(m, mainGrid)

  # Add plan handling
  pushfirst!(m["tbRec"], plandd)
  if isnothing(plan)
    plan = Gtk4.selected_string(plandd)
    updatePlan!(m, plan)
  end

  m.dv = DataViewerWidget()
  push!(m["boxDW"], m.dv)

  updateData!(m, filenameMeas)

  initCallbacks(m)

  return m
end

function initCallbacks(m::OfflineRecoWidget)
  signal_connect((w)->performReco(m), m["tbPerformReco"], "clicked")
  signal_connect((w)->saveReco(m), m["tbSaveReco"], "clicked")
  signal_connect(m.plandd, "notify::selected") do widget, others...
    plan = Gtk4.selected_string(m.plandd)
    updatePlan!(m, plan)
  end
  
end

function saveReco(m::OfflineRecoWidget)
  if m.recoResult !== nothing
    m.recoResult.recoParams[:description] = get_gtk_property(m.params["entRecoDescrip"], :text, String)
    if isassigned(mpilab)
      @idle_add_guarded addReco(mpilab[], m.recoResult, m.currentStudy, m.currentExperiment)
    else
      if m.currentStudy !== nothing && m.currentExperiment !== nothing
        # using MDFDatasetStore
        addReco(getMDFStore(m.currentStudy), m.currentStudy, m.currentExperiment, m.recoResult)
      else
        # no DatasetStore -> save reco in the same folder as the measurement
        pathfile = joinpath(split(filepath(m.bMeas),"/")[1:end-1]...,"reco")
        saveRecoData(pathfile*".mdf",m.recoResult)
        @info "Reconstruction saved at $(pathfile).mdf"
      end
    end
  end
end

updatePlan!(m::OfflineRecoWidget, plan::String) = updatePlan!(m, loadPlan(MPIReco, plan, [MPIReco, MPIFiles, RegularizedLeastSquares, AbstractImageReconstruction]))
function updatePlan!(m::OfflineRecoWidget, plan::RecoPlan)
  @idle_add_guarded begin 
    boxParams = m["boxParams"]
    empty!(boxParams)

    inputs = RecoPlanParameters(plan)
    filter = RecoPlanParameterFilter(inputs)
    list = RecoPlanParameterList(inputs, filter = filter)
    recoPanel = GtkPaned(:h)
    recoPanel[1] = widget(filter)
    sw = GtkScrolledWindow()
    sw[] = widget(list)
    recoPanel[2] = sw

    push!(boxParams, recoPanel)
    m.plan = plan
  end
end

function updateData!(m::OfflineRecoWidget, filenameMeas, plan::RecoPlan,
                     study=nothing, experiment=nothing)
  updatePlan!(m, plan)
  updateData!(m, filenameMeas, study, experiment)
end

@guarded function updateData!(m::OfflineRecoWidget, filenameMeas, study=nothing, experiment=nothing)
  if filenameMeas != nothing
    m.bMeas = MPIFile(filenameMeas)
    m.currentStudy = study
    m.currentExperiment = experiment
  end
  return nothing
end

function infoMessage(m::OfflineRecoWidget, message::String="", color::String="green")
  @idle_add_guarded begin
    message = """<span foreground="$color" font_weight="bold" size="x-large">$message</span>"""
    if isassigned(mpilab)
      infoMessage(mpilab[], message)
    end
  end
end

function progress(m::OfflineRecoWidget, startStop::Bool)
  if isassigned(mpilab)
    progress(mpilab[], startStop)
  end
end


function performReco(m::OfflineRecoWidget)
  @tspawnat 2 performReco_(m)
end

@guarded function performReco_(m::OfflineRecoWidget)
  algo = build(m.plan)
  progress(m, true)
  m.recoResult = MPIReco.reconstruct(algo, m.bMeas)
  #m.recoResult.recoParams = getParams(m.params)
  @idle_add_guarded begin
    updateData!(m.dv, m.recoResult)
    infoMessage(m, "")
    progress(m, false)
  end
  return nothing
end
