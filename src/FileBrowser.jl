

type FileBrowser <: Gtk.GtkBox
  handle::Ptr{Gtk.GObject}
  path::String
  store::ListStore
  entry::Entry
  combo::GtkComboBoxText
  recentFolder::Vector{String}
end

function FileBrowser()
  store = ListStore(String,String)

  tv = TreeView(TreeModel(store))
  G_.headers_visible(tv,false)
  r1 = CellRendererPixbuf()
  r2 = CellRendererText()
  c1 = TreeViewColumn("Files", r1, Dict("stock-id" => 1))
  push!(c1,r2)
  Gtk.add_attribute(c1,r2,"text",0)
  G_.sort_column_id(c1,0)
  G_.resizable(c1,true)
  G_.max_width(c1,80)
  push!(tv,c1)

  sw = ScrolledWindow()
  push!(sw,tv)

  combo = GtkComboBoxText(true)
  entry = G_.child(combo)
  btnUp = ToolButton("gtk-go-up")
  btnChooser = ToolButton("gtk-open")
  btnPkgDir = ToolButton("gtk-directory")
  set_gtk_property!(btnPkgDir,"tooltip-text","Open Package Directory")
  btnHome = ToolButton("gtk-home")
  set_gtk_property!(btnHome,"tooltip-text","Open Home Directory")

  set_gtk_property!(entry,:editable,false)
  toolbar = Toolbar()
  push!(toolbar,btnUp,btnChooser, btnHome, btnPkgDir)
  G_.style(toolbar,GtkToolbarStyle.ICONS)
  G_.icon_size(toolbar,GtkIconSize.MENU)

  box = Box(:v)
  push!(box,combo)
  push!(box,toolbar)
  push!(box,sw)
  set_gtk_property!(box,:expand,sw,true)

  recentFolder = String[]

  browser = FileBrowser(box.handle, "", store, entry, combo, recentFolder)

  changedir!(browser, pwd())

  signal_connect(btnUp, "clicked") do widget
    cd("..")
    changedir!(browser,pwd())
  end

  signal_connect(btnPkgDir, "clicked") do widget
    cd(Pkg.dir())
    changedir!(browser,pwd())
  end

  signal_connect(btnHome, "clicked") do widget
    cd(homedir())
    changedir!(browser,pwd())
  end


  signal_connect(btnChooser, "clicked") do widget
    dlg = FileChooserDialog("Select folder", Null(), GtkFileChooserAction.SELECT_FOLDER,
                             "gtk-cancel", GtkResponseType.CANCEL,
                             "gtk-open", GtkResponseType.ACCEPT)
    if ret == GtkResponseType.ACCEPT
      path = Gtk.bytestring(Gtk._.filename(dlg),true)
      changedir!(browser,path)
    end
    destroy(dlg)
  end

  selection = G_.selection(tv)

  println(selection)

  signal_connect(tv, "row-activated") do treeview, path, col, other...
    if hasselection(selection)
      currentIt = selected( selection )

      file = store[currentIt,1]

      newpath = joinpath(browser.path,file)

      println(newpath)

      if isdir(newpath)
        changedir!(browser, newpath)
      else

      end
    end
    false
  end

  Gtk.gobject_move_ref(browser, box)
  browser
end

function changedir!(browser::FileBrowser, path::String)
  browser.path = path
  push!(browser.recentFolder,path)
  push!(browser.combo,path)
  G_.text(browser.entry,path)
  G_.position(Editable(browser.entry),-1)

  update!(browser)
end

function update!(browser::FileBrowser)
  empty!(browser.store)
  cd(browser.path)
  files = readdir()
  for file in files
    filename, ext = splitext(file)
    if isfile(file) &&
      (!isdir(file) || ext == ".nii" || ext == ".img" || ext == ".mdf")
      stock = isdir(file) ? "gtk-directory" : "gtk-file"
      push!(browser.store, (file,stock))
    end
  end
end
