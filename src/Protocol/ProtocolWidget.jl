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
struct GenericParameterType <: ParameterType end
struct SequenceParameterType <: ParameterType end
struct PositionParameterType <: ParameterType end
struct BoolParameterType <: ParameterType end
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
mutable struct GenericParameter{T} <: Gtk.GtkGrid
  handle::Ptr{Gtk.GObject}
  field::Symbol
  label::GtkLabel
  entry::GtkEntry

  function GenericParameter{T}(field::Symbol, label::AbstractString, value::AbstractString, tooltip::Union{Nothing, AbstractString} = nothing) where {T}
    grid = GtkGrid()
    entry = GtkEntry()
    label = GtkLabel(label)
    set_gtk_property!(label, :xalign, 0.0)
    set_gtk_property!(entry, :text, value)
    addTooltip(label, tooltip)
    grid[1, 1] = label
    grid[2, 1] = entry
    set_gtk_property!(grid, :column_homogeneous, true)
    generic = new(grid.handle, field, label, entry)
    return Gtk.gobject_move_ref(generic, grid)
  end
end

mutable struct UnitfulParameter <: Gtk.GtkGrid
  handle::Ptr{Gtk.GObject}
  field::Symbol
  label::GtkLabel
  entry::GtkEntry
  unitValue

  function UnitfulParameter(field::Symbol, label::AbstractString, value::T, tooltip::Union{Nothing, AbstractString} = nothing) where {T<:Quantity}
    grid = GtkGrid()
      
    entryGrid = GtkGrid()
    entry = GtkEntry()
    set_gtk_property!(entry, :text, string(ustrip(value)))
    unitValue = unit(value)
    unitText = string(unitValue)
    unitLabel = GtkLabel(unitText)
    entryGrid[1, 1] = entry
    entryGrid[2, 1] = unitLabel
    set_gtk_property!(entryGrid,:column_spacing,10)
    label = GtkLabel(label)
    set_gtk_property!(label, :xalign, 0.0)
    addTooltip(label, tooltip)
    grid[1, 1] = label
    grid[2, 1] = entryGrid
    set_gtk_property!(grid, :column_homogeneous, true)
    generic = new(grid.handle, field, label, entry, unitValue)
    return Gtk.gobject_move_ref(generic, grid)
  end
end

mutable struct BoolParameter <: Gtk.CheckButton
  handle::Ptr{Gtk.GObject}
  field::Symbol

  function BoolParameter(field::Symbol, label::AbstractString, value::Bool, tooltip::Union{Nothing, AbstractString} = nothing)
    check = GtkCheckButton()
    set_gtk_property!(check, :label, label)
    set_gtk_property!(check, :active, value)
    addTooltip(check, tooltip)
    cb = new(check.handle, field)
    return Gtk.gobject_move_ref(cb, check)
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
    #initCallbacks(pw)
    @idle_add set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf],:sensitive,true)
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

function initCallbacks(pw::ProtocolWidget)
  signal_connect(pw["tbRun", ToggleToolButtonLeaf], :toggled) do w
    if !pw.updating
      if get_gtk_property(w, :active, Bool)
        if startProtocol(pw)
          @idle_add begin 
            pw.updating = true
            set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :sensitive, false)
            set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, true)
            set_gtk_property!(pw["tbCancel",ToolButtonLeaf], :sensitive, true)
            pw.updating = false
          end
        else
          # Something went wrong during start, we dont count button press
          set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :active, false)
        end
      else
        endProtocol(pw)  
        @idle_add begin 
          pw.updating = true
          set_gtk_property!(pw["tbRun",ToggleToolButtonLeaf], :sensitive, true)
          set_gtk_property!(pw["tbPause",ToggleToolButtonLeaf], :sensitive, false)
          set_gtk_property!(pw["tbCancel",ToolButtonLeaf], :sensitive, false)
          set_gtk_property!(pw["tbRestart",ToolButtonLeaf], :sensitive, false)
          pw.updating = false
        end
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
    #tryRestartProtocol(pw)
  end

  #signal_connect(pw["cmbProtocolSelection", GtkComboBoxText], :changed) do w
  #  protocolName = Gtk.bytestring( GAccessor.active_text(pw["cmbProtocolSelection", GtkComboBoxText])) 
  #  #get_gtk_property(pw["cmbProtocolSelection", GtkComboBoxText], :active, AbstractString)
  #  #@show protocolName
  #  protocol = Protocol(protocolName, pw.scanner)
  #  updateProtocol(pw, protocol)
  #end

  #=signal_connect(pw["btnSaveProtocol", GtkButton], "clicked") do w
    dlg = ProtocolSelectionDialog(pw.scanner, Dict())
    ret = run(dlg)
    if ret == GtkResponseType.ACCEPT
      if hasselection(dlg.selection)
        protocol = getSelectedProtocol(dlg)
        updateProtocol(pw, protocol)
        end
    end
    destroy(dlg)
  end=#

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

    for field in fieldnames(typeof(params))
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

function addProtocolParameter(pw::ProtocolWidget, ::BoolParameterType, field, value, tooltip)
  cb = BoolParameter(field, string(field), value, tooltip)
  addGenericCallback(pw, cb)
  push!(pw["boxProtocolParameter", BoxLeaf], cb)
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
  dfString = *([ string(x*1e3," x ") for x in diag(ustrip.(dfStrength(seq)[1,:,:])) ]...)[1:end-3]
  dfDividerStr = *([ string(x," x ") for x in unique(vec(dfDivider(seq))) ]...)[1:end-3]
  
  @idle_add begin
    set_gtk_property!(pw["entSequenceName",EntryLeaf], :text, MPIFiles.name(seq)) 
    set_gtk_property!(pw["entNumPeriods",EntryLeaf], :text, "$(acqNumPeriodsPerFrame(seq))")
    set_gtk_property!(pw["entNumPatches",EntryLeaf], :text, "$(acqNumPatches(seq))")
    set_gtk_property!(pw["adjNumFrames", AdjustmentLeaf], :value, acqNumFrames(seq))
    set_gtk_property!(pw["adjNumFrameAverages", AdjustmentLeaf], :value, acqNumFrameAverages(seq))
    set_gtk_property!(pw["adjNumAverages", AdjustmentLeaf], :value, acqNumAverages(seq))
    set_gtk_property!(pw["entDFStrength",EntryLeaf], :text, dfString)
    set_gtk_property!(pw["entDFDivider",EntryLeaf], :text, dfDividerStr)
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

function setProtocolParameter(pw::ProtocolWidget, parameterObj::BoolParameter, params::ProtocolParams)
  value = get_gtk_property(parameterObj, :active, Bool)
  field = parameterObj.field
  @info "Setting field $field"
  setfield!(params, field, value)
end

function setProtocolParameter(pw::ProtocolWidget, parameterObj::UnitfulParameter, params::ProtocolParams)
  valueString = get_gtk_property(parameterObj.entry, :text, String)
  value = tryparse(Float64, valueString)
  field = parameterObj.field
  @info "Setting field $field"
  setfield!(params, field, value * parameterObj.unitValue)
end

function setProtocolParameter(pw::ProtocolWidget, parameterObj::GenericParameter{T}, params::ProtocolParams) where {T}
  valueString = get_gtk_property(parameterObj.entry, :text, String)
  value = tryparse(T, valueString)
  field = parameterObj.field
  @info "Setting field $field"
  setfield!(params, field, value)
end

function setProtocolParameter(pw::ProtocolWidget, parameterObj::SequenceParameter, params::ProtocolParams)
  @info "Trying to set sequence"
  seq = getfield(params, parameterObj.field)

  acqNumFrames(seq, get_gtk_property(pw["adjNumFrames",AdjustmentLeaf], :value, Int64))
  acqNumFrameAverages(seq, get_gtk_property(pw["adjNumFrameAverages",AdjustmentLeaf], :value, Int64))
  acqNumAverages(seq, get_gtk_property(pw["adjNumAverages",AdjustmentLeaf], :value, Int64))
  #dfDivider(seq)
  #dfStrength TODO, doesnt have a function atm
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