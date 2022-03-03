mutable struct ProtocolWidget{T} <: Gtk.GtkBox
  # Gtk 
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  paramBuilder::Dict
  updating::Bool
  # Protocol Interaction
  scanner::T
  protocol::Union{Protocol, Nothing}
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing}
  eventHandler::Union{Timer, Nothing}
  protocolState::ProtocolState
  # Display
  progress::Union{ProgressEvent, Nothing}
  rawDataWidget::RawDataWidget
  # Storage
  mdfstore::MDFDatasetStore
  dataBGStore::Array{Float32,4}
  currStudyName::String
  currStudyDate::DateTime
end

include("Parameters.jl")

getindex(m::ProtocolWidget, w::AbstractString, T::Type) = object_(m.builder, w, T)

function ProtocolWidget(scanner=nothing)
  @info "Starting ProtocolWidget"
  uifile = joinpath(@__DIR__,"..","builder","protocolWidget.ui")
    
  if !isnothing(scanner)
    mdfstore = MDFDatasetStore( generalParams(scanner).datasetStore )
    protocol = Protocol(scanner.generalParams.defaultProtocol, scanner)
  else
    mdfstore = MDFDatasetStore(defaultdatastore)
    protocol = nothing
  end
    
  b = Builder(filename=uifile)
  mainBox = object_(b, "boxProtocol",BoxLeaf)

  paramBuilder = Dict(:sequence => "expSequence", :positions => "expPositions")

  pw = ProtocolWidget(mainBox.handle, b, paramBuilder, false, scanner, protocol, nothing, nothing, PS_UNDEFINED,
        nothing, RawDataWidget(), mdfstore, zeros(Float32,0,0,0,0), "", now())
  Gtk.gobject_move_ref(pw, mainBox)

  @idle_add begin
    set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf],:sensitive,false)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf],:sensitive,false)
    set_gtk_property!(pw["tbCancel",ToolButtonLeaf],:sensitive,false)      
  end
  if !isnothing(pw.scanner)
    # Load default protocol and set params
    # + dummy plotting?
    initProtocolChoices(pw)
    initCallbacks(pw)
  end

  # Dummy plotting for warmstart during protocol execution
  @idle_add begin 
    push!(pw["boxProtocolTabVisu",BoxLeaf], pw.rawDataWidget)
    set_gtk_property!(pw["boxProtocolTabVisu",BoxLeaf],:expand, pw.rawDataWidget, true)  
    updateData(pw.rawDataWidget, ones(Float32,10,1,1,1), 1.0)
    showall(pw.rawDataWidget)
  end

  @info "Finished starting ProtocolWidget"
  return pw
end

function displayProgress(pw::ProtocolWidget)
  progress = "N/A"
  fraction = 0.0
  if !isnothing(pw.progress) && pw.protocolState == PS_RUNNING
    progress = "$(pw.progress.unit) $(pw.progress.done)/$(pw.progress.total)"
    fraction = pw.progress.done/pw.progress.total
  elseif pw.protocolState == PS_FINISHED
    progress = "FINISHED"
    fraction = 1.0
  end
  @idle_add begin
    set_gtk_property!(pw["pbProtocol", ProgressBar], :text, progress)
    set_gtk_property!(pw["pbProtocol", ProgressBar], :fraction, fraction)
  end
end

function getStorageMDF(pw::ProtocolWidget)
  mdf = defaultMDFv2InMemory()
  studyName(mdf, pw.currStudyName) # TODO These are never updates, is the result correct?
  studyDate(mdf, pw.currStudyDate )
  studyDescription(mdf, "")
  experimentDescription(mdf, get_gtk_property(pw["entExpDescr",EntryLeaf], :text, String))
  experimentName(mdf, get_gtk_property(pw["entExpName",EntryLeaf], :text, String))
  scannerOperator(mdf, get_gtk_property(pw["entOperator",EntryLeaf], :text, String))
  tracerName(mdf, [get_gtk_property(pw["entTracerName",EntryLeaf], :text, String)])
  tracerBatch(mdf, [get_gtk_property(pw["entTracerBatch",EntryLeaf], :text, String)])
  tracerVendor(mdf, [get_gtk_property(pw["entTracerVendor",EntryLeaf], :text, String)])
  tracerVolume(mdf, [1e-3*get_gtk_property(pw["adjTracerVolume",AdjustmentLeaf], :value, Float64)])
  tracerConcentration(mdf, [1e-3*get_gtk_property(pw["adjTracerConcentration",AdjustmentLeaf], :value, Float64)])
  tracerSolute(mdf, [get_gtk_property(pw["entTracerSolute",EntryLeaf], :text, String)])
  return params
end

include("EventHandler.jl")
include("SequenceBrowser.jl")
include("ProtocolBrowser.jl")

function initCallbacks(pw::ProtocolWidget)
  signal_connect(pw["tbInit", ToolButtonLeaf], :clicked) do w
    if !pw.updating
      if !isnothing(pw.eventHandler) && isopen(pw.eventHandler)
        message = "Event handler is still running. Cannot initialize new protocol"
        @warn message
        info_dialog(message, mpilab[]["mainWindow"])
      else
        if initProtocol(pw)
          @idle_add begin
            pw.updating = true
            est = timeEstimate(pw.protocol)
            set_gtk_property!(pw["lblRuntime", LabelLeaf], :label, est)
            set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :sensitive, true)
            pw.updating = false
          end        
        end
      end
    end
  end

  signal_connect(pw["tbRun", ToggleToolButtonLeaf], :toggled) do w
    if !pw.updating
      if get_gtk_property(w, :active, Bool)
        if startProtocol(pw)
          @idle_add begin 
            pw.updating = true
            set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :sensitive, false)
            set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
            set_gtk_property!(pw["tbCancel",ToolButtonLeaf], :sensitive, true)
            set_gtk_property!(pw["btnPickProtocol", ButtonLeaf], :sensitive, false)
            pw.updating = false
          end
        else
          # Something went wrong during start, we dont count button press
          set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :active, false)
        end
      else
        endProtocol(pw)  
      end
    end
  end

  signal_connect(pw["tbPause", ToggleToolButtonLeaf], :toggled) do w
    if !pw.updating
      if get_gtk_property(w, :active, Bool)
        tryPauseProtocol(pw)
      else 
        tryResumeProtocol(pw)
      end
      @idle_add set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, false)
    end
  end

  signal_connect(pw["tbCancel", ToolButtonLeaf], :clicked) do w
    tryCancelProtocol(pw)
  end

  signal_connect(pw["btnPickProtocol", GtkButton], "clicked") do w
    @info "clicked picked protocol button"
    dlg = ProtocolSelectionDialog(pw.scanner, Dict())
    ret = run(dlg)
    if ret == GtkResponseType.ACCEPT
      if hasselection(dlg.selection)
        protocol = getSelectedProtocol(dlg)
        updateProtocol(pw, protocol)
        end
    end
    destroy(dlg)
  end

  signal_connect(pw["btnSaveProtocol", GtkButton], "clicked") do w
    try 
      # TODO try to pick protocol folder of current scanner?
      filter = Gtk.GtkFileFilter(pattern=String("*.toml"))
      fileName = save_dialog("Save Protocol", GtkNullContainer(), (filter, ))
      if fileName != ""
        saveProtocol(pw::ProtocolWidget, fileName)
      end
    catch e
      @info e
      showError(e)
    end
  end

  signal_connect(pw["txtBuffProtocolDescription", GtkTextBufferLeaf], :changed) do w
    if !pw.updating
      @idle_add set_gtk_property!(pw["btnSaveProtocol", Button], :sensitive, true)
    end
  end

  #for adj in ["adjNumFrames", "adjNumAverages", "adjNumFrameAverages", "adjNumBGFrames"]
  #  signal_connect(pw[adj, AdjustmentLeaf], "value_changed") do w
  #    if !pw.updating
  #      @idle_add set_gtk_property!(pw["btnSaveProtocol", Button], :sensitive, true)
  #    end
  #  end
  #end

end

function initProtocolChoices(pw::ProtocolWidget)
  pw.updating = true
  scanner = pw.scanner
  protocolName = scanner.generalParams.defaultProtocol
  protocol = Protocol(protocolName, pw.scanner)
  updateProtocol(pw, protocol)
  pw.updating = false
end

function updateProtocol(pw::ProtocolWidget, protocol::AbstractString)
  p = Protocol(protocol, pw.scanner)
  updateProtocol(pw, p)
end

function updateProtocol(pw::ProtocolWidget, protocol::Protocol)
  params = protocol.params
  @info "Updating protocol"
  @idle_add begin
    pw.updating = true
    pw.protocol = protocol
    set_gtk_property!(pw["lblScannerName", GtkLabelLeaf], :label, name(pw.scanner))
    set_gtk_property!(pw["lblProtocolType", GtkLabelLeaf], :label, string(typeof(protocol)))
    set_gtk_property!(pw["txtBuffProtocolDescription", GtkTextBufferLeaf], :text, MPIMeasurements.description(protocol))
    set_gtk_property!(pw["lblProtocolName", GtkLabelLeaf], :label, name(protocol))
    # Clear old parameters
    empty!(pw["boxProtocolParameter", BoxLeaf])

    regular = [field for field in fieldnames(typeof(params)) if parameterType(field, nothing) isa RegularParameterType]
    special = setdiff(fieldnames(typeof(params)), regular)
    addRegularProtocolParameter(pw, params, regular)

    for field in special
      try 
        value = getfield(params, field)
        tooltip = string(fielddoc(typeof(params), field))
        if contains(tooltip, "has field") #fielddoc for fields with no docstring returns "Type x has fields ..." listing all fields with docstring
          tooltip = nothing
        end
        addProtocolParameter(pw, parameterType(field, value), field, value, tooltip)
        @info "Added $field"
      catch ex
        @error ex
      end
    end

    set_gtk_property!(pw["btnSaveProtocol", Button], :sensitive, false)
    pw.updating = false
    showall(pw["boxProtocolParameter", BoxLeaf])
  end
end

function addRegularProtocolParameter(pw::ProtocolWidget, params::ProtocolParams, fields::Vector{Symbol})
  try 
    paramGrid = RegularParameters()
    for field in fields
      value = getfield(params, field)
      tooltip = string(fielddoc(typeof(params), field))
      if contains(tooltip, "has field") #fielddoc for fields with no docstring returns "Type x has fields ..." listing all fields with docstring
        tooltip = nothing
      end
      addProtocolParameter(pw, parameterType(field, value), paramGrid, field, value, tooltip)
    end
    push!(pw["boxProtocolParameter", BoxLeaf], paramGrid)
  catch ex 
    @error ex
  end
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, field, value, tooltip)
  generic = GenericParameter{typeof(value)}(field, string(field), string(value), tooltip)
  addGenericCallback(pw, generic.entry)
  push!(pw["boxProtocolParameter", BoxLeaf], generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, field, value::T, tooltip) where {T<:Quantity}
  generic = UnitfulParameter(field, string(field), value, tooltip)
  addGenericCallback(pw, generic.entry)
  push!(pw["boxProtocolParameter", BoxLeaf], generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::BoolParameterType, field, value, tooltip)
  cb = BoolParameter(field, string(field), value, tooltip)
  addGenericCallback(pw, cb)
  push!(pw["boxProtocolParameter", BoxLeaf], cb)
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, regParams::RegularParameters, field::Symbol, value, tooltip)
  label = ParameterLabel(field, tooltip)
  generic = GenericEntry{typeof(value)}(string(value))
  addGenericCallback(pw, generic)
  addToRegularParams(regParams, label, generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, regParams::RegularParameters, field::Symbol, value::T, tooltip) where {T<:Quantity}
  label = ParameterLabel(field, tooltip)
  generic = UnitfulEntry(value)
  addGenericCallback(pw, generic.entry)
  addToRegularParams(regParams, label, generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::BoolParameterType, regParams::RegularParameters, field::Symbol, value, tooltip)
  label = ParameterLabel(field, tooltip)
  cb = BoolParameter(field, string(field), value, tooltip)
  addGenericCallback(pw, cb)
  addToRegularParams(regParams, label, cb)
end

function addToRegularParams(regParams::RegularParameters, label::ParameterLabel, object::GObject)
  index = length(regParams.paramDict) + 1
  regParams[1, index] = label
  regParams[2, index] = object
  regParams.paramDict[label.field] = object
end

function addToRegularParams(regParams::RegularParameters, label::ParameterLabel, object::BoolParameter)
  index = length(regParams.paramDict) + 1
  regParams[1:2, index] = object
  regParams.paramDict[label.field] = object
end

function addProtocolParameter(pw::ProtocolWidget, ::SequenceParameterType, field, value::Sequence, tooltip)
  seq = SequenceParameter(field, value, pw.scanner)
  updateSequence(seq, value) # Set default sequence values
  push!(pw["boxProtocolParameter", BoxLeaf], seq)
end

function addProtocolParameter(pw::ProtocolWidget, ::PositionParameterType, field, value, tooltip)
  pos = PositionParameter(field, value)
  updatePositions(pos, value)
  push!(pw["boxProtocolParameter", BoxLeaf], pos)
end

function addTooltip(object, tooltip::AbstractString)
  set_gtk_property!(object, :tooltip_text, tooltip)
end

function addTooltip(object, tooltip::Nothing)
    # NOP
end

function addGenericCallback(pw::ProtocolWidget, generic)
  signal_connect(generic, "changed") do w
    if !pw.updating
      @idle_add set_gtk_property!(pw["btnSaveProtocol", Button], :sensitive, true)
    end
  end
end

function addGenericCallback(pw::ProtocolWidget, cb::BoolParameter)
  signal_connect(cb, "toggled") do w
    if !pw.updating
      @idle_add set_gtk_property!(pw["btnSaveProtocol", Button], :sensitive, true)
    end
  end
end

### File Interaction ###
function saveProtocol(pw::ProtocolWidget, fileName::AbstractString)
  @info "Saving protocol to $fileName"
  # TODO Serialize into protocol
  # TODO Update protocol selection
  # TODO Pick new protocol
end

function isMeasurementStore(m::ProtocolWidget, d::DatasetStore)
  if isnothing(m.mdfstore)
    return false
  else
    return d.path == m.mdfstore.path
  end
end