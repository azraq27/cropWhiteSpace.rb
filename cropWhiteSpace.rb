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
          bb[:top] = h.to_f
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
          bb[:bottom] = h.to_f
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
          bb[:left] = w.to_f
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
          bb[:right] = w.to_f
          throw :done
        end
      }
    }
  }
  
  bb[:height] = bb[:bottom] - bb[:top]
  bb[:width] = bb[:right] - bb[:left]

  if Debug
    [bb[:top], bb[:bottom]].each { |h| (bb[:left].to_i..bb[:right].to_i).each { |w| image[w,h] = ChunkyPNG::Color('red') }}
    [bb[:left], bb[:right]].each { |w| (bb[:top].to_i..bb[:bottom].to_i).each { |h| image[w,h] = ChunkyPNG::Color('red') }}
  end    

  bbInches = {}
  bb.each { |k,v| bbInches[k] = v / TempDPI }

  return bbInches
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
  inputPDFData.gsub!(/MediaBox \[[^\]]*\]/) { 
    bb = bbs.shift
    "MediaBox [#{bb[:left]} #{bb[:top]} #{bb[:right]} #{bb[:bottom]}] "
  }
  File.open(OutputPDF,"w") { |f| f.puts inputPDFData }
end

def numberOfPages
#  m = `pdfinfo #{InputPDF}`.match(/^Pages:\s+([0-9]+)$/)
#  m ? m[1].to_i : nil
  File.open(InputPDF).read.scan(/\/Count ([0-9]+)/).sort[-1][0].to_i
end

n = numberOfPages
puts "Processing #{n} pages" if Debug
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
   
  puts "Calculated boundingBox for page #{page}:  " + boundingBox.inspect if Debug
  
  verticalMargin = (FinalSize[:height] - boundingBox[:height]) / 2
  horizontalMargin = (FinalSize[:width] - boundingBox[:width]) / 2

  mediaBox[:top] = (boundingBox[:top] - verticalMargin)# + (200.0/72.0)
  mediaBox[:bottom] = (boundingBox[:bottom] + verticalMargin)# + (200.0/72.0)
  mediaBox[:left] = (boundingBox[:left] - horizontalMargin)
  mediaBox[:right] = (boundingBox[:right] + horizontalMargin)


  mediaBox72dpi = {}
  mediaBox.each { |k,v| mediaBox72dpi[k] = v * 72.0 }
  mediaBoxTempdpi = {}
  mediaBox.each { |k,v| mediaBoxTempdpi[k] = v * TempDPI }

  if Debug
    [mediaBoxTempdpi[:top], mediaBoxTempdpi[:bottom]].each { |h| (mediaBoxTempdpi[:left].to_i..mediaBoxTempdpi[:right].to_i).each { |w| tempPageImage[w,h] = ChunkyPNG::Color('blue') }}
    [mediaBoxTempdpi[:left], mediaBoxTempdpi[:right]].each { |w| (mediaBoxTempdpi[:top].to_i..mediaBoxTempdpi[:bottom].to_i).each { |h| tempPageImage[w,h] = ChunkyPNG::Color('blue') }}
    tempPageImage.save(tempPageName(page,"png"))
  end

  puts "Calculated mediaBox for page #{page}:  " + mediaBoxTempdpi.inspect if Debug

  bbs.push mediaBox72dpi

  `rm #{tempPageName(page,"png")}` if ! Debug
}
cropPDFPages(bbs)
