
import FileIO: load, save
using Pkg.TOML

mutable struct Settings
  builder
  data

end


const settingspath = abspath(homedir(), ".mpi")
const settingsfile = joinpath(settingspath, "Settings.toml")
const cachefile = joinpath(settingspath, "Cache.jld")
const logpath = joinpath(settingspath, "Logs")
const scannerpath = joinpath(settingspath, "Scanners")
const defaultdatastore = joinpath(settingspath, "Data")

function loadcache()
  if isfile(cachefile)
    cache = load(cachefile)
  else
    cache = Dict{String,Any}()
  end

  if !haskey(cache,"recoParams")
    recoParams = Dict{String,Dict}()
    recoParams["default"] = defaultRecoParams()
    cache["recoParams"] = recoParams
  end

  return cache
end

function savecache(cache)
  rm(cachefile, force=true)
  save(cachefile, cache)
end

getindex(m::Settings, w::AbstractString) = m.data[w] #Gtk4.G_.get_object(m.builder, w)

getindex(m::Settings, w::Symbol) = m.data[w]

function getindex(m::Settings, w, default)
  if haskey(m.data,w)
    return m.data[w]
  else
    return default
  end
end

function Settings()

  uifile = joinpath(@__DIR__,"builder","mpiLab.ui")

  @static if Sys.islinux() || Sys.isapple()
    defaultSettingsFile = joinpath(@__DIR__, "DefaultSettings", "SettingsLinux.toml")
  elseif Sys.iswindows()
    defaultSettingsFile = joinpath(@__DIR__, "DefaultSettings", "SettingsWindows.toml")
  else
    error("Operating system not supported.")
  end

  mkpath(settingspath)
  try_chmod(settingspath, 0o777, recursive=true)
  if !isfile(settingsfile)
    cp(defaultSettingsFile, settingsfile)
  end

  m = Settings( GtkBuilder(uifile), nothing)

  load(m)

  return m
end



function load(m::Settings)
  m.data = TOML.parsefile(settingsfile)

  #@idle_add_guarded set_gtk_property!(m["entSettingsDatasetFolder"], :text, m["datasetDir"])
  #@idle_add_guarded set_gtk_property!(m["entSettingsRecoFolder"], :text, m["reconstructionDir"])
  #@idle_add_guarded set_gtk_property!(m["cbMDFStoreFreqData"], :active, get(m.data, "exportMDFFreqSpace", false))


  #hack for backwards compatibility
  if !haskey(m.data,:recoParams)
    recoParams = Dict{String,Dict}()
    recoParams["default"] = defaultRecoParams()
    m.data["recoParams"] = recoParams
  end

  nothing
end

function save(m::Settings)
  #mkpath(settingspath)
  open(settingsfile,"w") do f
      TOML.print(f,m.data)
  end

  load(m)
  reinit(mpilab[])
end
