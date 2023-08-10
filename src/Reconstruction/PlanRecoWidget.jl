mutable struct PlanRecoWidget <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  builder
  dataInput::MPIFilePlanInput
  plan::RecoPlan
  inputs::RecoPlanParameters
  filter::RecoPlanParameterFilter
  list::RecoPlanParameterList
  dv
  result
end

getindex(widget::PlanRecoWidget, w::AbstractString) = G_.get_object(widget.builder, w)

mutable struct PlanRecoWindow
  w::Gtk4.GtkWindowLeaf
  rw::PlanRecoWidget
end

function PlanRecoWindow(plan::String)
  p = loadPlan(MPIReco, plan, [MPIReco, MPIFiles, RegularizedLeastSquares, AbstractImageReconstruction])
  window = GtkWindow(plan, 800, 600)
  planWidget = PlanRecoWidget(p)
  push!(window, planWidget)
  show(window)
  return PlanRecoWindow(window, planWidget)
end

function PlanRecoWidget(plan::RecoPlan)
  inputs = RecoPlanParameters(plan)
  @info "inputs"
  filter = RecoPlanParameterFilter(inputs)
  @info "filter"
  list = RecoPlanParameterList(inputs, filter = filter)
  @info "0"
  uifile = joinpath(@__DIR__, "..", "builder", "reconstructionWidget.ui")

  @info "1"
  b = GtkBuilder(uifile)
  mainGrid = G_.get_object(b, "gridReco")
  boxParams = G_.get_object(b, "boxParams")
  boxButtons = G_.get_object(b, "tbRec")

  @info "2"
  recoPanel = GtkPaned(:h)
  recoPanel[1] = filter.filterGrid
  sw = GtkScrolledWindow()
  sw[] = list.view
  recoPanel[2] = sw
  @info "3"
  push!(boxParams, recoPanel)

  @info "4"
  measInput = MPIFilePlanInput(MPIFile, missing, :Measurement)
  push!(boxButtons, widget(measInput))

  @info "5"
  planWidget = PlanRecoWidget(mainGrid.handle, b, measInput, plan, inputs, filter, list, nothing, nothing)
  @info "6"
  Gtk4.GLib.gobject_move_ref(planWidget, mainGrid)
  @info "7"
  planWidget.dv = DataViewerWidget()
  @info "8"
  push!(planWidget["boxDW"], planWidget.dv)

  initCallbacks(planWidget)
  @info "9"
  return planWidget
end

function initCallbacks(widget::PlanRecoWidget)
  signal_connect((w)->performReco(widget), widget["tbPerformReco"], "clicked")
  #signal_connect((w)->saveReco(m), m["tbSaveReco"], "clicked")
end

function performReco(widget::PlanRecoWidget)
  @tspawnat 2 performReco_(widget)
end

@guarded function performReco_(widget::PlanRecoWidget)
  @idle_add_guarded begin
    algo = build(widget.plan)
    recoResult = MPIReco.reconstruct(algo, value(widget.dataInput)) 
    updateData!(widget.dv, recoResult)
  end
  return nothing
end