
function initExportCallbacks(m::DataViewerWidget)
  signal_connect(m["btnExportImages"], "clicked") do widget
    try
      exportImages(m)
    catch e
      showError(e)
    end
  end

  signal_connect(m["btnExportTikz"], "clicked") do widget
    try
      exportTikz(m)
    catch e
      showError(e)
    end
  end

  signal_connect(m["btnExportMovi"], "clicked") do widget
    try
      exportMovi(m)
    catch e
      @error e
    #  showError(e)
    end
  end

  signal_connect(m["btnExportAllData"], "clicked") do widget
    try
      exportAllData(m)
    catch e
      showError(e)
    end
  end

  signal_connect(m["btnExportRealDataAllFr"], "clicked") do widget
    try
      exportRealDataAllFr(m)
    catch e
      showError(e)
    end
  end

  signal_connect(m["btnExportData"], "clicked") do widget
    try
      exportData(m)
    catch e
      showError(e)
    end
  end

  signal_connect(m["btnExportProfile"], "clicked") do widget
    exportProfile(m)
  end
end

function exportImages(m::DataViewerWidget)
  if m.currentlyShownImages != nothing
    filter = Gtk4.GtkFileFilter(pattern=String("*.png"), mimetype=String("image/png"))
    diag = save_dialog("Select Export File", mpilab[]["mainWindow"], (filter, )) do filenameImageData
      if filenameImageData != ""
        pixelResizeFactor = get_gtk_property(m["adjPixelResizeFactor"],:value,Int64)
        @info "Export Image as" filenameImageData
        exportImage(filenameImageData, m.currentlyShownImages, pixelResizeFactor=pixelResizeFactor)
      end
    end
    diag.modal = true
  end
end

function exportTikz(m::DataViewerWidget)
  if m.currentlyShownImages != nothing
    filter = Gtk4.GtkFileFilter(pattern=String("*.tikz*"), mimetype=String("image/tikz"))
    diag = save_dialog("Select Export File", mpilab[]["mainWindow"], (filter, )) do filenameImageData
      if filenameImageData != ""
        pixelResizeFactor = get_gtk_property(m["adjPixelResizeFactor"],:value,Int64)
        @info "Export Tikz as" filenameImageData
        props = m.currentlyShownData[1].properties
        SFPath=props["recoParams"][:SFPath]
        bSF = MPIFile(SFPath)
        exportTikz(filenameImageData, m.currentlyShownImages, collect(size(m.dataBG)),
        collect(converttometer(pixelspacing(m.dataBG))),fov(bSF),getParams(m); pixelResizeFactor=pixelResizeFactor)
      end
    end
    diag.modal = true
  end
end

function exportMovi(m::DataViewerWidget)
  filter = Gtk4.GtkFileFilter(pattern=String("*.gif"), mimetype=String("image/gif"))
  diag = save_dialog("Select Export File", mpilab[]["mainWindow"], (filter, )) do filenameMovie
    if filenameMovie != ""
      params = getParams(m)
      sliceMovies = getColoredSlicesMovie(m.data, m.dataBG, m.coloring, params)
      pixelResizeFactor = get_gtk_property(m["adjPixelResizeFactor"],:value, Int64)
      @info "Export Movie as" filenameMovie
      exportMovies(filenameMovie, sliceMovies, pixelResizeFactor=pixelResizeFactor)
    end
  end
  diag.modal = true
end

function exportAllData(m::DataViewerWidget)
  if m.data != nothing
    filter = Gtk4.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
    diag = save_dialog("Select Export File", mpilab[]["mainWindow"], (filter, )) do filenameData
      if filenameData != ""
        params = getParams(m)

        maxval = [maximum(d) for d in m.data]
        minval = [minimum(d) for d in m.data]

        if m.dataBG != nothing
          data_ = interpolateToRefImage(m.dataBG, m.data, params)
          dataBG = interpolateToRefImage(m.dataBG, params)

          data__ = [data(d) for d in data_]

          cdataFG = colorize(data__, m.coloring, minval, maxval, params)

          minval,maxval = extrema(dataBG)
          cdataBG = colorize(dataBG,params[:coloringBG],minval,maxval)

          blendF = get(params, :translucentBlending, false) ? blend : dogyDoge
          cdata = blendF(cdataBG, cdataFG)
        else
          data_ = [data(d) for d in m.data]
          cdata = colorize(data_, m.coloring, minval, maxval, params)
        end

        prop = properties(m.data[1])
        cdata_ = similar(cdata, RGB{N0f8})
        cdata_[:] = convert(ImageMeta{RGB},cdata)[:] #TK: ugly hack

        file, ext = splitext(filenameData)
        savedata_analyze(string(file,".nii"), ImageMeta(cdata_,prop), permRGBData=true)
      end
    end
    diag.modal = true
  end
end

function exportRealDataAllFr(m::DataViewerWidget)
  if m.data != nothing && m.dataBG != nothing
    filter = Gtk4.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
    diag = save_dialog("Select Export File", mpilab[]["mainWindow"], (filter, )) do filenameData
      if filenameData != ""
        params = getParams(m)

        data = interpolateToRefImageAllFr(m.dataBG, m.data, params)
        dataBG = interpolateToRefImage(m.dataBG, params)

        #dataBG_ = applyPermutionsRev(m, dataBG)

        file, ext = splitext(filenameData)
        savedata_analyze(string(file,".nii"), data)
        savedata_analyze(string(file,"_BG.nii"), dataBG)
      end
    end
    diag.modal = true
  end
end

function exportData(m::DataViewerWidget)
  if m.currentlyShownData != nothing
    filter = Gtk4.GtkFileFilter(pattern=String("*.nii"), mimetype=String("application/x-nifti"))
    diag = save_dialog("Select Export File", mpilab[]["mainWindow"], (filter, )) do filenameData
      if filenameData != ""

        params = getParams(m)

        maxval = [maximum(d) for d in m.data]
        minval = [minimum(d) for d in m.data]

        data_ = [data(d) for d in m.currentlyShownData]

        cdata = colorize(data_,m.coloring,minval,maxval,params)

        if m.dataBG != nothing
          minval,maxval = extrema(m.dataBG)
          cdataBG = colorize(m.dataBG,params[:coloringBG],minval,maxval)

          blendF = get(params, :translucentBlending, false) ? blend : dogyDoge
          cdata = blendF(cdataBG, cdata)
        end

        prop = properties(m.currentlyShownData[1])
        cdata_ = similar(cdata, RGB{N0f8})
        cdata_[:] = convert(ImageMeta{RGB},cdata)[:] #TK: ugly hack

        file, ext = splitext(filenameData)
        savedata_analyze(string(file,".nii"), ImageMeta(cdata_,prop), permRGBData=true)
      end
    end
    diag.modal = true
  end
end


function exportProfile(m::DataViewerWidget)
  if m.currentlyShownData != nothing
    filter = Gtk4.GtkFileFilter(pattern=String("*.csv"), mimetype=String("text/comma-separated-values"))
    diag = save_dialog("Select Export File", mpilab[]["mainWindow"], (filter, )) do filenameImageData
      if filenameImageData != "" && m.currentProfile != nothing
        @info "Export Image as" filenameImageData
        writedlm(filenameImageData, m.currentProfile )
      end
    end
    diag.modal = true
  end
end
