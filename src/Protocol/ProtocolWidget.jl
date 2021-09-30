mutable struct ProtocolWidget{T} <: Gtk.GtkBox
    # Gtk 
    handle::Ptr{Gtk.GObject}
    builder::GtkBuilder
    # Protocol Interaction
    scanner::T
    protocol::Union{Protocol, Nothing}
    biChannel::Union{BidirectionalChannel{ProtocolEvent}, Nothing}
    eventHandler::Union{Timer, Nothing}
    # Storage
    mdfstore::MDFDatasetStore
    dataBGStore::Array{Float32,4}
end

getindex(m::ProtocolWidget, w::AbstractString, T::Type) = object_(m.builder, w, T)

function ProtocolWidget(filenameConfig="")
    @info "Starting ProtocolWidget"
    uifile = joinpath(@__DIR__,"..","builder","protocolWidget.ui")
    
    if filenameConfig != ""
        scanner = MPIScanner(filenameConfig)
        mdfstore = MDFDatasetStore( generalParams(scanner).datasetStore )
        protocol = Protocol(scanner.generalParams.defaultProtocol, scanner)
    else
        scanner = nothing
        mdfstore = MDFDatasetStore( "Dummy" )
        protocol = nothing
    end
    
    b = Builder(filename=uifile)
    mainBox = object_(b, "boxProtocol",BoxLeaf)

    pw = ProtocolWidget(mainBox.handle, b, scanner, protocol, nothing, nothing, 
        mdfstore, zeros(Float32,0,0,0,0))

    if isnothing(pw.scanner)
        @idle_add begin
            set_gtk_property!(pw["tbStart",ToolButtonLeaf],:sensitive,false)
            set_gtk_property!(pw["tbPause",ToolButtonLeaf],:sensitive,false)
            set_gtk_property!(pw["tbCancel",ToggleToolButtonLeaf],:sensitive,false)      
        end
    else
        # Load default protocol and set params
        # + dummy plotting?
        initCallbacks(pw)
    end
    @info "Finished starting ProtocolWidget"
    return pw
end

function initCallbacks(pw::ProtocolWidget)

end