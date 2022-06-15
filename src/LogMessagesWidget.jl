export LogMessageListWidget, LogMessageWidget, WidgetLogger, min_enabled_level, shoudlog, handle_message  

abstract type LogMessageWidget <: Gtk.GtkBox end

mutable struct LogMessageFilter
  messageFilter::Union{Regex, Nothing}
  minLevel::Int
  groups::Dict{String, Bool}
  from::Union{DateTime, Nothing}
  to::Union{DateTime, Nothing}
end

function apply(filter::LogMessageFilter, logLevel::Integer, group::String, message::String, time::DateTime)
  if logLevel < filter.minLevel
    return false
  end

  if !isnothing(filter.messageFilter) && !occursin(filter.messageFilter, message)
    return false
  end

  if !get(filter.groups, group, true)
    return false
  end

  if !isnothing(filter.from) && time < filter.from
    return false
  end

  if !isnothing(filter.to) && time >= filter.to
    return false
  end

  return true
end

function updateGroup!(filter::LogMessageFilter, group::String, visible::Bool)
  filter.groups[group] = visible
end
hasGroup(filter::LogMessageFilter, group::String) = haskey(filter.groups, group)

@enum AutoScrollState DETACHED ATTACHED_TOP ATTACHED_BOTTOM

mutable struct LogMessageListWidget <: LogMessageWidget
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  store
  tmSorted
  tv
  selection
  logFilter::LogMessageFilter
  scrollState::AutoScrollState
  updating::Bool
end

const LOG_LEVEL_TO_PIX = Dict(
  -1000 => "gtk-execute",
  0 => "gtk-info",
  1000 => "gtk-dialog-warning",
  2000 => "gtk-dialog-error"
)

getindex(m::LogMessageListWidget, w::AbstractString) = G_.object(m.builder, w)

function LogMessageListWidget()

  uifile = joinpath(@__DIR__,"builder","logMessagesWidget.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxLogMessages")

  # LogLevel, Time, Group, Message, visible, tooltip, "number" log level
  store = ListStore(String, String, String, String, Bool, String, Int)

  tv = TreeView(TreeModel(store))
  r0 = CellRendererPixbuf()
  r1 = CellRendererText()

  c0 = TreeViewColumn("Level", r0, Dict("stock-id" => 0))
  c1 = TreeViewColumn("Time", r1, Dict("text" => 1))
  c2 = TreeViewColumn("Group", r1, Dict("text" => 2))
  c3 = TreeViewColumn("Message", r1, Dict("text" => 3))

  for (i,c) in enumerate((c0,c1,c2,c3))
    G_.sort_column_id(c,i-1)
    G_.resizable(c,true)
    G_.max_width(c,80)
    push!(tv,c)
  end

  G_.max_width(c0,80)
  G_.max_width(c1,200)
  G_.max_width(c2,200)
  G_.max_width(c3,500)

  tmFiltered = TreeModelFilter(store)
  G_.visible_column(tmFiltered,4)
  tmSorted = TreeModelSort(tmFiltered)
  G_.model(tv, tmSorted)

  selection = G_.selection(tv)

  logFilter = LogMessageFilter(nothing, 0, Dict{String, Bool}(), nothing, nothing)
  m = LogMessageListWidget(mainBox.handle, b, store, tmSorted, tv, selection, logFilter, DETACHED, false)
  Gtk.gobject_move_ref(m, mainBox)

  push!(m["wndMessages"], tv)

  # Set calendar and time to now!
  initCallbacks(m::LogMessageListWidget)

  showall(tv)
  return m
end

function initCallbacks(m::LogMessageListWidget)
  signal_connect(m["calFrom"], :day_selected) do w
    @idle_add_guarded begin
      dt = getFromDateTime(m)
      m.logFilter.from = dt
      applyFilter!(m)
    end
  end
  signal_connect(m["spinFromHour"], :value_changed) do w
    @idle_add_guarded begin
      dt = getFromDateTime(m)
      m.logFilter.from = dt
      applyFilter!(m)
    end
  end
  signal_connect(m["spinFromMin"], :value_changed) do w
    @idle_add_guarded begin
      dt = getFromDateTime(m)
      m.logFilter.from = dt
      applyFilter!(m)
    end
  end

  signal_connect(m["calTo"], :day_selected) do w
    @idle_add_guarded begin
      dt = getToDateTime(m)
      m.logFilter.to = dt
      applyFilter!(m)
    end
  end
  signal_connect(m["spinToHour"], :value_changed) do w
    @idle_add_guarded begin
      dt = getToDateTime(m)
      m.logFilter.to = dt
      applyFilter!(m)
    end
  end
  signal_connect(m["spinToMin"], :value_changed) do w
    @idle_add_guarded begin
      dt = getToDateTime(m)
      m.logFilter.to = dt
      applyFilter!(m)
    end
  end

  signal_connect(m["entryMsgRegex"], :changed) do w
    @idle_add_guarded begin
      str = get_gtk_property(m["entryMsgRegex"],:text,String)
      if isempty(str)
        m.logFilter.messageFilter = nothing
      else
        rgx = Regex(".*$str.*")
        m.logFilter.messageFilter = rgx
      end
      applyFilter!(m)
    end
  end

  signal_connect(m["cbLogLevel"], :changed) do w
    @idle_add_guarded begin
      str = Gtk.bytestring(GAccessor.active_text(m["cbLogLevel"]))
      level = 0
      if str == "Debug"
        level = -1000
      elseif str == "Info"
        level = 0
      elseif str == "Warning"
        level = 1000
      elseif str == "Error"
        level = 2000
      end
      m.logFilter.minLevel = level
      applyFilter!(m)
    end
  end

  signal_connect(m["btnDelete"], :clicked) do w
    @idle_add_guarded begin
      m.updating = true
      unselectall!(m.selection)
      empty!(m.store)
      m.updating = false
    end
  end

  signal_connect(m["btnDir"], :clicked) do w
    @idle_add_guarded begin
      openFileBrowser(logpath)
    end
  end

  signal_connect(m.selection, :changed) do w
    if hasselection(m.selection) && !m.updating
      @idle_add_guarded begin
        current = selected(m.selection)
        tooltip = TreeModel(m.tmSorted)[current, 6]
        set_gtk_property!(m.tv, :tooltip_text, tooltip)
      end
    end
  end

  # Autoscrolling
  signal_connect(m["wndMessages"], :edge_reached) do w, pos
    if pos == 3
      m.scrollState = ATTACHED_BOTTOM
    else
      m.scrollState = ATTACHED_TOP
    end
  end

  vadj = get_gtk_property(m["wndMessages"], :vadjustment, GtkAdjustment)
  signal_connect(vadj, :value_changed) do w
    newValue = get_gtk_property(vadj, :value, Float64)
    if newValue != (get_gtk_property(vadj, :upper, Float64) - get_gtk_property(vadj, :page_size, Float64)) && newValue != get_gtk_property(vadj, :lower, Float64)
      m.scrollState = DETACHED
    end
  end

  signal_connect(m.tv, :size_allocate) do w, a
    @idle_add_guarded begin
      m.updating = true
      if m.scrollState == ATTACHED_BOTTOM
        set_gtk_property!(vadj, :value, get_gtk_property(vadj, :upper, Float64) - get_gtk_property(vadj, :page_size, Float64))
      elseif m.scrollState == ATTACHED_TOP
        set_gtk_property!(vadj, :value, 0)
      end
      m.updating = false
    end
  end
end

function getToDateTime(widget::LogMessageListWidget)
  year = get_gtk_property(widget["calTo"], :year, Int)
  month = get_gtk_property(widget["calTo"], :month, Int) + 1 # Month is 0 ... 11
  day = get_gtk_property(widget["calTo"], :day, Int)
  hour = get_gtk_property(widget["spinToHour"], :value, Int)
  min = get_gtk_property(widget["spinToMin"], :value, Int)
  return DateTime(year, month, day, hour, min)
end

function getFromDateTime(widget::LogMessageListWidget)
  year = get_gtk_property(widget["calFrom"], :year, Int)
  month = get_gtk_property(widget["calFrom"], :month, Int) + 1 # Month is 0 ... 11
  day = get_gtk_property(widget["calFrom"], :day, Int)
  hour = get_gtk_property(widget["spinFromHour"], :value, Int)
  min = get_gtk_property(widget["spinFromMin"], :value, Int)
  return DateTime(year, month, day, hour, min)
end

function addGroupCheckBox(widget::LogMessageListWidget, group::String)
  # Add to group immidiately to avoid multiple checkbuttons
  updateGroup!(widget.logFilter, group, true)
  @idle_add_guarded begin
    check = GtkCheckButton(group)
    set_gtk_property!(check, :active, true)
    signal_connect(check, :toggled) do w
      @idle_add_guarded begin
        updateGroup!(widget.logFilter, get_gtk_property(check, :label, String), get_gtk_property(check, :active, Bool))
        applyFilter!(widget)
      end
    end
    push!(widget["boxGroups"], check)
    showall(widget["boxGroups"])
  end
end

function applyFilter!(widget::LogMessageListWidget)
  @idle_add_guarded begin
    widget.updating = true
    try
      unselectall!(widget.selection)
      for l=1:length(widget.store)
        dateTime = DateTime(widget.store[l, 2], dateTimeFormatter)
        visible = apply(widget.logFilter, widget.store[l, 7], widget.store[l, 3], widget.store[l, 4], dateTime)
        widget.store[l, 5] = visible
      end
    catch e
      @warn "Could not update log filter" e
    end
    widget.updating = false
  end
end

function updateMessage!(widget::LogMessageListWidget, level::Base.LogLevel, dateTime::Union{DateTime, Missing}, group, message, filepath, line; kwargs...)
  try 
    messageString = string(message)
    
    if ismissing(dateTime)
      dateTimeString = "N/A"
    else 
      dateTimeString = Dates.format(dateTime, dateTimeFormatter)
    
    end
    visible = apply(widget.logFilter, level.level, string(group), messageString, dateTime)
    
    groupString = string(group)
    if !hasGroup(widget.logFilter, groupString)
      addGroupCheckBox(widget, groupString)
    end
    
    lineString = string(filepath, ":", string(line))
    keyVals = [string(string(key), " = ", string(val)) for (key, val) in kwargs]
    if isempty(keyVals)
      tooltip = lineString
    else
      tooltip = join(insert!(keyVals, 1, lineString), "\n")
    end
    tooltip = tooltip[1:min(end, 1024)]

    @idle_add_guarded begin
      push!(widget.store, (get(LOG_LEVEL_TO_PIX, level.level, "gtk-missing-image"), dateTimeString, groupString, messageString, visible, tooltip, level.level))
    end
  catch ex
    # Avoid endless loop
    with_logger(ConsoleLogger()) do 
      @warn "Could not buffer log message" ex
    end
  end
end

struct WidgetLogger <: Base.AbstractLogger
  widget::LogMessageWidget
end

shouldlog(logger::WidgetLogger, args...) = true
min_enabled_level(logger::WidgetLogger) = Base.LogLevel(-1000)

function handle_message(logger::WidgetLogger, level::LogLevel, message, _module, group, id, filepath, line; kwargs...)
  # TODO Check if widget is still open/exists?
  dateTime = missing
  for (key, val) in kwargs
    if key === :dateTime
      dateTime = val
    end
  end
  kwargsFiltered = [p for p in pairs(kwargs) if p[1] != :dateTime]
  #@show kwar
  updateMessage!(logger.widget, level, dateTime, group, message, filepath, line; kwargsFiltered...)
end