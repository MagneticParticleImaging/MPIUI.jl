export LogMessageListWidget, LogMessageWidget, WidgetLogger, min_enabled_level, shoudlog, handle_message  

abstract type LogMessageWidget <: Gtk.GtkBox end

mutable struct LogMessageListWidget <: LogMessageWidget
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  store
  tmSorted
  tv
  selection
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

  # LogLevel, Time, Group, Message, visible
  store = ListStore(String, String, String, String, Bool)

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

  m = LogMessageListWidget(mainBox.handle, b, store, tmSorted, tv, selection, false)
  Gtk.gobject_move_ref(m, mainBox)

  push!(m["wndMessages"], tv)

  showall(tv)
  return m
end


function updateMessage!(widget::LogMessageListWidget, level::Base.LogLevel, dateTime::Union{DateTime, Missing}, group, message, filepath, line)
  try 
    messageString = string(message)
    if ismissing(dateTime)
      dateTimeString = "N/A"
    else 
      dateTimeString = Dates.format(dateTime, "yyyy-mm-dd HH:MM:SS.ss")
    end
    push!(widget.store, (get(LOG_LEVEL_TO_PIX, level.level, "gtk-execute"), dateTimeString, string(group), messageString, true))
  catch ex
    @warn "Could not buffer log message^"
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
  updateMessage!(logger.widget, level, dateTime, group, message, filepath, line)
end