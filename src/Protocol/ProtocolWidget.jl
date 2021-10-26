@enum ProtocolState UNDEFINED INIT RUNNING PAUSED FINISHED FAILED

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

getindex(m::ProtocolWidget, w::AbstractString, T::Type) = object_(m.builder, w, T)

abstract type ParameterType end
abstract type SpecialParameterType <: ParameterType end
abstract type RegularParameterType <: ParameterType end
struct GenericParameterType <: RegularParameterType end
struct SequenceParameterType <: SpecialParameterType end
struct PositionParameterType <: SpecialParameterType end
struct BoolParameterType <: RegularParameterType end
function parameterType(field::Symbol, value)
  if field == :sequence
    return SequenceParameterType()
  elseif field == :positions
    return PositionParameterType()
  else
    return GenericParameterType()
  end
end
function parameterType(::Symbol, value::Bool)
    return BoolParameterType()
end

mutable struct GenericEntry{T} <: Gtk.GtkEntry
  handle::Ptr{Gtk.GObject}
  entry::GtkEntry
  function GenericEntry{T}(value::AbstractString) where {T}
    entry = GtkEntry()
    set_gtk_property!(entry, :text, value)
    set_gtk_property!(entry, :hexpand, true)
    generic = new(entry.handle, entry)
    return Gtk.gobject_move_ref(generic, entry)
  end
end

function value(entry::GenericEntry{T}) where {T}
  valueString = get_gtk_property(entry, :text, String)
  return tryparse(T, valueString)
end

mutable struct GenericParameter{T} <: Gtk.GtkGrid
  handle::Ptr{Gtk.GObject}
  field::Symbol
  label::GtkLabel
  entry::GenericEntry{T}

  function GenericParameter{T}(field::Symbol, label::AbstractString, value::AbstractString, tooltip::Union{Nothing, AbstractString} = nothing) where {T}
    grid = GtkGrid()
    entry = GenericEntry{T}(value)
    label = GtkLabel(label)
    set_gtk_property!(label, :xalign, 0.0)
    addTooltip(label, tooltip)
    grid[1, 1] = label
    grid[2, 1] = entry
    generic = new(grid.handle, field, label, entry)
    return Gtk.gobject_move_ref(generic, grid)
  end
end

mutable struct UnitfulEntry <: Gtk.GtkGrid
  handle::Ptr{Gtk.GObject}
  entry::GtkEntry
  unitValue
  function UnitfulEntry(value::T) where {T<:Quantity}
    grid = GtkGrid()
    entry = GtkEntry()
    set_gtk_property!(entry, :text, string(ustrip(value)))
    unitValue = unit(value)
    unitText = string(unitValue)
    unitLabel = GtkLabel(unitText)
    grid[1, 1] = entry
    grid[2, 1] = unitLabel
    set_gtk_property!(grid,:column_spacing,5)
    set_gtk_property!(entry, :hexpand, true)
    result = new(grid.handle, entry, unitValue)
    return Gtk.gobject_move_ref(result, grid)
  end
end

function value(entry::UnitfulEntry)
  valueString = get_gtk_property(entry.entry, :text, String)
  value = tryparse(Float64, valueString)
  return value * entry.unitValue
end
mutable struct UnitfulParameter <: Gtk.GtkGrid
  handle::Ptr{Gtk.GObject}
  field::Symbol
  label::GtkLabel
  entry::UnitfulEntry
  function UnitfulParameter(field::Symbol, label::AbstractString, value::T, tooltip::Union{Nothing, AbstractString} = nothing) where {T<:Quantity}
    grid = GtkGrid()
      
    unitfulEntry = UnitfulEntry(value)
    label = GtkLabel(label)
    set_gtk_property!(label, :xalign, 0.0)
    addTooltip(label, tooltip)
    grid[1, 1] = label
    grid[2, 1] = unitfulEntry
    #set_gtk_property!(unitLabel, :hexpand, true)
    generic = new(grid.handle, field, label, unitfulEntry)
    return Gtk.gobject_move_ref(generic, grid)
  end
end

mutable struct RegularParameters <: Gtk.Grid
  handle::Ptr{Gtk.GObject}
  paramDict::Dict{Symbol, GObject}
  function RegularParameters()
    grid = GtkGrid()
    set_gtk_property!(grid, :column_spacing, 5)
    set_gtk_property!(grid, :row_spacing, 5)
    result = new(grid.handle, Dict{Symbol, GObject}())
    return Gtk.gobject_move_ref(result, grid)
  end
end

mutable struct ParameterLabel <: Gtk.GtkLabel
  handle::Ptr{Gtk.GObject}
  field::Symbol

  function ParameterLabel(field::Symbol, tooltip::Union{AbstractString, Nothing} = nothing)
    label = GtkLabel(string(field))
    addTooltip(label, tooltip)
    result = new(label.handle, field)
    return Gtk.gobject_move_ref(result, label)
  end
end

mutable struct BoolParameter <: Gtk.CheckButton
  handle::Ptr{Gtk.GObject}
  field::Symbol

  function BoolParameter(field::Symbol, label::AbstractString, value::Bool, tooltip::Union{Nothing, AbstractString} = nothing)
    check = GtkCheckButton()
    set_gtk_property!(check, :label, label)
    set_gtk_property!(check, :active, value)
    set_gtk_property!(check, :xalign, 0.5)
    addTooltip(check, tooltip)
    cb = new(check.handle, field)
    return Gtk.gobject_move_ref(cb, check)
  end
end

value(entry::BoolParameter) = get_gtk_property(entry, :active, Bool)
mutable struct ComponentParameter <: Gtk.GtkGrid
  handle::Ptr{Gtk.GObject}
  idLabel::GtkLabel
  divider::GenericEntry
  amplitude::UnitfulEntry
  phase::UnitfulEntry

  function ComponentParameter(comp::PeriodicElectricalComponent)
    grid = GtkGrid()
    set_gtk_property!(grid, :row_spacing, 5)
    set_gtk_property!(grid, :column_spacing, 5)
    # ID
    idLabel = GtkLabel(id(comp), xalign = 0.0)
    grid[1:2, 1] = idLabel
    # Divider
    div = GenericEntry{Int64}(string(divider(comp)))
    set_gtk_property!(div, :sensitive, false)
    grid[1, 2] = GtkLabel("Divider", xalign = 0.0)
    grid[2, 2] = div
    # Amplitude
    amp = UnitfulEntry(MPIFiles.amplitude(comp))
    grid[1, 3] = GtkLabel("Amplitude", xalign = 0.0)
    grid[2, 3] = amp
    # Phase
    pha = UnitfulEntry(MPIFiles.phase(comp))
    grid[1, 4] = GtkLabel("Phase", xalign = 0.0)
    grid[2, 4] = pha
    gridResult = new(grid.handle, idLabel, div, amp, pha)
    return Gtk.gobject_move_ref(gridResult, grid)
  end
end

mutable struct PeriodicChannelParameter <: Gtk.GtkExpander
  handle::Ptr{Gtk.GObject}
  channel::PeriodicElectricalChannel
  box::GtkBox
  function PeriodicChannelParameter(idx::Int64, ch::PeriodicElectricalChannel)
    expander = GtkExpander(id(ch), expand=true)
    # TODO offset
    box = GtkBox(:v)
    push!(expander, box)
    grid = GtkGrid(expand=true)
    grid[1, 1] = GtkLabel("Tx Channel Index", xalign = 0.0)
    grid[2, 1] = GtkLabel(string(idx))
    grid[1:2, 3] = GtkLabel("Components", xalign = 0.5, hexpand=true)
    grid[1:2, 2] = GtkSeparatorMenuItem() 
    push!(box, grid)
    for comp in components(ch)
      compParam = ComponentParameter(comp)
      push!(box, compParam)
    end
    result = new(expander.handle, ch, box)
    return Gtk.gobject_move_ref(result, expander)
  end
end

# GtkObject only exists once!
mutable struct SequenceParameter <: Gtk.GtkExpander
  handle::Ptr{Gtk.GObject}
  field::Symbol

  function SequenceParameter(pw::ProtocolWidget, field::Symbol, tooltip::Union{Nothing, AbstractString} = nothing)
    exp = object_(pw.builder, "expSequence", GtkExpander)
    addTooltip(object_(pw.builder, "lblSequence", GtkLabel), tooltip)
    seq = new(exp.handle, field)
    return Gtk.gobject_move_ref(seq, exp)
  end
end

mutable struct PositionParameter <: Gtk.GtkExpander
  handle::Ptr{Gtk.GObject}
  field::Symbol

  function PositionParameter(pw::ProtocolWidget, field::Symbol, tooltip::Union{Nothing, AbstractString} = nothing)
    pos = object_(pw.builder, "expPositions", GtkExpander)
    addTooltip(object_(pw.builder, "lblPositions", GtkLabel), tooltip)
    posParam = new(pos.handle, field)
    return Gtk.gobject_move_ref(posParam, pos)
  end
end

function ProtocolWidget(scanner=nothing)
  @info "Starting ProtocolWidget"
  uifile = joinpath(@__DIR__,"..","builder","protocolWidget.ui")
    
  if !isnothing(scanner)
    mdfstore = MDFDatasetStore( generalParams(scanner).datasetStore )
    protocol = Protocol(scanner.generalParams.defaultProtocol, scanner)
  else
    mdfstore = MDFDatasetStore( "Dummy" )
    protocol = nothing
  end
    
  b = Builder(filename=uifile)
  mainBox = object_(b, "boxProtocol",BoxLeaf)

  paramBuilder = Dict(:sequence => "expSequence", :positions => "expPositions")

  pw = ProtocolWidget(mainBox.handle, b, paramBuilder, false, scanner, protocol, nothing, nothing, UNDEFINED,
        nothing, RawDataWidget(), mdfstore, zeros(Float32,0,0,0,0), "", now())
  Gtk.gobject_move_ref(pw, mainBox)

  @idle_add begin
    set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf],:sensitive,false)
    set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf],:sensitive,false)
    set_gtk_property!(pw["tbCancel",ToolButtonLeaf],:sensitive,false)      
    set_gtk_property!(pw["tbRestart",ToolButtonLeaf],:sensitive,false)      
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
  if !isnothing(pw.progress) && pw.protocolState == RUNNING
    progress = "$(pw.progress.unit) $(pw.progress.done)/$(pw.progress.total)"
    fraction = pw.progress.done/pw.progress.total
  elseif pw.protocolState == FINISHED
    progress = "FINISHED"
    fraction = 1.0
  end
  @idle_add begin
    set_gtk_property!(pw["pbProtocol", ProgressBar], :text, progress)
    set_gtk_property!(pw["pbProtocol", ProgressBar], :fraction, fraction)
  end
end

function getStorageParams(pw::ProtocolWidget)
  params = Dict{String,Any}()
  params["studyName"] = pw.currStudyName # TODO These are never updates, is the result correct?
  params["studyDate"] = pw.currStudyDate 
  params["studyDescription"] = ""
  params["experimentDescription"] = get_gtk_property(pw["entExpDescr",EntryLeaf], :text, String)
  params["experimentName"] = get_gtk_property(pw["entExpName",EntryLeaf], :text, String)
  params["scannerOperator"] = get_gtk_property(pw["entOperator",EntryLeaf], :text, String)
  params["tracerName"] = [get_gtk_property(pw["entTracerName",EntryLeaf], :text, String)]
  params["tracerBatch"] = [get_gtk_property(pw["entTracerBatch",EntryLeaf], :text, String)]
  params["tracerVendor"] = [get_gtk_property(pw["entTracerVendor",EntryLeaf], :text, String)]
  params["tracerVolume"] = [1e-3*get_gtk_property(pw["adjTracerVolume",AdjustmentLeaf], :value, Float64)]
  params["tracerConcentration"] = [1e-3*get_gtk_property(pw["adjTracerConcentration",AdjustmentLeaf], :value, Float64)]
  params["tracerSolute"] = [get_gtk_property(pw["entTracerSolute",EntryLeaf], :text, String)]
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

  signal_connect(pw["tbRestart", ToolButtonLeaf], :clicked) do w
    tryRestartProtocol(pw)
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

  signal_connect(pw["btnSelectSequence",ButtonLeaf], :clicked) do w
    dlg = SequenceSelectionDialog(pw.scanner, Dict())
    ret = run(dlg)
    if ret == GtkResponseType.ACCEPT
      if hasselection(dlg.selection)
        seq = getSelectedSequence(dlg)
        updateSequence(pw, seq)
        end
    end
    destroy(dlg)
  end

  for adj in ["adjNumFrames", "adjNumAverages", "adjNumFrameAverages", "adjNumBGFrames"]
    signal_connect(pw[adj, AdjustmentLeaf], "value_changed") do w
      if !pw.updating
        @idle_add set_gtk_property!(pw["btnSaveProtocol", Button], :sensitive, true)
      end
    end
  end

  signal_connect(pw["btnLoadFilePos", ButtonLeaf], :clicked) do w
    loadFilePos(pw)
  end

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
  addGenericCallback(pw, generic)
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

function addProtocolParameter(pw::ProtocolWidget, ::SequenceParameterType, field, value, tooltip)
  seq = SequenceParameter(pw, field, tooltip)
  updateSequence(pw, value) # Set default sequence values
  push!(pw["boxProtocolParameter", BoxLeaf], seq)
end

function updateSequence(pw::ProtocolWidget, seq::AbstractString)
  s = Sequence(pw.scanner, seq)
  updateSequence(pw, s)
end

function addProtocolParameter(pw::ProtocolWidget, ::PositionParameterType, field, value, tooltip)
  pos = PositionParameter(pw, field, tooltip)
  updatePositions(pw, value)
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

function loadFilePos(pw::ProtocolWidget)
  filter = Gtk.GtkFileFilter(pattern=String("*.h5"), mimetype=String("HDF5 File"))
  filename = open_dialog("Select Position File", GtkNullContainer(), (filter, ))
  @idle_add begin 
    set_gtk_property!(pw["entArbitraryPos",EntryLeaf],:text,filename)
    if filename != ""
      set_gtk_property!(pw["cbUseArbitraryPos", CheckButtonLeaf], :sensitive, true)
    end
  end
end

### Parameter Interaction ###
function updateSequence(pw::ProtocolWidget, seq::Sequence)  
  @idle_add begin
    try
      @info "Try adding channels"
      empty!(pw["boxPeriodicChannel", BoxLeaf])
      for channel in periodicElectricalTxChannels(seq)
        idx = MPIMeasurements.channelIdx(getDAQ(pw.scanner), id(channel))
        channelParam = PeriodicChannelParameter(idx, channel)
        push!(pw["boxPeriodicChannel", BoxLeaf], channelParam)
      end
      showall(pw["boxPeriodicChannel", BoxLeaf])
      @info "Finished adding channels"


      set_gtk_property!(pw["entSequenceName",EntryLeaf], :text, MPIFiles.name(seq)) 
      set_gtk_property!(pw["entNumPeriods",EntryLeaf], :text, "$(acqNumPeriodsPerFrame(seq))")
      set_gtk_property!(pw["entNumPatches",EntryLeaf], :text, "$(acqNumPatches(seq))")
      set_gtk_property!(pw["adjNumFrames", AdjustmentLeaf], :value, acqNumFrames(seq))
      set_gtk_property!(pw["adjNumFrameAverages", AdjustmentLeaf], :value, acqNumFrameAverages(seq))
      set_gtk_property!(pw["adjNumAverages", AdjustmentLeaf], :value, acqNumAverages(seq))
    catch e 
      @error e
    end
    #setInfoParams(pw)
  end
end

function updatePositions(pw::ProtocolWidget, pos::Union{Positions, Nothing})
  if !isnothing(pos)
    shp = MPIFiles.shape(pos)
    shpStr = @sprintf("%d x %d x %d", shp[1],shp[2],shp[3])
    fov = Float64.(ustrip.(uconvert.(Unitful.mm,MPIFiles.fieldOfView(pos)))) # convert to mm
    fovStr = @sprintf("%.2f x %.2f x %.2f", fov[1],fov[2],fov[3])
    ctr = Float64.(ustrip.(uconvert.(Unitful.mm,MPIFiles.fieldOfViewCenter(pos)))) # convert to mm
    ctrStr = @sprintf("%.2f x %.2f x %.2f", ctr[1],ctr[2],ctr[3])
    @idle_add begin 
      set_gtk_property!(pw["entGridShape",EntryLeaf], :text, shpStr)
      set_gtk_property!(pw["entFOV",EntryLeaf], :text, fovStr)
      set_gtk_property!(pw["entCenter",EntryLeaf], :text, ctrStr)
      set_gtk_property!(pw["cbUseArbitraryPos", CheckButtonLeaf], :sensitive, false)
      set_gtk_property!(pw["entArbitraryPos",EntryLeaf],:text, "")
    end
  end
end

function setProtocolParameter(pw::ProtocolWidget, field::Symbol, parameterObj, params::ProtocolParams)
  @info "Setting field $field"
  val = value(parameterObj)
  setfield!(params, field, val)
end

# Technically BoolParameter contains the field already but for the sake of consistency this is structured like the other parameter
function setProtocolParameter(pw::ProtocolWidget, parameterObj::BoolParameter, params::ProtocolParams)
  field = parameterObj.field
  setProtocolParameter(pw, field, parameterObj, params)
end

function setProtocolParameter(pw::ProtocolWidget, parameterObj::Union{UnitfulParameter, GenericParameter{T}}, params::ProtocolParams) where {T}
  field = parameterObj.field
  setProtocolParameter(pw, field, parameterObj.entry, params)
end

function setProtocolParameter(pw::ProtocolWidget, fieldObj::Union{ParameterLabel, BoolParameter}, valueObj, params::ProtocolParams)
  field = fieldObj.field
  setProtocolParameter(pw, field, valueObj, params)
end

function setProtocolParameter(pw::ProtocolWidget, parameterObj::RegularParameters, params::ProtocolParams)
  for i = 1:length(parameterObj.paramDict)
    fieldObj = parameterObj[1, i]
    valueObj = parameterObj[2, i]
    setProtocolParameter(pw, fieldObj, valueObj, params)
  end
end

function setProtocolParameter(pw::ProtocolWidget, parameterObj::SequenceParameter, params::ProtocolParams)
  @info "Trying to set sequence"
  seq = getfield(params, parameterObj.field)

  acqNumFrames(seq, get_gtk_property(pw["adjNumFrames",AdjustmentLeaf], :value, Int64))
  acqNumFrameAverages(seq, get_gtk_property(pw["adjNumFrameAverages",AdjustmentLeaf], :value, Int64))
  acqNumAverages(seq, get_gtk_property(pw["adjNumAverages",AdjustmentLeaf], :value, Int64))
  
  for channelParam in pw["boxPeriodicChannel", BoxLeaf]
    setProtocolParameter(pw, channelParam)
  end
  @info "Set sequence"
end

function setProtocolParameter(pw::ProtocolWidget, channelParam::PeriodicChannelParameter)
  # TODO offset
  channel = channelParam.channel
  for index = 2:length(channelParam.box) # Index 1 is grid describing channel, then come the components
    component = channelParam.box[index]
    id = get_gtk_property(component.idLabel, :label, String)
    @info "Setting componend $id"
    amplitude!(channel, id, value(component.amplitude))
    phase!(channel, id, value(component.phase))
  end
end

function setProtocolParameter(pw::ProtocolWidget, parameterObj::PositionParameter, params::ProtocolParams)
  # Construct pos
  @info "Trying to set pos"
  cartGrid = nothing
  if get_gtk_property(pw["cbUseArbitraryPos",CheckButtonLeaf], :active, Bool) == false
    
    shpString = get_gtk_property(pw["entGridShape",EntryLeaf], :text, String)
    shp_ = tryparse.(Int64,split(shpString,"x"))
    fovString = get_gtk_property(pw["entFOV",EntryLeaf], :text, String)
    fov_ = tryparse.(Float64,split(fovString,"x"))
    centerString = get_gtk_property(pw["entCenter",EntryLeaf], :text, String)
    center_ = tryparse.(Float64,split(centerString,"x"))
    if any(shp_ .== nothing) || any(fov_ .== nothing) || any(center_ .== nothing)  ||
     length(shp_) != 3 || length(fov_) != 3 || length(center_) != 3
      @warn "Mismatch dimension for positions"
      # TODO throw some sort of exception
      return
    end
    shp = shp_
    fov = fov_ .*1Unitful.mm
    ctr = center_ .*1Unitful.mm
    cartGrid = RegularGridPositions(shp,fov,ctr)
  
  else
    
    filename = get_gtk_property(pw["entArbitraryPos",EntryLeaf],:text,String)
    if filename != ""
        cartGrid = h5open(filename, "r") do file
            positions = Positions(file)
        end
    else
      error("Filename Arbitrary Positions empty!")
    end

  end

  setfield!(params, parameterObj.field, cartGrid)
end