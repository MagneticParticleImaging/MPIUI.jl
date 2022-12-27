include("Parameters/Parameters.jl")
include("DataHandler/DataHandler.jl")

mutable struct ProtocolWidget{T} <: Gtk4.GtkBox
  # Gtk 
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  paramGtkBuilder::Dict
  updating::Bool
  # Protocol Interaction
  scanner::T
  protocol::Union{Protocol, Nothing}
  biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing}
  eventHandler::Union{Timer, Nothing}
  protocolState::MPIMeasurements.ProtocolState
  # Display
  progress::Union{ProgressEvent, Nothing}
  dataHandler::Union{Nothing, Vector{AbstractDataHandler}}
  eventQueue::Vector{AbstractDataHandler}
end

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
    
  b = GtkBuilder(filename=uifile)
  mainBox = object_(b, "boxProtocol",BoxLeaf)

  paramGtkBuilder = Dict(:sequence => "expSequence", :positions => "expPositions")

  pw = ProtocolWidget(mainBox.handle, b, paramBuilder, false, scanner, protocol, nothing, nothing, PS_UNDEFINED,
        nothing, nothing, AbstractDataHandler[])
  Gtk4.GLib.gobject_move_ref(pw, mainBox)

  @idle_add_guarded begin
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
  if pw.progress.total == 0 || isnan(fraction) || isinf(fraction)
    @idle_add_guarded begin
      set_gtk_property!(pw["pbProtocol", ProgressBar], :text, progress)
      set_gtk_property!(pw["pbProtocol", ProgressBar], "pulse_step", 0.3)
      pulse(pw["pbProtocol", ProgressBar])
    end
  else
    @idle_add_guarded begin
      set_gtk_property!(pw["pbProtocol", ProgressBar], :text, progress)
      set_gtk_property!(pw["pbProtocol", ProgressBar], :fraction, fraction)
    end
  end  
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
          @idle_add_guarded begin
            pw.updating = true
            est = timeEstimate(pw.protocol)
            set_gtk_property!(pw["lblRuntime", GtkLabelLeaf], :label, est)
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
          @idle_add_guarded begin 
            pw.updating = true
            set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :sensitive, false)
            set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
            set_gtk_property!(pw["tbCancel",ToolButtonLeaf], :sensitive, true)
            set_gtk_property!(pw["btnPickProtocol", GtkButtonLeaf], :sensitive, false)
            pw.updating = false
          end
        else
          @idle_add_guarded begin
            # Something went wrong during start, we dont count button press
            set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :active, false)
          end
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
      @idle_add_guarded set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, false)
    end
  end

  signal_connect(pw["tbCancel", ToolButtonLeaf], :clicked) do w
    tryCancelProtocol(pw)
  end

  signal_connect(pw["btnPickProtocol", GtkButton], "clicked") do w
    @info "clicked picked protocol button"
    dlg = ProtocolSelectionDialog(pw.scanner, Dict())
    ret = run(dlg)
    if ret == Gtk4.ResponseType_ACCEPT
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
      filter = Gtk4.GtkFileFilter(pattern=String("*.toml"))
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
      @idle_add_guarded set_gtk_property!(pw["btnSaveProtocol", GtkButton], :sensitive, true)
    end
  end

  #for adj in ["adjNumFrames", "adjNumAverages", "adjNumFrameAverages", "adjNumBGFrames"]
  #  signal_connect(pw[adj, Gtk4.GtkAdjustmentLeaf], "value_changed") do w
  #    if !pw.updating
  #      @idle_add_guarded set_gtk_property!(pw["btnSaveProtocol", GtkButton], :sensitive, true)
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
  @info "Updating protocol"
  @idle_add_guarded begin
    pw.updating = true
    pw.protocol = protocol
    updateProtocolDataHandler(pw, protocol)
    updateProtocolParameter(pw, protocol)
    pw.updating = false
  end
end

function updateProtocolDataHandler(pw::ProtocolWidget, protocol::Protocol)
  nb = pw["nbDataWidgets", Notebook]
  paramBox = pw["boxGUIParams", GtkBox]
  storageBox = pw["boxStorageParams", GtkBox]
  #empty!(nb) # segfaults sometimes
  numPages = G_.n_pages(nb)
  for i = 1:numPages
    splice!(nb, numPages-i+1)
  end
  empty!(paramBox)
  empty!(storageBox)
  handlers = AbstractDataHandler[]
  for (i, handlerType) in enumerate(defaultDataHandler(protocol))
    # TODO what common constructor do we need
    handler = handlerType(pw.scanner)
    push!(handlers, handler)
    display = getDisplayWidget(handler)
    if isnothing(display)
      display = Box(:v)
    end
    push!(nb, display, getDisplayTitle(handler))
    storage = getStorageWidget(handler)
    if !isnothing(storage)
      storageExpander = Gtk.GtkExpander(getStorageTitle(handler))
      set_gtk_property!(storageExpander, :expand, true)
      push!(storageExpander, storage)
      push!(storageBox, storageExpander)
    end
    paramExpander = ParamExpander(handler)
    push!(paramBox, paramExpander)
    showall(paramExpander)
    showall(display)
    set_gtk_property!(paramExpander, :expand, i == 1) # This does not expand
    enable!(paramExpander, i == 1)
  end
  pw.dataHandler = handlers
  showall(paramBox)
  showall(storageBox)
  showall(nb)
end

function updateProtocolParameter(pw::ProtocolWidget, protocol::Protocol)
  params = protocol.params
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
  showall(pw["boxProtocolParameter", BoxLeaf])
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
    push!(pw["boxProtocolParameter", Gtk4.GtkBoxLeaf], paramGrid)
  catch ex 
    @error ex
  end
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, field, value, tooltip)
  generic = GenericParameter{typeof(value)}(field, string(field), string(value), tooltip)
  addGenericCallback(pw, generic.entry)
  push!(pw["boxProtocolParameter", Gtk4.GtkBoxLeaf], generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, field, value::T, tooltip) where {T<:Quantity}
  generic = UnitfulParameter(field, string(field), value, tooltip)
  addGenericCallback(pw, generic.entry)
  push!(pw["boxProtocolParameter", Gtk4.GtkBoxLeaf], generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::BoolParameterType, field, value, tooltip)
  cb = BoolParameter(field, string(field), value, tooltip)
  addGenericCallback(pw, cb)
  push!(pw["boxProtocolParameter", Gtk4.GtkBoxLeaf], cb)
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, regParams::RegularParameters, field::Symbol, value, tooltip)
  label = ParameterLabel(field, tooltip)
  generic = GenericEntry{typeof(value)}(string(value))
  addGenericCallback(pw, generic)
  addToRegularParams(regParams, label, generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, regParams::RegularParameters, field::Symbol, value::T, tooltip) where {T<:Quantity}
  label = ParameterLabel(field, tooltip)
  generic = UnitfulGtkEntry(value)
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
  push!(pw["boxProtocolParameter", Gtk4.GtkBoxLeaf], seq)
end

function addProtocolParameter(pw::ProtocolWidget, ::ReconstructionParameterType, field, value, tooltip)
  reco = OnlineRecoWidget(field)
  push!(pw["boxProtocolParameter", BoxLeaf], reco)
end

function addProtocolParameter(pw::ProtocolWidget, ::CoordinateParameterType, field, value, tooltip)
  coord = CoordinateParameter(field, value, tooltip)
  updateCoordinate(coord, value)
  push!(pw["boxProtocolParameter", Gtk4.GtkBoxLeaf], coord)
end

function addProtocolParameter(pw::ProtocolWidget, ::PositionParameterType, field, value, tooltip)
  pos = PositionParameter(field, value)
  updatePositions(pos, value)
  push!(pw["boxProtocolParameter", Gtk4.GtkBoxLeaf], pos)
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
      @idle_add_guarded set_gtk_property!(pw["btnSaveProtocol", GtkButton], :sensitive, true)
    end
  end
end

function addGenericCallback(pw::ProtocolWidget, cb::BoolParameter)
  signal_connect(cb, "toggled") do w
    if !pw.updating
      @idle_add_guarded set_gtk_property!(pw["btnSaveProtocol", GtkButton], :sensitive, true)
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

function updateStudy(m::ProtocolWidget, name, date)
  for handler in m.dataHandler
    updateStudy(handler, name, date)
  end
end


function isMeasurementStore(m::ProtocolWidget, d::DatasetStore)
  if isempty(m.dataHandler)
    return false
  else
    isStore = true
    for handler in m.dataHandler
      isStore &= isMeasurementStore(handler, d)
    end
    return isStore
  end
end

function updateScanner!(pw::ProtocolWidget, scanner::MPIScanner)
  pw.scanner = scanner
  @idle_add_guarded begin
    set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf],:sensitive,false)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf],:sensitive,false)
    set_gtk_property!(pw["tbCancel",ToolButtonLeaf],:sensitive,false)
    initProtocolChoices(pw)
  end
end