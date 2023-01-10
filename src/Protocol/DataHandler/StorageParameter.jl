mutable struct StorageParameter <: Gtk4.GtkBox
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  # Storage
  mdfstore::MDFDatasetStore
  currStudyName::String
  currStudyDate::DateTime
end

getindex(m::StorageParameter, w::AbstractString) = G_.get_object(m.builder, w)

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
  b = GtkBuilder(filename=uifile)
  mainBox = G_.get_object(b, "boxParams")
  storage = StorageParameter(mainBox.handle, b, mdfstore, "", now())
  Gtk4.GLib.gobject_move_ref(storage, mainBox)

  # Allow to change between different units for the concentration
  for c in ["mmol/L","mg/mL"]
    push!(storage["cbConc"], c)
  end
  set_gtk_property!(storage["cbConc"],:active,1) # default: mg/ml

  return storage
end

function getStorageMDF(sp::StorageParameter)
  @info "Creating storage MDF"
  mdf = defaultMDFv2InMemory()
  studyName(mdf, sp.currStudyName)
  studyTime(mdf, sp.currStudyDate)
  studyDescription(mdf, "")
  experimentDescription(mdf, get_gtk_property(sp["entExpDescr"], :text, String))
  experimentName(mdf, get_gtk_property(sp["entExpName"], :text, String))
  scannerOperator(mdf, get_gtk_property(sp["entOperator"], :text, String))
  tracerName(mdf, [get_gtk_property(sp["entTracerName"], :text, String)])
  tracerBatch(mdf, [get_gtk_property(sp["entTracerBatch"], :text, String)])
  tracerVendor(mdf, [get_gtk_property(sp["entTracerVendor"], :text, String)])
  tracerVolume(mdf, [1e-3*get_gtk_property(sp["adjTracerVolume"], :value, Float64)])
  # Concentration depends on the chosen unit 
  if get_gtk_property(sp["cbConc"], :active, Int) == 0 # mmol/L
    conc = 1e-3*get_gtk_property(sp["adjTracerConcentration"], :value, Float64)
  else # mg/mL (1 mg/mL = 17.85 mmol/L)
    conc = 17.85 * 1e-3*get_gtk_property(sp["adjTracerConcentration"], :value, Float64)
  end
  tracerConcentration(mdf, [conc])
  tracerSolute(mdf, [get_gtk_property(sp["entTracerSolute"], :text, String)])
  return mdf
end