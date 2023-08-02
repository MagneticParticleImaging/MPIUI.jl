mutable struct RecoPlanParameterList
  model::GtkStringList
  factory::GtkSignalListItemFactory
  view::Union{Nothing, GtkListView}
  paramters::RecoPlanParameters
  dict::Dict{String, RecoPlanParameter}
end

function RecoPlanParameterList(params::RecoPlanParameters)
  dict = Dict{String, RecoPlanParameter}()
  paramVec = parameters(params)
  for (i, param) in enumerate(paramVec)
    dict[string(i)] = param
  end
  model = GtkStringList(collect(keys(dict)))
  factory = GtkSignalListItemFactory()
  
  list = RecoPlanParameterList(model, factory, nothing, params, dict)

  function setup_param(f, li) # (factory, listitem)
    expander = GtkExpander(nothing)
    expander.expanded = true
    set_child(li, expander)
  end
  function bind_param(f, li)
    key = li[].string
    expander = get_child(li)
    expander[] = widget(list.dict[key])
  end
  signal_connect(setup_param, factory, "setup")
  signal_connect(bind_param, factory, "bind")

  view = GtkListView(GtkSelectionModel(GtkSingleSelection(GLib.GListModel(model))), factory)
  list.view = view
  return list
end