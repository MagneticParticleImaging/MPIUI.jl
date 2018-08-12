
import FileIO: load, save

type Settings
  builder
  data

end


const settingspath = joinpath(homedir(),".mpilab")
const settingsfile = joinpath(settingspath, "Settings.toml")
const cachefile = joinpath(settingspath, "Cache.jld")

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

getindex(m::Settings, w::AbstractString) = m.data[w] #G_.object(m.builder, w)

getindex(m::Settings, w::Symbol) = m.data[w]

function getindex(m::Settings, w, default)
  if haskey(m.data,w)
    return m.data[w]
  else
    return default
  end
end

function Settings()

  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","mpiLab.ui")

  defaultSettingsFile = joinpath(Pkg.dir("MPIUI"),"src","Settings.toml")
  mkpath(settingspath)
  try_chmod(settingspath, 0o777, recursive=true)
  if !isfile(settingsfile)
    cp(defaultSettingsFile, settingsfile)
  end

  m = Settings( Builder(filename=uifile), nothing)

  load(m)

  return m
end



function load(m::Settings)
  m.data = TOML.parsefile(settingsfile)

  #Gtk.@sigatom setproperty!(m["entSettingsDatasetFolder"], :text, m["datasetDir"])
  #Gtk.@sigatom setproperty!(m["entSettingsRecoFolder"], :text, m["reconstructionDir"])
  #Gtk.@sigatom setproperty!(m["cbMDFStoreFreqData"], :active, get(m.data, "exportMDFFreqSpace", false))


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
