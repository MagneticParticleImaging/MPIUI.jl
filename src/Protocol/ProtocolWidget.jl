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
        for field in fieldnames(typeof(params))
        @info "Try adding field $field"
        try 
            addProtocolParameter(pw, field, params)
            @info "Added $field"
        catch ex
            @error ex
        end
        end
    end
end

function addProtocolParameter(pw::ProtocolWidget, field, params)
    if haskey(pw.paramBuilder, field)
        @info "Do special things for parameter $field"
    else 
        gridGeneric = object_(pw.builder, "gridGeneric",GtkGrid)
        labelLeaf = gridGeneric[1, 1]
        valueEntry = gridGeneric[2, 1]
        set_gtk_property!(labelLeaf, :label, string(field))
        set_gtk_property!(valueEntry, :text, string(getfield(params, field)))
        #TODO set entry name/id to fetch it later
        push!(pw["boxProtocolParameter", BoxLeaf], gridGeneric)
    end
end

function isMeasurementStore(m::ProtocolWidget, d::DatasetStore)
    if isnothing(m.mdfstore)
      return false
    else
      return d.path == m.mdfstore.path
    end
  end