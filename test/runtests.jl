using MPIUI
using Test
using HTTP, ImageMagick
using Gtk, Cairo

# download test data
mkpath("./data/")
function download_(filenameServer, filenameLocal)
    if !isfile(filenameLocal)
      @info "download $(filenameLocal)..."
      HTTP.open("GET", "http://media.tuhh.de/ibi/openMPIData/data/"*filenameServer) do http
        open(filenameLocal, "w") do file
          write(file, http)
        end
      end
    end
end

# compare two images
mkpath("img/")
mkpath("correct/")
macro testImg(filename)
    return :(
      im1 = ImageMagick.load(joinpath("img", $filename));
      im2 = ImageMagick.load(joinpath("correct", $filename));
      @test im1 == im2
      )
end

# tests
include("SFViewer.jl")
