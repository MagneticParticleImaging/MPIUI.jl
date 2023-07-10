mutable struct FileStorageParameter <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  fileFilter::Union{String, Nothing}
end

getindex(m::FileStorageParameter, w::AbstractString) = G_.get_object(m.builder, w)

function FileStorageParameter(scanner::Union{MPIScanner, Nothing})
  return FileStorageParameter("")
end

function FileStorageParameter(filename::String, fileFilter::Union{String, Nothing} = nothing)
  uifile = joinpath(@__DIR__,"..","..","builder","fileStorageParameter.ui")
  b = GtkBuilder(uifile)
  mainBox = G_.get_object(b, "boxParams")
  storage = FileStorageParameter(mainBox.handle, b, fileFilter)
  Gtk4.gobject_move_ref(storage, mainBox)
  set_gtk_property!(storage["entFilename"], :text, filename)

  signal_connect(storage["btnSaveAs", GtkButton], :clicked) do w
    name = save_dialog("Choose a file name", mpilab[]["mainWindow"], (storage.fileFilter,))
    if !isnothing(name)
      @idle_add_guarded set_gtk_property!(storage["entFilename"], :text, name)
    end
  end
  return storage
end

filename(params::FileStorageParameter) = get_gtk_property(params["entFilename"], :text, String)