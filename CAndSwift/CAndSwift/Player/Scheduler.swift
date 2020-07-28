import AVFoundation

class Scheduler {
    
    let decoder: Decoder = Decoder()
    let audioEngine: AudioEngine = AudioEngine()
    
    private var file: AudioFileContext!
    private var codec: AudioCodec! {file.audioCodec}
    
    private var sampleCountForImmediatePlayback: Int32 = 0
    private var sampleCountForDeferredPlayback: Int32 = 0
    
    var audioFormat: AVAudioFormat!
    
    var scheduledBufferCount: Int = 0
    
    private let schedulingOpQueue: OperationQueue = {
        
        let queue = OperationQueue()
        queue.underlyingQueue = DispatchQueue.global(qos: .userInitiated)
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        
        return queue
    }()
    
    func initialize(with file: AudioFileContext) throws {
        
        self.file = file
        
        let sampleRate: Int32 = codec.sampleRate
        let channelCount: Int32 = codec.params.channels
        let effectiveSampleRate: Int32 = sampleRate * channelCount
        
        switch effectiveSampleRate {
            
        case 0..<100000:
            
            // 44.1 / 48 KHz stereo
            
            sampleCountForImmediatePlayback = 5 * sampleRate
            sampleCountForDeferredPlayback = 10 * sampleRate
            
        case 100000..<500000:
            
            // 96 / 192 KHz stereo
            
            sampleCountForImmediatePlayback = 3 * sampleRate
            sampleCountForDeferredPlayback = 10 * sampleRate
            
        default:
            
            // 96 KHz surround and higher sample rates
            
            sampleCountForImmediatePlayback = 2 * sampleRate
            sampleCountForDeferredPlayback = 7 * sampleRate
        }
        
        try decoder.initialize(with: file)
    }
    
    func initiateScheduling(from seekPosition: Double? = nil) throws {
        
        if let theSeekPosition = seekPosition {
            try decoder.seekToTime(theSeekPosition)
        }
        
        scheduleOneBuffer()
        
        // TODO: Check for EOF here ???
        scheduleOneBufferAsync()
    }
    
    private func scheduleOneBufferAsync() {
        
        self.schedulingOpQueue.addOperation {
            self.scheduleOneBuffer()
        }
    }
    
    private func scheduleOneBuffer() {
        
        let time = measureTime {
            
            do {
            
                if let buffer: SamplesBuffer = try decoder.decode(sampleCountForImmediatePlayback), let audioBuffer: AVAudioPCMBuffer = buffer.constructAudioBuffer(format: audioFormat) {
                    
                    audioEngine.scheduleBuffer(audioBuffer, {
                        
                        self.scheduledBufferCount -= 1
                        
                        if self.audioEngine.isPlaying {
                            
                            if !self.decoder.eof {
    
                                self.scheduleOneBufferAsync()
                                print("\nEnqueued one scheduling op ... (\(self.schedulingOpQueue.operationCount))")
    
                            } else if self.scheduledBufferCount == 0 {
    
                                DispatchQueue.main.async {
                                    self.playbackCompleted()
                                }
                            }
                        }
                    })
                    
                    // Write out the raw samples to a .raw file for testing in Audacity
                    //            BufferFileWriter.writeBuffer(audioBuffer)
                    //            BufferFileWriter.closeFile()
                    
                    scheduledBufferCount += 1
                    buffer.destroy()
                }
                
            } catch {
                print("\nDecoder threw error: \(error)")
            }
            
//            if eof {
//                NSLog("Reached EOF !!!")
//            }
        }
        
        print("\nTook \(Int(round(time * 1000))) msec to schedule a buffer")
    }
    
    func stop() {
        
        let time = measureTime {
            
            if schedulingOpQueue.operationCount > 0 {
                
                schedulingOpQueue.cancelAllOperations()
                schedulingOpQueue.waitUntilAllOperationsAreFinished()
            }
        }
        
        print("\nWaited \(time * 1000) msec for previous ops to stop.")
    }
    
    private func playbackCompleted() {
        
        // TODO: What does the scheduler need to do here ?
        
        NSLog("Playback completed !!!\n")
        
        stop()
        audioEngine.playbackCompleted()
        
        NotificationCenter.default.post(name: .playbackCompleted, object: self)
    }
}