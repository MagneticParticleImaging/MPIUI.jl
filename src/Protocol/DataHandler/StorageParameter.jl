mutable struct StorageParameter <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  # Storage
  mdfstore::MDFDatasetStore
  currStudyName::String
  currStudyDate::DateTime
end

getindex(m::StorageParameter, w::AbstractString, T::Type) = object_(m.builder, w, T)

function StorageParameter(scanner::Nothing)
  mdfstore = MDFDatasetStore(defaultdatastore)
  return StorageParameter(mdfstore)
end

function StorageParameter(scanner::MPIScanner)
  mdfstore = MDFDatasetStore( generalParams(scanner).datasetStore )
  return StorageParameter(mdfstore)
end

function StorageParameter(mdfstore::MDFDatasetStore)
  uifile = joinpath(@__DIR__,"..","..","builder","storageParams.ui")
  b = Builder(filename=uifile)
  mainBox = object_(b, "boxParams", BoxLeaf)
  storage = StorageParameter(mainBox.handle, b, mdfstore, "", now())
  Gtk.gobject_move_ref(storage, mainBox)
  return storage
end

function getStorageMDF(sp::StorageParameter)
  @info "Creating storage MDF"
  mdf = defaultMDFv2InMemory()
  studyName(mdf, sp.currStudyName)
  studyTime(mdf, sp.currStudyDate)
  studyDescription(mdf, "")
  experimentDescription(mdf, get_gtk_property(sp["entExpDescr",EntryLeaf], :text, String))
  experimentName(mdf, get_gtk_property(sp["entExpName",EntryLeaf], :text, String))
  scannerOperator(mdf, get_gtk_property(sp["entOperator",EntryLeaf], :text, String))
  tracerName(mdf, [get_gtk_property(sp["entTracerName",EntryLeaf], :text, String)])
  tracerBatch(mdf, [get_gtk_property(sp["entTracerBatch",EntryLeaf], :text, String)])
  tracerVendor(mdf, [get_gtk_property(sp["entTracerVendor",EntryLeaf], :text, String)])
  tracerVolume(mdf, [1e-3*get_gtk_property(sp["adjTracerVolume",AdjustmentLeaf], :value, Float64)])
  tracerConcentration(mdf, [1e-3*get_gtk_property(sp["adjTracerConcentration",AdjustmentLeaf], :value, Float64)])
  tracerSolute(mdf, [get_gtk_property(sp["entTracerSolute",EntryLeaf], :text, String)])
  return mdf
end