
import FileIO: load, save

type Settings
  builder
  data

end


const settingspath = joinpath(homedir(),".mpilab")
#const settingsfile = joinpath(settingspath,"Settings.toml")
const settingsfile = joinpath(Pkg.dir("MPIUI"),"src","Settings.toml")

getindex(m::Settings, w::AbstractString) = m.data[w] #G_.object(m.builder, w)

getindex(m::Settings, w::Symbol) = m.data[w]

function Settings()

  uifile = joinpath(Pkg.dir("MPIUI"),"src","builder","mpiLab.ui")

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
  reinit(mpilab)
end
