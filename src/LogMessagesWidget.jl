export LogMessageListWidget, LogMessageWidget, WidgetLogger, min_enabled_level, shoudlog, handle_message  

abstract type LogMessageWidget <: Gtk.GtkBox end

mutable struct LogMessageListWidget <: LogMessageWidget
  handle::Ptr{Gtk.GObject}
  store
  tv
  updating::Bool
end

function LogMessageListWidget()

  uifile = joinpath(@__DIR__,"builder","logMessagesWidget.ui")

  b = Builder(filename=uifile)
  mainBox = G_.object(b, "boxLogMessages")

  # LogLevel, Time, Group, Message, filepath, line
  store = ListStore(Int, String, String, String, String, String)


  m = LogMessageListWidget(mainBox.handle, store, nothing, false)
  Gtk.gobject_move_ref(m, mainBox)

end


function updateMessage!(widget::LogMessageListWidget, level::Base.LogLevel, dateTime::Union{DateTime, Missing}, group, message, filepath, line)
  try 
    messageString = string(message)
    if ismissing(dateTime)
      dateTimeString = "N/A"
    else 
      dateTimeString = Dates.format(dateTime, "yyyy-mm-dd HH:MM:SS.ss")
    end
    push!(widget.store, (level.level, dateTimeString, string(group), messageString, string(filepath), string(line)))
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