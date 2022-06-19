mutable struct SequenceParameter <: Gtk4.GtkExpander
  handle::Ptr{Gtk4.GObject}
  builder::GtkBuilder
  field::Symbol
  value::Sequence
  scanner::MPIScanner

  function SequenceParameter(field::Symbol, value::Sequence, scanner::MPIScanner)
    uifile = joinpath(@__DIR__, "..", "builder", "sequenceWidget.ui")
    b = GtkBuilder(filename=uifile)
    exp = Gtk4.G_.get_object(b, "expSequence")
    #addTooltip(object_(pw.builder, "lblSequence", GtkLabel), tooltip)
    seq = new(exp.handle, b, field, value, scanner)
    Gtk4.GLib.gobject_move_ref(seq, exp)
    initCallbacks(seq)
    return seq
  end
end

getindex(m::SequenceParameter, w::AbstractString, T::Type) = object_(m.builder, w, T)


mutable struct PeriodicChannelParameter <: Gtk4.GtkExpander
  handle::Ptr{Gtk4.GObject}
  channel::PeriodicElectricalChannel
  box::GtkBox
  function PeriodicChannelParameter(idx::Int64, ch::PeriodicElectricalChannel, waveforms::Vector{Waveform})
    expander = GtkExpander(id(ch), expand=true)
    # TODO offset
    box = GtkBox(:v)
    push!(expander, box)
    grid = GtkGrid(expand=true)
    grid[1:2, 1] = GtkLabel("Tx Channel Index", xalign = 0.0)
    grid[2, 1] = GtkLabel(string(idx))
    grid[1:2, 3] = GtkLabel("Components", xalign = 0.5, hexpand=true)
    grid[1:2, 2] = GtkSeparatorMenuItem() 
    push!(box, grid)
    for comp in components(ch)
      compParam = ComponentParameter(comp, waveforms)
      push!(box, compParam)
    end
    result = new(expander.handle, ch, box)
    return Gtk4.GLib.gobject_move_ref(result, expander)
  end
end

mutable struct ComponentParameter <: Gtk4.GtkGrid
  handle::Ptr{Gtk4.GObject}
  idLabel::GtkLabel
  divider::GenericEntry
  amplitude::UnitfulGtkEntry
  phase::UnitfulGtkEntry
  waveform::Gtk4.GtkComboBoxTextLeaf
  waveforms::Vector{Waveform}

  function ComponentParameter(comp::PeriodicElectricalComponent, waveforms::Vector{Waveform})
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
    ampVal = MPIFiles.amplitude(comp)
    if ampVal isa typeof(1.0u"T")
      ampVal = uconvert(u"mT", ampVal)
    end
    amp = UnitfulGtkEntry(ampVal)
    grid[1, 3] = GtkLabel("Amplitude", xalign = 0.0)
    grid[2, 3] = amp
    # Phase
    pha = UnitfulGtkEntry(MPIFiles.phase(comp))
    grid[1, 4] = GtkLabel("Phase", xalign = 0.0)
    grid[2, 4] = pha

    # Waveform
    wav = Gtk4.GtkComboBoxTextLeaf()
    waveformsStr = fromWaveform.(waveforms)
    for w in waveformsStr
      push!(wav, w)
    end
    activeIdx = findfirst(w->w == waveform(comp), waveforms)
    set_gtk_property!(wav, :active, activeIdx-1) 
    set_gtk_property!(wav, :sensitive, true) 
    grid[1, 5] = GtkLabel("Waveform", xalign = 0.0)
    grid[2, 5] = wav
    gridResult = new(grid.handle, idLabel, div, amp, pha, wav, waveforms)
    return Gtk4.GLib.gobject_move_ref(gridResult, grid)
  end
end

function initCallbacks(seqParam::SequenceParameter)
  signal_connect(seqParam["btnSelectSequence",ButtonLeaf], :clicked) do w
    dlg = SequenceSelectionDialog(seqParam.scanner, Dict())
    ret = run(dlg)
    if ret == GtkResponseType.ACCEPT
      if hasselection(dlg.selection)
        seq = getSelectedSequence(dlg)
        updateSequence(seqParam, seq)
        end
    end
    destroy(dlg)
  end
end

function updateSequence(seqParam::SequenceParameter, seqValue::AbstractString)
  s = Sequence(seqParam.scanner, seqValue)
  updateSequence(seqParam, s)
end

function updateSequence(seqParam::SequenceParameter, seq::Sequence)  
  @idle_add_guarded begin
    try
      @info "Try adding channels"
      empty!(seqParam["boxPeriodicChannel", Gtk4.GtkBoxLeaf])
      for channel in periodicElectricalTxChannels(seq)
        daq = getDAQ(seqParam.scanner)
        idx = MPIMeasurements.channelIdx(daq, id(channel))
        waveforms = MPIMeasurements.allowedWaveforms(daq, id(channel)) 
        channelParam = PeriodicChannelParameter(idx, channel, waveforms)
        push!(seqParam["boxPeriodicChannel", Gtk4.GtkBoxLeaf], channelParam)
      end
      show(seqParam["boxPeriodicChannel", Gtk4.GtkBoxLeaf])
      @info "Finished adding channels"


      set_gtk_property!(seqParam["entSequenceName",GtkEntryLeaf], :text, MPIFiles.name(seq)) 
      set_gtk_property!(seqParam["entNumPeriods",GtkEntryLeaf], :text, "$(acqNumPeriodsPerFrame(seq))")
      set_gtk_property!(seqParam["entNumPatches",GtkEntryLeaf], :text, "$(acqNumPatches(seq))")
      set_gtk_property!(seqParam["adjNumFrames", Gtk4.GtkAdjustmentLeaf], :value, acqNumFrames(seq))
      set_gtk_property!(seqParam["adjNumFrameAverages", Gtk4.GtkAdjustmentLeaf], :value, acqNumFrameAverages(seq))
      set_gtk_property!(seqParam["adjNumAverages", Gtk4.GtkAdjustmentLeaf], :value, acqNumAverages(seq))
      seqParam.value = seq
    catch e 
      @error e
    end
  end
end

function setProtocolParameter(seqParam::SequenceParameter, params::ProtocolParams)
  @info "Trying to set sequence"
  seq = seqParam.value

  acqNumFrames(seq, get_gtk_property(seqParam["adjNumFrames",Gtk4.GtkAdjustmentLeaf], :value, Int64))
  acqNumFrameAverages(seq, get_gtk_property(seqParam["adjNumFrameAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64))
  acqNumAverages(seq, get_gtk_property(seqParam["adjNumAverages",Gtk4.GtkAdjustmentLeaf], :value, Int64))
  
  for channelParam in seqParam["boxPeriodicChannel", Gtk4.GtkBoxLeaf]
    setProtocolParameter(channelParam)
  end
  setfield!(params, seqParam.field, seq)
  @info "Set sequence"
end

function setProtocolParameter(channelParam::PeriodicChannelParameter)
  # TODO offset
  channel = channelParam.channel
  for index = 2:length(channelParam.box) # Index 1 is grid describing channel, then come the components
    component = channelParam.box[index]
    id = get_gtk_property(component.idLabel, :label, String)
    @info "Setting component $id"
    amplitude!(channel, id, uconvert(u"T", value(component.amplitude)))
    phase!(channel, id, value(component.phase))
    wave = component.waveforms[get_gtk_property(component.waveform, :active, Int)+1]
    waveform!(channel, id, wave)
  end
end