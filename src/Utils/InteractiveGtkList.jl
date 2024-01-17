abstract type AbstractGrowableListEntry end

mutable struct GrowableGtkList <: AbstractArray{GtkWidget, 1}
  list::GtkListBox
  entries::Vector{AbstractGrowableListEntry}
  provider
  function GrowableGtkList(provider = () -> GtkEntry())
    list = GtkListBox()
    list.vexpand = true
    list.hexpand = true
    list.show_separators = true
    grow = new(list, GrowableListEntry[], provider)
    addEmptyEntry!(grow)
    return grow
  end
end
size(list::GrowableGtkList) = size(list.entries)
getindex(list::GrowableGtkList, i) = list.list[i]

function insert!(list::GrowableGtkList, i, item)
  entry = GrowableListEntry(item, list)
  insert!(list.entries, i, entry)
  insert!(list.list, i, widget(entry))
end

function deleteat!(list::GrowableGtkList, index)
  deleteat!(list.entries, index)
  delete!(list.list, list.list[index]) # deleteat! does not exist for ListBox
  if isempty(list.entries)
    addEmptyEntry!(list)
  end
end

function addEmptyEntry!(list::GrowableGtkList)
  empty = EmptyListEntry(list)
  push!(list.list, widget(empty))
  push!(list.entries, empty)
end

struct EmptyListEntry <: AbstractGrowableListEntry
  parent::GrowableGtkList
  btnAdd::GtkButton
  function EmptyListEntry(parent)
    add = GtkButton()
    add.icon_name = "list-add"
    entry = new(parent, add)
    signal_connect(add, :clicked) do btn
      item = parent.provider()
      insert!(parent, 1, item)
      # If delete happens before insert, the list adds a new empty element
      deleteat!(parent, 2)
    end
    return entry
  end
end
widget(entry::EmptyListEntry) = entry.btnAdd

mutable struct GrowableListEntry{T} <: AbstractGrowableListEntry where T
  widget::T
  grid::GtkGrid
  parent::GrowableGtkList
  btnAddBefore::GtkButton
  btnAddAfter::GtkButton
  btnDel::GtkButton
  function GrowableListEntry(widget::T, parent) where T
    grid = GtkGrid()

    before = GtkButton()
    after = GtkButton()
    del = GtkButton()
    del.vexpand = true

    grid[1, 1] = before
    grid[1, 2] = del
    grid[1, 3] = after
    grid[2, 1:3] = GtkSeparator(:v)
    grid[3, 1:3] = widget
    entry = new{T}(widget, grid, parent, before, after, del)

    before.icon_name = "list-add"
    signal_connect(before, :clicked) do btn
      item = parent.provider()
      index = findfirst(x-> x == entry, parent.entries)
      insert!(parent, index, item)
    end

    after.icon_name = "list-add"
    signal_connect(after, :clicked) do btn
      item = parent.provider()
      index = findfirst(x-> x == entry, parent.entries) + 1
      insert!(parent, index, item)
    end

    del.icon_name = "list-remove"
    signal_connect(del, :clicked) do btn
      index = findfirst(x-> x == entry, parent.entries)
      deleteat!(parent, index)
    end

    return entry
  end
end
widget(entry::GrowableListEntry) = entry.grid