using MPIUI
using Test
using HTTP, ImageMagick
using Gtk, Cairo

# download test data
datasetstore = MDFDatasetStore("./data")
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

# The image comparison takes into account that the test can run on different
# computers with a differen resolution. For this reason the test images are
# resized to a common size. Since this involves interpolation we need to take
# interpolation errors into account and therefore allow an error of 20%
macro testImg(filename)
    return :(
      im1 = ImageMagick.load(joinpath("img", $filename));
      im2 = imresize( ImageMagick.load(joinpath("correct", $filename)), size(im1));
      d = im1-im2;
      @test (norm(red.(d),1) + norm(green.(d),1) + norm(blue.(d),1)) / (3*length(im1)) < 0.2
      )
end

# tests
include("SFViewer.jl")
include("OfflineRecoWidget.jl")
