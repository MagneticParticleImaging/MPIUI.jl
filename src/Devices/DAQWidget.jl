
mutable struct DAQWidget <: Gtk.GtkBox
    handle::Ptr{Gtk.GObject}
    builder::GtkBuilder
    updating::Bool
    daq::AbstractDAQ
    timer::Union{Timer,Nothing}
end
  
getindex(m::DAQWidget, w::AbstractString) = G_.object(m.builder, w)
  
  
  
function DAQWidget(daq::AbstractDAQ)
    uifile = joinpath(@__DIR__,"..","builder","DAQWidget.ui")

    b = Builder(filename=uifile)
    mainBox = G_.object(b, "mainBox")

    m = DAQWidget(mainBox.handle, b, false, daq, nothing)
    Gtk.gobject_move_ref(m, mainBox)

    init(m)
    initCallbacks(m)

    return m
end
  
function initCallbacks(m::DAQWidget)
    signal_connect(m["tbStartTx"], :toggled) do w
        if get_gtk_property(m["tbStartTx"], :active, Bool)
            startDAQ(m)
        else
            stopDAQ(m)
        end
    end
end

function init(m::DAQWidget)
    @idle_add begin
        set_gtk_property!(m["entNumRxChan"],:text, numRxChannelsTotal(m.daq))
        set_gtk_property!(m["entNumTxChan"],:text, numTxChannelsTotal(m.daq))
    end
end



function startDAQ(m::DAQWidget)
    MPIMeasurements.startTx(m.daq)
    function update_(timer::Timer)
        @info "ja Moin!  $(typeof(m.daq))  $(!(m.updating))"
        if !(m.updating) && typeof(m.daq) <: RedPitayaDAQ
            wp = MPIMeasurements.currentWP(m.daq.rpc)
            @info wp
            @idle_add set_gtk_property!(m["entWP"], :text, wp)
        end
    end
    m.timer = Timer(update_, 0.0, interval=0.1)
end
  
function stopDAQ(m)
    if m.timer != nothing
        close(m.timer)
        MPIMeasurements.stopTx(m.daq)
        m.timer = nothing
    end
end
  
  