mutable struct PositionParameter <: Gtk.GtkExpander
  handle::Ptr{Gtk.GObject}
  builder::GtkBuilder
  field::Symbol

  function PositionParameter(field::Symbol, posValue::Union{Positions, Nothing})
    uifile = joinpath(@__DIR__, "..", "builder", "positionsWidget.ui")
    b = Builder(filename=uifile)
    posObj = G_.object(b, "expPositions")
    #addTooltip(object_(pw.builder, "lblPositions", GtkLabel), tooltip)
    posParam = new(posObj.handle, b, field)
    updatePositions(posParam, posValue)
    initCallbacks(posParam)
    return Gtk.gobject_move_ref(posParam, posObj)
  end
end

getindex(m::PositionParameter, w::AbstractString, T::Type) = object_(m.builder, w, T)

function initCallbacks(posParam::PositionParameter)
  signal_connect(posParam["btnLoadFilePos", ButtonLeaf], :clicked) do w
    loadFilePos(posParam)
  end
end

function updatePositions(posParam::PositionParameter, pos::Union{Positions, Nothing})
  if !isnothing(pos)
    shp = MPIFiles.shape(pos)
    shpStr = @sprintf("%d x %d x %d", shp[1],shp[2],shp[3])
    fov = Float64.(ustrip.(uconvert.(Unitful.mm,MPIFiles.fieldOfView(pos)))) # convert to mm
    fovStr = @sprintf("%.2f x %.2f x %.2f", fov[1],fov[2],fov[3])
    ctr = Float64.(ustrip.(uconvert.(Unitful.mm,MPIFiles.fieldOfViewCenter(pos)))) # convert to mm
    ctrStr = @sprintf("%.2f x %.2f x %.2f", ctr[1],ctr[2],ctr[3])
    @idle_add_guarded begin 
      set_gtk_property!(posParam["entGridShape",EntryLeaf], :text, shpStr)
      set_gtk_property!(posParam["entFOV",EntryLeaf], :text, fovStr)
      set_gtk_property!(posParam["entCenter",EntryLeaf], :text, ctrStr)
      set_gtk_property!(posParam["cbUseArbitraryPos", CheckButtonLeaf], :sensitive, false)
      set_gtk_property!(posParam["entArbitraryPos",EntryLeaf],:text, "")
    end
  end
end

function setProtocolParameter(posParam::PositionParameter, params::ProtocolParams)
  # Construct pos
  @info "Trying to set pos"
  cartGrid = nothing
  if get_gtk_property(posParam["cbUseArbitraryPos",CheckButtonLeaf], :active, Bool) == false
    
    shpString = get_gtk_property(posParam["entGridShape",EntryLeaf], :text, String)
    shp_ = tryparse.(Int64,split(shpString,"x"))
    fovString = get_gtk_property(posParam["entFOV",EntryLeaf], :text, String)
    fov_ = tryparse.(Float64,split(fovString,"x"))
    centerString = get_gtk_property(posParam["entCenter",EntryLeaf], :text, String)
    center_ = tryparse.(Float64,split(centerString,"x"))
    if any(shp_ .== nothing) || any(fov_ .== nothing) || any(center_ .== nothing)  ||
     length(shp_) != 3 || length(fov_) != 3 || length(center_) != 3
      @warn "Mismatch dimension for positions"
      # TODO throw some sort of exception
      return
    end
    shp = shp_
    fov = fov_ .*1Unitful.mm
    ctr = center_ .*1Unitful.mm
    cartGrid = RegularGridPositions(shp,fov,ctr)
  
  else
    
    filename = get_gtk_property(posParam["entArbitraryPos",EntryLeaf],:text,String)
    if filename != ""
        cartGrid = h5open(filename, "r") do file
            positions = Positions(file)
        end
    else
      error("Filename Arbitrary Positions empty!")
    end

  end

  setfield!(params, posParam.field, cartGrid)
end

function loadFilePos(posParam::PositionParameter)
  filter = Gtk.GtkFileFilter(pattern=String("*.h5"), mimetype=String("HDF5 File"))
  filename = open_dialog("Select Position File", GtkNullContainer(), (filter, ))
  @idle_add_guarded begin 
    set_gtk_property!(posParam["entArbitraryPos",EntryLeaf],:text,filename)
    if filename != ""
      set_gtk_property!(posParam["cbUseArbitraryPos", CheckButtonLeaf], :sensitive, true)
    end
  end
end

