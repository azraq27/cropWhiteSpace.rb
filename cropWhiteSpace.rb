require 'rubygems'
require 'oily_png'

FinalSize = {
    :width => 4.75, 
    :height => 7.50
}
BlackThreshold = 0.5
InputPDF = ARGV[0]
OutputPDF = ARGV[1]

TempDPI = 150
FinalDPI = 72


ImageMagickConvert = `which convert`

def tempPageName(page)
  "#{InputPDF}.temp#{page}.png"
end

def createTempPage(page)
  `#{ImageMagickConvert} #{InputPDF}'[#{page}]' -density #{TempDPI}x#{TempDPI} #{tempPageName(page)}`
end

def luminance(value)
  (value>>8).to_f/0xffffff
end

def calculateBoundingBox(image)
  bb = {}
  
  # Find top
  catch(:done) {
    (0...image.height).each { |h|
      (0...image.width).each { |w|
        if luminance(image[w,h]) < BlackThreshold
          bb[:top] = h.to_f / TempDPI
          throw :done
        end
      }
    }
  }
  
  # Find bottom
  catch(:done) {
    (0...image.height).to_a.reverse.each { |h|
      (0...image.width).each { |w|
        if luminance(image[w,h]) < BlackThreshold
          bb[:bottom] = h.to_f / TempDPI
          throw :done
        end
      }
    }
  }
  
  # Find left
  catch(:done) {
    (0...image.width).each { |w|
      (0...image.height).each { |h|
        if luminance(image[w,h]) < BlackThreshold
          bb[:left] = w.to_f / TempDPI
          throw :done
        end
      }
    }
  }
  
  # Find right
  catch(:done) {
    (0...image.width).to_a.reverse.each { |w|
      (0...image.height).each { |h|
        if luminance(image[w,h]) < BlackThreshold
          bb[:right] = w.to_f / TempDPI
          throw :done
        end
      }
    }
  }
  
  bb[:height] = bb[:bottom] - bb[:top]
  bb[:width] = bb[:right] - bb[:left]

  return bb
end

def cropPDFPages(bbs)
  inputPDFData = File.open(InputPDF).read
  inputPDFData.gsub!(/MediaBox.*/) { 
    bb = bbs.shift
    "MediaBox [#{bb[:left]} #{bb[:top]} #{bb[:right]} #{bb[:bottom]}] "
  }
  File.open(OutputPDF,"w") { |f| f.puts inputPDFData }
end

def numberOfPages
  File.open(InputPDF).read.scan(/MediaBox/).length
end

n = numberOfPages
bbs = []
mediaBox = {}
(0...n).each { |page|
  createTempPage(page)
  tempPageImage = ChunkyPNG::Image.from_file(tempPageName(page))
  boundingBox = calculateBoundingBox(tempPageImage)  
  
  verticalMargin = (FinalSize[:height] - boundingBox[:height]) / 2
  horizontalMargin = (FinalSize[:width] - boundingBox[:width]) / 2
  mediaBox[:top] = (boundingBox[:top] - verticalMargin) * FinalDPI
  mediaBox[:bottom] = (boundingBox[:bottom] + verticalMargin) * FinalDPI
  mediaBox[:left] = (boundingBox[:left] - horizontalMargin) * FinalDPI
  mediaBox[:right] = (boundingBox[:right] + horizontalMargin) * FinalDPI

  bbs.push mediaBox

  `rm #{tempPageName(page)}`
}
cropPDFPages(bbs)
