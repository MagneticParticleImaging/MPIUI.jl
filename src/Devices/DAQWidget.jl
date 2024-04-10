
mutable struct DAQWidget <: Gtk4.GtkBox
    handle::Ptr{Gtk4.GObject}
    builder::GtkBuilder
    updating::Bool
    daq::AbstractDAQ
    timer::Union{Timer,Nothing}
end
  
getindex(m::DAQWidget, w::AbstractString) = Gtk4.G_.get_object(m.builder, w)
  
  
  
function DAQWidget(daq::AbstractDAQ)
    uifile = joinpath(@__DIR__,"..","builder","DAQWidget.ui")

    b = GtkBuilder(uifile)
    mainBox = Gtk4.G_.get_object(b, "mainBox")

    m = DAQWidget(mainBox.handle, b, false, daq, nothing)
    Gtk4.GLib.gobject_move_ref(m, mainBox)

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
    @idle_add_guarded begin
        set_gtk_property!(m["entNumRxChan"],:text, numRxChannelsTotal(m.daq))
        set_gtk_property!(m["entNumTxChan"],:text, numTxChannelsTotal(m.daq))
    end
end



function startDAQ(m::DAQWidget)
    MPIMeasurements.startTx(m.daq)
    function update_(timer::Timer)
        if !(m.updating) && typeof(m.daq) <: RedPitayaDAQ
            wp = MPIMeasurements.currentWP(m.daq.rpc)
            @info wp
            @idle_add_guarded set_gtk_property!(m["entWP"], :text, wp)
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
  
  