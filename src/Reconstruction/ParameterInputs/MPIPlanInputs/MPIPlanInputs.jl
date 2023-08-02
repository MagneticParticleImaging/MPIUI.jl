mutable struct MPIFilePlanInput <: RecoPlanParameterInput
  grid::Gtk4.GtkGrid
  entry::Gtk4.GtkEntry # TODO potentially here have a growing/shrinking list of entries or textbuffer/-view
  cb::Union{Nothing,Function}
  buttons::Vector{GtkCheckButton}
  userChange::Bool
  function MPIFilePlanInput(::Type{<:MPIFile}, value::Union{Missing,MPIFile}, field::Symbol)
    entry = GtkEntry()
    button = GtkButton("Load")
    value = ""
    if value isa MultiContrastFile || value isa MultiMPIFile
      value = join(filepath.(value), ", ")
    elseif value isa MPIFile
      value = filepath(value)
    end
    set_gtk_property!(entry, :text, value)
    set_gtk_property!(entry, :hexpand, true)
    regular = GtkCheckButton("Regular")
    contrast = GtkCheckButton("MultiContrast")
    group(contrast, regular)
    patch = GtkCheckButton("MultiPatch")
    group(patch, regular)
    if value isa MultiContrastFile
      contrast.active = true
    elseif value isa MultiMPIFile
      patch.active = true
    else
      regular.active = true
    end

    grid = GtkGrid()
    grid[1:2, 1] = entry
    grid[3, 1] = button
    grid[1, 2] = regular
    grid[2, 2] = contrast
    grid[3, 2] = patch
    input = new(grid, entry, nothing, [regular, contrast, patch], true)
    
    signal_connect(entry, :activate) do w
      if !isnothing(input.cb)
        input.cb()
      end
    end
    
    for btn in input.buttons
      signal_connect(btn, :toggled) do w
        if !isnothing(input.cb) && btn.active && input.userChange # Only one button should trigger update
          input.cb()
        end
      end
    end
    
    signal_connect(button, :clicked) do w
      multiple = contrast.active || patch.active
      open_dialog("Pick an MDF to open", Gtk4.G_.get_root(button); multiple = multiple) do filenames
        text = filenames isa Vector ? join(filenames, ", ") : filenames
        entry.text = text
        if !isnothing(input.cb)
          input.cb()
        end
      end
    end
    
    return input
  end
end
RecoPlanParameterInput(t::Type{<:MPIFile}, value, field) = MPIFilePlanInput(t, value, field)
widget(input::MPIFilePlanInput) = input.grid
function value(input::MPIFilePlanInput)
  name = input.entry.text
  if isempty(name)
    return missing
  end
  file = MPIFile
  if input.buttons[2].active
    name = string.(split(name, ", "))
    file = MultiContrastFile
  elseif input.buttons[3].active
    name = string.(split(name, ", "))
    file = MultiMPIFile
  end
  return file(name)
end
update!(input::MPIFilePlanInput, value) = update!(input, string(value))
update!(input::MPIFilePlanInput, value::Vector) = update!(input, join(value, ", "))
function update!(input::MPIFilePlanInput, value::MPIFile)
  @idle_add_guarded begin
    input.userChange = false
    input.entry.text = filepath(value)
    input.buttons[1].active = true
    input.userChange = true
  end
end
function update!(input::MPIFilePlanInput, value::MultiContrastFile)
  @idle_add_guarded begin
    input.userChange = false
    input.entry.text = join(filepath.(value), ", ")
    input.buttons[2].active = true
    input.userChange = true
  end
end
function update!(input::MPIFilePlanInput, value::MultiMPIFile)
  @idle_add_guarded begin
    input.userChange = false
    input.entry.text = join(filepath.(value), ", ")
    input.buttons[3].active = true
    input.userChange = true
  end
end
function update!(input::MPIFilePlanInput, value::Missing)
  @idle_add_guarded begin
    input.entry.text = ""
  end
end
callback!(input::MPIFilePlanInput, value) = input.cb = value