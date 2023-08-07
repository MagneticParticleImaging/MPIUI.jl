mutable struct RecoPlanParameterList
  model::GtkStringList
  factory::GtkSignalListItemFactory
  view::Union{Nothing, GtkListView}
  paramters::RecoPlanParameters
  dict::Dict{String, Union{RecoPlanParameter,RecoPlanParameters}}
end

function RecoPlanParameterList(params::RecoPlanParameters)
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

mutable struct RecoPlanParameterFilter
  parameters::RecoPlanParameters
  filterWidgets::Vector{GtkWidget}
  dict::Dict{String, RecoPlanParameters}
  view::Union{Nothing, GtkListView}
end

function RecoPlanParameterFilter(params::RecoPlanParameters)
  dict = Dict{String, RecoPlanParameters}()
  fillTreeDict!(dict, params)
  factory = GtkSignalListItemFactory()

  filter = RecoPlanParameterFilter(params, GtkWidget[], dict, nothing)

  function create_tree(item, userData)
    if item != C_NULL
      itemLeaf = Gtk4.GLib.find_leaf_type(item)
      println(itemLeaf)
      item = convert(itemLeaf, item)
      str = item.string
      store = GtkStringList()

      parent = filter.dict[str]
      for child in getChildStrings(parent)
        push!(store, child)
      end

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
        labelString = split(Gtk4.get_item(row).string, ".")[end]
        label = GtkLabel(labelString)
        label.hexpand = true
        label.xalign = 0.0
        check = GtkCheckButton()
        check.active = true
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
  selection = GtkSelectionModel(GtkMultiSelection(Gtk4.GLib.GListModel(tree)))
  view = GtkListView(selection, factory)
  filter.view = view
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