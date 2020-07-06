
function initSurveillance(m::MeasurementWidget)
  if !m.expanded
    su = getSurveillanceUnit(m.scanner)

    cTemp = Canvas()
    box = m["boxSurveillance",BoxLeaf]
    push!(box,cTemp)
    set_gtk_property!(box,:expand,cTemp,true)

    showall(box)

    tempInit = getTemperatures(su)
    L = length(tempInit)

    temp = Any[]
    for l=1:L
      push!(temp, zeros(0))
    end

    @guarded function update_(::Timer)
      begin
        te = getTemperatures(su)
        str = join([ @sprintf("%.2f C ",t) for t in te ])
        set_gtk_property!(m["entTemperatures",EntryLeaf], :text, str)

        for l=1:L
          push!(temp[l], te[l])
        end

        if length(temp[1]) > 100
          for l=1:L
            temp[l] = temp[l][2:end]
          end
        end

        L = min(L,7)

        colors = ["b", "r", "g", "y", "k", "c", "m"]

        p = Winston.plot(temp[1], colors[1], linewidth=10)
        for l=2:L
          Winston.plot(p, temp[l], colors[l], linewidth=10)
        end
        #Winston.ylabel("Harmonic $f")
        #Winston.xlabel("Time")
        display(cTemp ,p)
      end
    end
    timer = Timer(update_, 0.0, interval=1.5)
    m.expanded = true
  end
end
