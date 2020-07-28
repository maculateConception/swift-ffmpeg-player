import Foundation

class MetadataFileContext {

    let file: URL
    
    let format: FormatContext

    let audioStream: AudioStream
    let audioCodec: AudioCodec
    
    var imageStream: ImageStream?
    let imageCodec: ImageCodec?
    
    init?(_ file: URL) {
        
        self.file = file
        
        guard let theFormatContext = FormatContext(file, [AVMEDIA_TYPE_AUDIO, AVMEDIA_TYPE_VIDEO]),
            let audioStream = theFormatContext.audioStream, let theCodec = audioStream.codec as? AudioCodec else {
                
            return nil
        }

        self.format = theFormatContext
        self.audioStream = audioStream
        self.audioCodec = theCodec
        
        // Image stream, if present, will contain cover art.
        self.imageStream = theFormatContext.imageStream
        self.imageCodec = imageStream?.codec as? ImageCodec
    }
    
    private var destroyed: Bool = false
    
    func destroy() {
        
        if destroyed {return}

        audioCodec.destroy()
        imageCodec?.destroy()
        format.destroy()
        
        destroyed = true
    }

    deinit {
        destroy()
    }
}