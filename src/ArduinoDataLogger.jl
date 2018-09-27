import Base: getindex
using MPIMeasurements
mutable struct ArduinoDataLoggerUI
    builder
    data
    freq
    time
    c1
    c2
    c3
    c4
    c5
    c6
    c7
end
struct ArduinoDataLogger
  sd::MPIMeasurements.SerialDevice
  CommandStart::String
  CommandEnd::String
  delim::String
end

getindex(m::ArduinoDataLoggerUI, w::AbstractString)= G_.object(m.builder,w)

function ArduinoDataLoggerUI()
        @info "Starting ArduinoDataLoggerUI"
        uifile= joinpath(@__DIR__,"builder","ArduinoDataLogger.ui")
        b= Builder(filename=uifile)

        m= ArduinoDataLoggerUI(b,nothing, nothing,nothing, nothing, nothing,nothing,nothing,nothing,nothing,nothing)
        m.c1 =Canvas()
        m.c2=Canvas()

        signal_connect(m["btnConnect"], :clicked) do w
            connectToArduino(m)
        end
        showall(m["mainWindow"])
        @info "Finished starting ArduinoDataLoggerUI"
    return m
end

function connectToArduino(m::ArduinoDataLoggerUI)
    port=get_gtk_property(m["Port"], :text,String)
    pause_ms::Int=30
    timeout_ms::Int=500
    delim::String="#"
    delim_read::String="#"
    delim_write::String="#"
    baudrate::Integer = 2000000
    CommandStart="!"
    CommandEnd="*"
    ndatabits::Integer=8
    parity::SPParity=SP_PARITY_NONE
    nstopbits::Integer=1
    sp = MPIMeasurements.SerialPort(portAdress)
    open(sp)
	set_speed(sp, baudrate)
	set_frame(sp,ndatabits=ndatabits,parity=parity,nstopbits=nstopbits)
	#set_flow_control(sp,rts=rts,cts=cts,dtr=dtr,dsr=dsr,xonxoff=xonxoff)
    sleep(2)
    flush(sp)
    write(sp, "!ConnectionEstablished*#")
    response=readuntil(sp,delim_read,timeout_ms);
    if (response == "ArduinoDataLoggerV1")
        @info "Connected to ArduinoDataLogger"
        Arduino=ArduinoDataLogger(MPIMeasurements.SerialDevice(sp,pause_ms, timeout_ms, delim_read, delim_write),CommandStart,CommandEnd,delim)
    end

    m.c1 = Canvas()
    push!(m["boxMain"],m.c1)
    set_gtk_property!(m["boxMain"],:expand,m.c1,true)
    while get_gtk_property(m["ONOFF"],:activate, Bool)
        data = rand(numSamp)+im*rand(numSamp) #TODO
        #data=readuntil(sp,delim_read,timeout_ms);
        #make things with Data
        p1= Winston.plot(linspace(0,size(data,1),size(data,1),data),"k-x",linewith=2)
        display(m.c1,p1)
    end
    close(sp)
end
