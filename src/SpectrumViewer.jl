using Gtk, Gtk.ShortNames

export SpectrumViewer, SpectrumViewerWidget

mutable struct SpectrumViewerWidget <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  file
  freq
  c
  cbDomain
  cbChan
  adjMinFreq
  adjMaxFreq
  adjFrame
  vbox
  semilogY
  cbBGSubtract
  bgdata
end

function SpectrumViewer(file::MPIFile; semilogY=false)

  w = Window("SpectrumViewer",600,400, true, true)
  dw = SpectrumViewerWidget(file, semilogY=semilogY)
  push!(w,dw)
  showall(w)

  dw
end

function SpectrumViewerWidget(file::MPIFile; semilogY=false)

  vbox = Box(:v)
  hbox = Box(:h)
  push!(vbox, hbox)

  #set_gtk_property!(vbox, :expand, hbox, true)

  cc = Canvas()
  g = Gtk.Grid()

  push!(vbox, g)

  cbDomain = ComboBoxText()

  choices = ["Abs", "Phase", "Real", "Imag"]
  for c in choices
    push!(cbDomain, c)
  end
  set_gtk_property!(cbDomain,:active,0)
  push!(hbox, cbDomain)

  cbChan = ComboBoxText()

  choices = ["x", "y", "z"]
  for c in choices
    push!(cbChan, c)
  end
  set_gtk_property!(cbChan,:active,0)
  push!(hbox, cbChan)

  scFrame = Scale(false, 1:100)
  adjFrame = Adjustment(scFrame)
  push!(hbox,Label("Frame"))
  push!(hbox,scFrame)
  G_.value(scFrame, 0)
  set_gtk_property!(adjFrame,:lower,1)
  set_gtk_property!(adjFrame,:upper,1)
  set_gtk_property!(hbox, :expand, scFrame, true)

  scMinFreq = Scale(false, 1:100)
  adjMinFreq = Adjustment(scMinFreq)
  push!(hbox,Label("MinFreq"))
  push!(hbox,scMinFreq)
  G_.value(scMinFreq, 0)
  set_gtk_property!(adjMinFreq,:lower,1)
  set_gtk_property!(adjMinFreq,:upper,1)
  set_gtk_property!(hbox, :expand, scMinFreq, true)

  scMaxFreq = Scale(false, 1:100)
  adjMaxFreq = Adjustment(scMaxFreq)
  push!(hbox,Label("MaxFreq"))
  push!(hbox,scMaxFreq)
  G_.value(scMaxFreq, 1)
  set_gtk_property!(adjMaxFreq,:lower,1)
  set_gtk_property!(adjMaxFreq,:upper,1)
  set_gtk_property!(hbox, :expand, scMaxFreq, true)

  cbBGSubtract = CheckButton("Subtract last 100 frames as BG")
  push!(hbox,cbBGSubtract)

  g[1,1] = cc

  set_gtk_property!(g, :column_homogeneous, true)
  set_gtk_property!(g, :row_homogeneous, true)

  set_gtk_property!(vbox, :fill, g, true)
  set_gtk_property!(vbox, :expand, g, true)

  # set all widgets

  freq = frequencies(file)

  set_gtk_property!(adjMinFreq,:upper,length(freq))
  set_gtk_property!(adjMaxFreq,:upper,length(freq))
  set_gtk_property!(adjMaxFreq,:value,length(freq))

  set_gtk_property!(adjFrame,:upper, numScans(file))

  bgdata = getMeasurementsFT(file, frames=(numScans(file)-99):numScans(file), nAverages=100)

  dw = SpectrumViewerWidget(vbox.handle, file, freq, cc, cbDomain, cbChan,
   adjMinFreq, adjMaxFreq, adjFrame, vbox,semilogY, cbBGSubtract, bgdata)

  function update( widget )
     Gtk.@sigatom showData( dw )
  end

  signal_connect(update, adjFrame, "value_changed")
  signal_connect(update, adjMinFreq, "value_changed")
  signal_connect(update, adjMaxFreq, "value_changed")
  signal_connect(update, cbDomain, "changed")
  signal_connect(update, cbChan, "changed")
  signal_connect(update, cbBGSubtract, "toggled")

  update( nothing )

  Gtk.gobject_move_ref(dw, vbox)
  dw
end


function showData(d::SpectrumViewerWidget)
  frame = get_gtk_property(d.adjFrame, :value, Int64)
  minFreq = get_gtk_property(d.adjMinFreq, :value, Int64)
  maxFreq = get_gtk_property(d.adjMaxFreq, :value, Int64)
  chan  =  get_gtk_property(d.cbChan, :active, Int64)
  bgsubtract  =  get_gtk_property(d.cbBGSubtract, :active, Bool)

  dataAll = getMeasurementsFT(d.file, frames=frame, recChannels=(chan+1))

  if bgsubtract
    dataAll[:] -= vec(d.bgdata[:,(chan+1),1])
  end

  data = vec(dataAll[minFreq:maxFreq])
  freq = d.freq[minFreq:maxFreq] ./ 1000

  plotfunc=d.semilogY ? Winston.semilogy : Winston.plot

  activeDomainText = Gtk.bytestring( G_.active_text(d.cbDomain))
  if activeDomainText == "Abs"
    p = plotfunc(freq, abs( vec( data ) ) )
  elseif activeDomainText == "Real"
    p = plotfunc(freq, real( vec( data ) ) )
  elseif activeDomainText == "Imag"
    p = plotfunc(freq, imag( vec( data ) ) )
  else
    p = Winston.plot(freq, angle( vec( data ) ) )
  end
  #println(typeof(d.c))

  display(d.c,p)


  showall(d)

end
