import Foundation

///
/// A temporary container for the raw audio data from a single buffered frame.
///
class BufferedFrame: Hashable {
    
    ///
    /// Pointers to the raw data (unsigned bytes) constituting this frame's samples.
    ///
    var rawDataPointers: UnsafeMutableBufferPointer<UnsafeMutablePointer<UInt8>?>
    private var actualDataPointers: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
    
    ///
    /// The number of pointers for which space has been allocated (and that need to be deallocated when this
    /// frame is destroyed).
    ///
    /// # Notes #
    ///
    /// 1. For interleaved (packed) samples, this value will always be 1, as data for all channels will be "packed" into a single buffer.
    ///
    /// 2. For non-interleaved (planar) samples, this value will always equal the channel count, as data for each channel will have its own "plane" (buffer).
    ///
    private var allocatedDataPointerCount: Int
    
    ///
    /// The channel layout for the samples contained in this frame.
    ///
    let channelLayout: UInt64
    
    ///
    /// The channel count for the samples contained in this frame.
    ///
    let channelCount: Int
    
    ///
    /// The number of samples contained in this frame.
    ///
    let sampleCount: Int32
    
    ///
    /// The sampling rate for the samples contained in this frame.
    ///
    let sampleRate: Int32
    
    ///
    /// For interleaved (packed) samples, this value will equal the size in bytes of data for all channels.
    /// For non-interleaved (planar) samples, this value will equal the size in bytes of data for a single channel.
    ///
    let lineSize: Int
    
    ///
    /// The format of the samples contained in this frame.
    ///
    let sampleFormat: SampleFormat
    
    ///
    /// A timestamp indicating this frame's position (order) within the parent audio stream,
    /// specified in stream time base units.
    ///
    /// ```
    /// This can be useful when using concurrency to decode multiple
    /// packets simultaneously. The received frames, in that case,
    /// would be in arbitrary order, and this timestamp can be used
    /// to sort them in the proper presentation order.
    /// ```
    ///
    let timestamp: Int64
    
    init(_ frame: Frame) {
        
        self.timestamp = frame.timestamp

        self.channelLayout = frame.channelLayout
        self.channelCount = Int(frame.channelCount)
        self.sampleCount = frame.sampleCount
        self.sampleRate = frame.sampleRate
        self.lineSize = frame.lineSize
        self.sampleFormat = frame.sampleFormat
        
        self.actualDataPointers = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: channelCount)
        self.allocatedDataPointerCount = 0
        
        let sourceBuffers = frame.dataPointers
        
        // Copy over all the raw data from the source frame into this buffered frame.
        
        // Iterate through all the buffers in the source frame.
        
        // NOTE:
        // - For interleaved (packed) data, there will be only a single source buffer.
        // - For non-interleaved (planar) data, the number of source buffers will equal the channel count.
        
        for bufferIndex in 0..<8 {
            
            guard let sourceBuffer = sourceBuffers[bufferIndex] else {break}
            
            // Allocate memory space equal to lineSize bytes, and initialize the data (copy) from the source buffer.
            actualDataPointers[bufferIndex] = UnsafeMutablePointer<UInt8>.allocate(capacity: lineSize)
            actualDataPointers[bufferIndex]?.initialize(from: sourceBuffer, count: lineSize)
            
            allocatedDataPointerCount += 1
        }
        
        self.rawDataPointers = UnsafeMutableBufferPointer(start: actualDataPointers, count: channelCount)
    }
    
    ///
    /// Produces an array of pointers that are the result of interpreting the original raw sample bytes as planar floating-point samples.
    ///
    /// # Important #
    ///
    /// This property should only be used when the format of the samples contained in this frame is: planar floating-point.
    ///
    /// Otherwise, the Floats referenced by these pointers will be invalid as PCM audio samples.
    ///
    var planarFloatPointers: [UnsafePointer<Float>] {
        
        guard let rawDataPointer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?> = rawDataPointers.baseAddress else {return []}
        
        var floatPointers: [UnsafePointer<Float>] = []
        let intSampleCount: Int = Int(sampleCount)
        
        for channelIndex in 0..<channelCount {
            
            guard let bytesForChannel = rawDataPointer[channelIndex] else {break}
            
            floatPointers.append(bytesForChannel.withMemoryRebound(to: Float.self, capacity: intSampleCount)
            {(pointer: UnsafeMutablePointer<Float>) in
                
                // Convert the UnsafeMutablePointer<Float> into an UnsafePointer<Float>.
                UnsafePointer(pointer)})
        }
        
        return floatPointers
    }
    
    /// Indicates whether or not this object has already been destroyed.
    private var destroyed: Bool = false
    
    ///
    /// Performs cleanup (deallocation of allocated memory space) when
    /// this object is about to be deinitialized or is no longer needed.
    ///
    func destroy() {
        
        // This check ensures that the deallocation happens
        // only once. Otherwise, a fatal error will be
        // thrown.
        if destroyed {return}
        
        // Deallocate the memory space referenced by each of the data pointers.
        for index in 0..<allocatedDataPointerCount {
            self.actualDataPointers[index]?.deallocate()
        }
        
        // Deallocate the space occupied by the pointers themselves.
        self.actualDataPointers.deallocate()
        
        destroyed = true
    }
    
    /// When this object is deinitialized, make sure that its allocated memory space is deallocated.
    deinit {
        destroy()
    }
    
    ///
    /// Equality comparison function (required by the Hashable protocol).
    ///
    /// Two BufferedFrame objects can be considered equal if and only if their timestamps are equal.
    ///
    /// # Important #
    ///
    /// This comparison makes the assumption that both frames originated from the same stream.
    /// Otherwise, this comparison is meaningless and invalid.
    ///
    static func == (lhs: BufferedFrame, rhs: BufferedFrame) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
    
    ///
    /// Hash function (required by the Hashable protocol).
    ///
    /// Uses the timestamp to produce a hash value.
    ///
    func hash(into hasher: inout Hasher) {
        hasher.combine(timestamp)
    }
}
