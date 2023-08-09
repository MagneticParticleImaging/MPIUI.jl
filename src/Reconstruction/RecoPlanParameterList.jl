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
  planFilter::Dict{String, Bool}
  # Hacky field to stop GTK segfaulting 
  children::Vector{Vector{String}}
end

function RecoPlanParameterFilter(params::RecoPlanParameters)
  dict = Dict{String, RecoPlanParameters}()
  fillTreeDict!(dict, params)
  planFilter = Dict{String, Bool}()
  for key in keys(dict)
    planFilter[key] = true
  end
  factory = GtkSignalListItemFactory()

  filterGrid = GtkGrid()
  entry = GtkSearchEntry()
  entry.hexpand = true
  missingButton = GtkCheckButton("Only missing")
  missingButton.active = false
  filter = RecoPlanParameterFilter(params, filterGrid, nothing, entry, missingButton, dict, planFilter, [String[]])

  function create_tree(item, userData)
    if item != C_NULL
      itemLeaf = Gtk4.GLib.find_leaf_type(item)
      item = convert(itemLeaf, item)
      str = item.string

      parent = filter.dict[str]
      children = getChildStrings(parent) # Otherwise Strings seem to be GC'ed and segfaulst are caused
      push!(filter.children, children)
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
      if isempty(box)
        key = Gtk4.get_item(row).string
        labelString = split(key, ".")[end]
        label = GtkLabel(labelString)
        label.hexpand = true
        label.xalign = 0.0
        check = GtkCheckButton()
        check.active = filter.planFilter[key]
        #expander.hide_expander = isempty(getChildStrings(filter.dict[key]))
        # TODO set callback
        push!(box, label)
        push!(box, check)
      end
    end
  end

  function unbind_tree(f, li)
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

function match(filter::RecoPlanParameterFilter, li, user_data)
  println(typeof(li))
  result = true
  return result == true ? Cint(1) : Cint(0)
end


mutable struct RecoPlanParameterList
  model::GtkStringList
  factory::GtkSignalListItemFactory
  view::Union{Nothing, GtkListView}
  paramters::RecoPlanParameters
  dict::Dict{String, Union{RecoPlanParameter,RecoPlanParameters}}
end

function RecoPlanParameterList(params::RecoPlanParameters; filter::Union{RecoPlanParameterFilter, Nothing} = nothing)
  dict = Dict{String, Union{RecoPlanParameter,RecoPlanParameters}}()
  fillListDict!(dict, params)
  strings = sort(collect(keys(dict)))
  model = GtkStringList(strings) # Can't creat GListStores with custom GObject types (yet) -> String and map to dict
  factory = GtkSignalListItemFactory()
  
  list = RecoPlanParameterList(model, factory, nothing, params, dict)

  function setup_param(f, li) # (factory, listitem)    
    set_child(li, GtkBox(:v))
  end
  # In general a view might rebind a widget for different items, should not matter for our short lists
  function bind_param(f, li) 
    box = get_child(li)
    if isempty(box)
      key = li[].string
      entry = list.dict[key]
      child = getListChild(entry)
      push!(box, child)
    end
  end
  signal_connect(setup_param, factory, "setup")
  signal_connect(bind_param, factory, "bind")

  if !isnothing(filter)
    customFilter = GtkCustomFilter((li, data) -> match(filter, li, data))
    model = GtkFilterListModel(GLib.GListModel(model), customFilter)
  end

  view = GtkListView(GtkSelectionModel(GtkSingleSelection(GLib.GListModel(model))), factory)
  list.view = view
  return list
end

function fillListDict!(dict, params::RecoPlanParameters)
  dict[id(params)] = params
  for parameter in params.parameters
    fillListDict!(dict, parameter)
  end
  for parameter in params.nestedParameters
    fillListDict!(dict, parameter)
  end
  return dict
end
fillListDict!(dict, params::RecoPlanParameter) = dict[id(params)] = params

getListChild(params::RecoPlanParameter) = widget(params)
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
  return grid
end