mutable struct ProtocolWidget{T} <: Gtk.GtkBox
    # Gtk 
    handle::Ptr{Gtk.GObject}
    builder::GtkBuilder
    paramBuilder::Dict
    # Protocol Interaction
    scanner::T
    protocol::Union{Protocol, Nothing}
    biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing}
    eventHandler::Union{Timer, Nothing}
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
mutable struct GenericParameter <: Gtk.GtkGrid
    handle::Ptr{Gtk.GObject}
    field::Symbol
    label::GtkLabel
    entry::GtkEntry

    function GenericParameter(field::Symbol, label::AbstractString, value::AbstractString)
        grid = GtkGrid()
        entry = GtkEntry()
        label = GtkLabel(label)
        set_gtk_property!(entry, :text, value)
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
    unit::AbstractString

    function UnitfulParameter(field::Symbol, label::AbstractString, value::T) where {T<:Quantity}
        grid = GtkGrid()
        
        entryGrid = GtkGrid()
        entry = GtkEntry()
        set_gtk_property!(entry, :text, ustrip(value))
        unitText = string(unit(value))
        unitLabel = GtkLabel(unitText)
        entryGrid[1, 1] = entry
        entryGrid[2, 1] = unitLabel
        set_gtk_property!(entryGrid,:column_spacing,10)


        label = GtkLabel(label)
        grid[1, 1] = label
        grid[2, 1] = entryGrid
        set_gtk_property!(grid, :column_homogeneous, true)
        generic = new(grid.handle, field, label, entry, unitText)
        return Gtk.gobject_move_ref(generic, grid)
    end
end

mutable struct BoolParameter <: Gtk.CheckButton
    handle::Ptr{Gtk.GObject}
    field::Symbol

    function BoolParameter(field::Symbol, label::AbstractString, value::Bool)
        check = GtkCheckButton()
        set_gtk_property!(check, :label, label)
        set_gtk_property!(check, :active, value)
        cb = new(check.handle, field)
        return Gtk.gobject_move_ref(cb, check)
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

    pw = ProtocolWidget(mainBox.handle, b, paramBuilder, scanner, protocol, nothing, nothing, 
        mdfstore, zeros(Float32,0,0,0,0), "", now())
    Gtk.gobject_move_ref(pw, mainBox)

    if isnothing(pw.scanner)
        @idle_add begin
            set_gtk_property!(pw["tbStart",ToolButtonLeaf],:sensitive,false)
            set_gtk_property!(pw["tbPause",ToolButtonLeaf],:sensitive,false)
            set_gtk_property!(pw["tbCancel",ToolButtonLeaf],:sensitive,false)      
            set_gtk_property!(pw["tbRestart",ToolButtonLeaf],:sensitive,false)      
        end
    else
        # Load default protocol and set params
        # + dummy plotting?
        initProtocolChoices(pw)
        initCallbacks(pw)
    end
    @info "Finished starting ProtocolWidget"
    return pw
end

function initCallbacks(pw::ProtocolWidget)
    signal_connect(pw["tbRun", ToolButtonLeaf], :clicked) do w
        #startProtocol(pw)
    end

    signal_connect(pw["tbPause", ToolButtonLeaf], :clicked) do w
        #tryPauseProtocol(pw)
    end

    signal_connect(pw["tbCancel", ToolButtonLeaf], :clicked) do w
        #tryCancelProtocol(pw)
    end

    signal_connect(pw["tbRestart", ToolButtonLeaf], :clicked) do w
        #tryRestartProtocol(pw)
    end

    signal_connect(pw["cmbProtocolSelection", GtkComboBoxText], :changed) do w
        protocolName = Gtk.bytestring( GAccessor.active_text(pw["cmbProtocolSelection", GtkComboBoxText])) 
        #get_gtk_property(pw["cmbProtocolSelection", GtkComboBoxText], :active, AbstractString)
        protocol = Protocol(protocolName, pw.scanner)
        updateProtocol(pw, protocol)
    end
end

function initProtocolChoices(pw::ProtocolWidget)
    scanner = pw.scanner
    choices = getProtocolList(scanner)
    cb = pw["cmbProtocolSelection", GtkComboBoxText]
    for choice in choices
        push!(cb, choice)
    end
    defaultIndex = findfirst(x -> x == scanner.generalParams.defaultProtocol, choices)
    @show defaultIndex
    if !isnothing(defaultIndex)
        protocolName = choices[defaultIndex]
        protocol = Protocol(protocolName, pw.scanner)
        @idle_add begin
            updateProtocol(pw, protocol)
            set_gtk_property!(cb, :active, defaultIndex)
        end
    end
end

function updateProtocol(pw::ProtocolWidget, protocol::Protocol)
    params = protocol.params
    @info "Updating protocol"
    @idle_add begin
        set_gtk_property!(pw["lblProtocolType", GtkLabelLeaf], :label, string(typeof(protocol)))
        set_gtk_property!(pw["txtBuffProtocolDescription", GtkTextBufferLeaf], :text, MPIMeasurements.description(protocol))
    end
    @idle_add begin 
        # Clear old parameters
        empty!(pw["boxProtocolParameter", BoxLeaf])

        for (index, field) in enumerate(fieldnames(typeof(params)))
        @info "Try adding field $field"
            try 
                @show typeof(params).types[index]
                value = getfield(params, field)
                addProtocolParameter(pw, parameterType(field, value), field, value)
                @info "Added $field"
            catch ex
                @error ex
            end
        end

        showall(pw["boxProtocolParameter", BoxLeaf])
    end
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, field, value)
    generic = GenericParameter(field, string(field), string(value))
    push!(pw["boxProtocolParameter", BoxLeaf], generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::GenericParameterType, field, value::T) where {T<:Quantity}
    @info "Unitful parameter $field"
    generic = UnitfulParameter(field, string(field), value)
    push!(pw["boxProtocolParameter", BoxLeaf], generic)
end

function addProtocolParameter(pw::ProtocolWidget, ::SequenceParameterType, field, value)
    seq = object_(pw.builder, "expSequence", GtkExpander)
    push!(pw["boxProtocolParameter", BoxLeaf], seq)
end


function addProtocolParameter(pw::ProtocolWidget, ::PositionParameterType, field, value)
    @info "Do something for positions $field"
    pos = object_(pw.builder, "expPositions", GtkExpander)
    push!(pw["boxProtocolParameter", BoxLeaf], pos)
end

function addProtocolParameter(pw::ProtocolWidget, ::BoolParameterType, field, value)
    cb = BoolParameter(field, string(field), value)
    push!(pw["boxProtocolParameter", BoxLeaf], cb)
end

function isMeasurementStore(m::ProtocolWidget, d::DatasetStore)
    if isnothing(m.mdfstore)
      return false
    else
      return d.path == m.mdfstore.path
    end
  end