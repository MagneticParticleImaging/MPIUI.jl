# Based on https://github.com/JuliaGtk/Gtk4.jl/issues/29
mutable struct RecoPlanParameterFilter
  parameters::RecoPlanParameters
  # Filter GTK elements
  filterGrid::GtkGrid
  view::Union{Nothing, GtkListView}
  entry::GtkSearchEntry
  missingButton::GtkCheckButton
  # Filter State
  dict::Dict{String, RecoPlanParameters}
  planFilter::Dict{RecoPlanParameters, Bool}
  # Hacky field to stop GTK segfaulting 
  children::Dict{String, Vector{String}}
end
widget(filter::RecoPlanParameterFilter) = filter.filterGrid

function RecoPlanParameterFilter(params::RecoPlanParameters)
  dict = Dict{String, RecoPlanParameters}()
  fillTreeDict!(dict, params)
  planFilter = Dict{RecoPlanParameters, Bool}()
  for key in values(dict)
    planFilter[key] = true
  end
  factory = GtkSignalListItemFactory()

  filterGrid = GtkGrid()
  entry = GtkSearchEntry()
  entry.hexpand = true
  missingButton = GtkCheckButton("Only missing")
  missingButton.active = false
  filter = RecoPlanParameterFilter(params, filterGrid, nothing, entry, missingButton, dict, planFilter, Dict{String, Vector{String}}())

  function create_tree(item, userData)
    if item != C_NULL
      itemLeaf = Gtk4.GLib.find_leaf_type(item)
      item = convert(itemLeaf, item)
      str = item.string

      parent = filter.dict[str]
      children = getChildStrings(parent) # Otherwise Strings seem to be GC'ed and segfaulst are caused
      filter.children[str] = children
      store = GtkStringList(children)

      return Gtk4.GLib.GListModel(store)
    else
      return C_NULL
    end
  end

  function create_tree_raw(item, userData)
    result = create_tree(item, userData)
    return result.handle
  end

  function setup_tree(f, li)
    expander = GtkTreeExpander()
    box = GtkBox(:h)
    set_child(expander, box)
    set_child(li, expander)
  end

  function bind_tree(f, li)
    row = li[]
    if row != C_NULL
      expander = get_child(li)
      Gtk4.set_list_row(expander, row)
      box = get_child(expander)
      key = Gtk4.get_item(row).string
      labelString = split(key, ".")[end]
      label = GtkLabel(labelString)
      label.hexpand = true
      label.xalign = 0.0
      check = GtkCheckButton()
      check.active = filter.planFilter[filter.dict[key]]
      push!(box, label)
      push!(box, check)
    end
  end

  function unbind_tree(f, li)
    row = li[]
    if row != C_NULL
      expander = get_child(li)
      Gtk4.set_list_row(expander, row)
      box = get_child(expander)
      empty!(box)
    end
  end

  signal_connect(setup_tree, factory, "setup")
  signal_connect(bind_tree, factory, "bind")
  signal_connect(unbind_tree, factory, "unbind")


  root = Gtk4.GLib.GListModel(GtkStringList(getChildStrings(params)))
  tree = GtkTreeListModel(root, false, true, create_tree_raw)
  selection = GtkSelectionModel(GtkSingleSelection(Gtk4.GLib.GListModel(tree)))
  view = GtkListView(selection, factory)
  view.hexpand = true
  view.vexpand = true
  filter.view = view

  filterGrid[1, 1] = entry
  filterGrid[2, 1] = missingButton
  scroll = GtkScrolledWindow()
  scroll[] = view
  filterGrid[1:2, 2] = scroll
  return filter
end

function fillTreeDict!(dict, params::RecoPlanParameters)
  dict[id(params)] = params
  for parameter in params.nestedParameters
    fillTreeDict!(dict, parameter)
  end
  return dict
end

function getChildStrings(params::RecoPlanParameters)
  result = String[]
  for parameter in params.nestedParameters
    push!(result, id(parameter))
  end
  return sort(result)
end

function addFilter!(filter::RecoPlanParameterFilter, list::GtkListBox)
  signal_connect(filter.missingButton, :toggled) do btn
    @idle_add Gtk4.G_.invalidate_filter(list) 
  end
end

function match(filter::RecoPlanParameterFilter, parameters::RecoPlanParameters)
  result = true
  return result ? Cint(1) : Cint(0)
end

function match(filter::RecoPlanParameterFilter, parameter::RecoPlanParameter)
  result = true

  result = !filter.missingButton.active || ismissing(parameter.plan[parameter.field])
  return result ? Cint(1) : Cint(0)
end


mutable struct RecoPlanParameterList
  listBox::GtkListBox
  parameters::RecoPlanParameters
  filter::Union{RecoPlanParameterFilter, Nothing}
  listInputs::Vector{Union{RecoPlanParameter, RecoPlanParameters}}
  listWidgets::Vector{GtkWidget}
end

function RecoPlanParameterList(params::RecoPlanParameters; filter::Union{RecoPlanParameterFilter, Nothing} = nothing)
  listInputs = Vector{Union{RecoPlanParameter, RecoPlanParameters}}()
  listWidgets = Vector{GtkWidget}()
  fillListVectors!(params, listInputs, listWidgets)
  
  list = RecoPlanParameterList(GtkListBox(), params, filter, listInputs, listWidgets)

  if !isnothing(filter)
    addFilter!(filter, list.listBox)
    Gtk4.set_filter_func(list.listBox, (row, data) -> match(list, row, data))
  end

  for widget in listWidgets
    push!(list.listBox, widget)
  end

  return list
end
widget(planList::RecoPlanParameterList) = planList.listBox

function fillListVectors!(params::RecoPlanParameters, inputs, widgets)
  push!(inputs, params)
  push!(widgets, getListChild(params))
  for parameter in params.parameters
    fillListVectors!(parameter, inputs, widgets)
  end
  for parameter in params.nestedParameters
    fillListVectors!(parameter, inputs, widgets)
  end
end
function fillListVectors!(params::RecoPlanParameter, inputs, widgets) 
  push!(inputs, params)
  push!(widgets, getListChild(params))
end

function getListChild(params::RecoPlanParameter) 
  result = widget(params)
  result.margin_top = 10
  result.margin_bottom = 10
  return result
end
function getListChild(params::RecoPlanParameters{T}) where T
  grid = GtkGrid()
  parents = AbstractImageReconstruction.parentfields(params.plan)
  if !isempty(parents)
    parent = parents[end]
    parentLabel = GtkLabel("<span size = \"large\"><b>$parent</b></span>")
    parentLabel.use_markup = true
    parentLabel.hexpand = true
    parentLabel.xalign = 0.0
    typeLabel = GtkLabel("($T)")
    typeLabel.justify = 1
    grid[1,1] = parentLabel
    grid[2,1] = typeLabel
  else
    centerLabel = GtkLabel("<span size = \"x-large\"><b>$T</b></span>")
    centerLabel.use_markup = true
    centerLabel.hexpand = true
    centerLabel.justify = 2
    grid[1:2, 1] = centerLabel
  end
  grid.margin_top = 25
  return grid
end

function match(list::RecoPlanParameterList, li::Ptr{Gtk4.GLib.GObject}, data)
  itemLeaf = Gtk4.GLib.find_leaf_type(li)
  item = convert(itemLeaf, li)
  return match(list, item)
end

function match(list::RecoPlanParameterList, item)
  widget = item.child
  idx = findfirst(x-> x == widget, list.listWidgets)
  return match(list.filter, list.listInputs[idx])
end