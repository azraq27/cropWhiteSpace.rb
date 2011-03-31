require 'rubygems'
require 'oily_png'

FinalSize = {
    :width => 4.75, 
    :height => 7.50
}
BlackThreshold = 0.5
InputPDF = ARGV[0]
OutputPDF = ARGV[1]

TempDPI = 50

Debug = true

def getImageInfo(filename)
  info = {}
  `sips -g all #{filename}`.split("\n")[1..-1].each { |attr|
    keyvalue = attr.strip.split(": ")
    info[keyvalue[0].to_sym] = keyvalue[1]
  }

  info[:inchHeight] = info[:pixelHeight].to_f / info[:dpiHeight].to_f
  info[:inchWidth] = info[:pixelWidth].to_f / info[:dpiWidth].to_f
  puts info.inspect if Debug
  return info
end

PDFInfo = getImageInfo(InputPDF)

def tempPageName(page,suffix)
  "#{InputPDF}.temp#{page}.#{suffix}"
end

def extractPDFPage(docName,page,outputName)
  `gs -q -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -dQUIET -dSAFER -dFirstPage=#{page} -dLastPage=#{page} -sOutputFile="#{outputName}" "#{docName}"`
end

def createTempPage(page)
  `gs -q -sDEVICE=png16m -r#{TempDPI} -dNOPAUSE -dBATCH -dQUIET -dSAFER -dFirstPage=#{page} -dLastPage=#{page} -sOutputFile="#{tempPageName(page,"png")}" "#{InputPDF}"`
end

def luminance(value)
  r = value>>24
  g = value>>16 & 0xff
  b = value>>8 & 0xff
  l = (0.2126*r + 0.7152*g + 0.0722*b) / 0xff
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

def calculateCenterOfMass(image)
  bb = {}
  
  File.open("test.txt","w") { |f|
    (0...image.height).each { |h|
      (0...image.width).each { |w|
        f.puts luminance(image[w,h])
      }
    }
  }
  
  # Vertical center of mass
  verticalMass = (0...image.height).collect { |h|
    (0...image.width).inject(0) { |sum,w| luminance(image[w,h]) < BlackThreshold ? sum+1 : sum }
  }
  verticalMassCenter = verticalMass.inject(0) { |s,i| s+i } / 2
  verticalMassCenterY = 0
  (0...image.height).inject(0) { |s,h|
    if s > verticalMassCenter
      verticalMassCenterY = h
      break
    end
    s + verticalMass[h]
  }
  
  # Horizontal center of mass
  horizontalMass = (0...image.width).collect { |w|
    (0...image.height).inject(0) { |sum,h| luminance(image[w,h]) < BlackThreshold ? sum+1 : sum }
  }
  horizontalMassCenter = horizontalMass.inject(0) { |s,i| s+i } / 2
  horizontalMassCenterX = 0
  (0...image.width).inject(0) { |s,w|
    if s > horizontalMassCenter
      horizontalMassCenterX = w
      break
    end
    s + horizontalMass[w]
  }

  {:x => horizontalMassCenterX.to_f / TempDPI, :y => (image.height - verticalMassCenterY).to_f / TempDPI}
end

def cropPDFPages(bbs)
  inputPDFData = File.open(InputPDF).read
  inputPDFData.gsub!(/MediaBox \[[0-9 ]+\]/) { 
    bb = bbs.shift
    "MediaBox [#{bb[:left]} #{bb[:top]} #{bb[:right]} #{bb[:bottom]}] "
  }
  File.open(OutputPDF,"w") { |f| f.puts inputPDFData }
end

def numberOfPages
  m = `pdfinfo #{InputPDF}`.match(/^Pages:\s+([0-9]+)$/)
  m ? m[1].to_i : nil
end

n = numberOfPages
puts n
bbs = []
mediaBox = {}
(1..n).each { |page|
  createTempPage(page)
  tempPageImage = ChunkyPNG::Image.from_file(tempPageName(page,"png"))

=begin
  com = calculateCenterOfMass(tempPageImage)
  puts com.inspect
  mediaBox[:top] = (com[:y] + FinalSize[:height]/2) * FinalDPI
  mediaBox[:bottom] = (com[:y] - FinalSize[:height]/2) * FinalDPI
  mediaBox[:left] = (com[:x] - FinalSize[:width]/2) * FinalDPI
  mediaBox[:right] = (com[:x] + FinalSize[:width]/2) * FinalDPI
  puts mediaBox.inspect
=end

  boundingBox = calculateBoundingBox(tempPageImage)  
  puts boundingBox.inspect
  
  verticalMargin = (FinalSize[:height] - boundingBox[:height]) / 2
  horizontalMargin = (FinalSize[:width] - boundingBox[:width]) / 2

  mediaBox[:top] = (FinalSize[:height] - (boundingBox[:top] - verticalMargin)) * PDFInfo[:dpiHeight].to_f
  mediaBox[:bottom] = (FinalSize[:height] - (boundingBox[:bottom] + verticalMargin)) * PDFInfo[:dpiHeight].to_f
  mediaBox[:left] = (boundingBox[:left] - horizontalMargin) * PDFInfo[:dpiWidth].to_f
  mediaBox[:right] = (boundingBox[:right] + horizontalMargin) * PDFInfo[:dpiWidth].to_f

  bbs.push mediaBox

#  `rm #{tempPageName(page,"png")}`
}
cropPDFPages(bbs)
