mutable struct FileStorageParameter <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  fileFilter::Union{String, Nothing}
end

getindex(m::FileStorageParameter, w::AbstractString, T::Type) = object_(m.builder, w, T)

function FileStorageParameter(scanner::Union{MPIScanner, Nothing})
  return FileStorageParameter("")
end

function FileStorageParameter(filename::String, fileFilter::Union{String, Nothing} = nothing)
  uifile = joinpath(@__DIR__,"..","..","builder","fileStorageParameter.ui")
  b = Builder(filename=uifile)
  mainBox = object_(b, "boxParams", BoxLeaf)
  storage = FileStorageParameter(mainBox.handle, b, fileFilter)
  Gtk.gobject_move_ref(storage, mainBox)
  set_gtk_property!(storage["entFilename", EntryLeaf], :text, filename)

  signal_connect(storage["btnSaveAs", GtkButton], :clicked) do w
    name = save_dialog("Choose a file name", mpilab[]["mainWindow"], (storage.fileFilter,))
    if !isnothing(name)
      @idle_add_guarded set_gtk_property!(storage["entFilename", EntryLeaf], :text, name)
    end
  end
  return storage
end

filename(params::FileStorageParameter) = get_gtk_property(params["entFilename", EntryLeaf], :text, String)