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
  model = GtkStringList(strings)
  factory = GtkSignalListItemFactory()
  
  list = RecoPlanParameterList(model, factory, nothing, params, dict)

  function setup_param(f, li) # (factory, listitem)    
    set_child(li, GtkBox(:v))
  end
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