import Foundation
import AVFoundation
import Cocoa
import VideoToolbox

/// Video stream handler for AR.Drone 2.0
/// Receives H.264 video stream on TCP port 5555 with PaVE header
class VideoStreamHandler: NSObject {
    
    private let droneIP = "192.168.1.1"
    private let videoPort: UInt16 = 5555
    
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var isStreaming = false
    
    // Video display layer
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var videoView: NSView?
    
    // H.264 Decoder
    private var formatDescription: CMFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private var spsData: Data?
    private var ppsData: Data?
    
    // Video recording
    private(set) var isRecording = false
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var recordingURL: URL?
    private var recordingStartTime: CMTime?
    
    // Frame buffer
    private var frameBuffer = Data()
    private let maxBufferSize = 1024 * 1024 * 10
    
    // Callbacks
    var onFrameReceived: ((Data) -> Void)?
    var onVideoError: ((Error) -> Void)?
    var onRecordingStarted: ((URL) -> Void)?
    var onRecordingStopped: ((URL) -> Void)?
    
    // Statistics
    private(set) var frameCount: Int = 0
    private(set) var bytesReceived: Int64 = 0
    private(set) var fps: Double = 0.0
    private var lastFrameTime: Date?
    private var fpsCounter = 0
    private var fpsTimer: Timer?
    
    // MARK: - Display Setup
    
    func setupDisplayLayer(in view: NSView) {
        self.videoView = view
        
        // Forcer la taille si la vue n'a pas encore de bounds
        let targetFrame = view.bounds.width > 0 ? view.bounds : CGRect(x: 0, y: 0, width: 600, height: 400)
        
        // Create and configure display layer
        let layer = AVSampleBufferDisplayLayer()
        layer.frame = targetFrame  // ⬅️ Utiliser targetFrame
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        
        // IMPORTANT : Contrôle de la synchronisation
        var controlTimebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &controlTimebase
        )
        
        if let timebase = controlTimebase {
            layer.controlTimebase = timebase
            CMTimebaseSetTime(timebase, time: .zero)
            CMTimebaseSetRate(timebase, rate: 1.0)
        }
        
        view.wantsLayer = true
        
        if view.layer == nil {
            view.layer = CALayer()
            view.layer?.backgroundColor = NSColor.black.cgColor
        }
        
        view.layer?.addSublayer(layer)
        self.displayLayer = layer
                
        // Mettre à jour après un instant
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if view.bounds.width > 0 {
                layer.frame = view.bounds
            }
        }
        
        // Setup FPS counter
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.fps = Double(self.fpsCounter)
            self.fpsCounter = 0
        }
    }
    
    // MARK: - Stream Management
    
    func startStreaming() {
        guard !isStreaming else { return }
        
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(
            kCFAllocatorDefault,
            droneIP as CFString,
            UInt32(videoPort),
            &readStream,
            &writeStream
        )
        
        guard let readStream = readStream?.takeRetainedValue(),
              let writeStream = writeStream?.takeRetainedValue() else {
            print("❌ Failed to create video streams")
            return
        }
        
        inputStream = readStream as InputStream
        outputStream = writeStream as OutputStream
        
        inputStream?.delegate = self
        inputStream?.schedule(in: .main, forMode: .common)
        
        inputStream?.open()
        outputStream?.open()
        
        isStreaming = true
        resetStatistics()
        print("📹 Video streaming started on port \(videoPort)")
    }
    
    func stopStreaming() {
        guard isStreaming else { return }
        
        stopRecording()
        
        inputStream?.close()
        inputStream?.remove(from: .main, forMode: .common)
        inputStream = nil
        
        outputStream?.close()
        outputStream = nil
        
        // Cleanup decoder
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        
        fpsTimer?.invalidate()
        fpsTimer = nil
        
        isStreaming = false
        frameBuffer.removeAll()
        spsData = nil
        ppsData = nil
        print("📹 Video streaming stopped")
    }
    
    // MARK: - H.264 Decoder Setup
    
    private func createDecoderWithSPSPPS() {
        guard let sps = spsData, let pps = ppsData else {
            print("⚠️ Missing SPS or PPS")
            return
        }
        
        guard decompressionSession == nil else { return }
        
        print("🔧 Creating decoder with SPS (\(sps.count) bytes) and PPS (\(pps.count) bytes)")
        
        // Create format description avec SPS/PPS
        let parameterSetPointers: [UnsafePointer<UInt8>] = [
            (sps as NSData).bytes.bindMemory(to: UInt8.self, capacity: sps.count),
            (pps as NSData).bytes.bindMemory(to: UInt8.self, capacity: pps.count)
        ]
        
        let parameterSetSizes: [Int] = [sps.count, pps.count]
        
        var formatDesc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: 2,
            parameterSetPointers: parameterSetPointers,
            parameterSetSizes: parameterSetSizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &formatDesc
        )
        
        guard status == noErr, let formatDescription = formatDesc else {
            print("❌ Failed to create format description with SPS/PPS: \(status)")
            return
        }
        
        self.formatDescription = formatDescription
        
        // Create decompression session
        var decompressionSessionOut: VTDecompressionSession?
        let decoderParameters = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ] as CFDictionary
        
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        let decodeStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: decoderParameters,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &decompressionSessionOut
        )
        
        guard decodeStatus == noErr, let session = decompressionSessionOut else {
            print("❌ Failed to create decompression session: \(decodeStatus)")
            return
        }
        
        self.decompressionSession = session
        print("✅ H.264 decoder initialized with SPS/PPS")
    }
    
    // MARK: - Recording
    
    func startRecording() {
        guard !isRecording else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "ARDrone_\(timestamp).mp4"
        recordingURL = documentsPath.appendingPathComponent(filename)
        
        guard let url = recordingURL else { return }
        
        do {
            try? FileManager.default.removeItem(at: url)
            
            videoWriter = try AVAssetWriter(url: url, fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2000000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            if let input = videoWriterInput, let writer = videoWriter {
                if writer.canAdd(input) {
                    writer.add(input)
                }
                
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)
                recordingStartTime = CMTime.zero
                
                isRecording = true
                print("🔴 Recording started: \(filename)")
                onRecordingStarted?(url)
            }
        } catch {
            print("❌ Failed to start recording: \(error)")
            onVideoError?(error)
        }
    }
    
    func stopRecording() {
        guard isRecording, let writer = videoWriter, let url = recordingURL else { return }
        
        isRecording = false
        
        videoWriterInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            print("⏹ Recording stopped: \(url.lastPathComponent)")
            self?.onRecordingStopped?(url)
        }
        
        videoWriter = nil
        videoWriterInput = nil
        recordingURL = nil
        recordingStartTime = nil
    }
    
    // MARK: - Statistics
    
    private func updateStatistics() {
        frameCount += 1
        fpsCounter += 1
        
        if let lastTime = lastFrameTime {
            let interval = Date().timeIntervalSince(lastTime)
            if interval > 0 && interval < 1.0 {
                // Smooth FPS calculation
                let instantFPS = 1.0 / interval
                fps = (fps * 0.9) + (instantFPS * 0.1)
            }
        }
        lastFrameTime = Date()
    }
    
    func resetStatistics() {
        frameCount = 0
        bytesReceived = 0
        fps = 0.0
        fpsCounter = 0
        lastFrameTime = nil
    }
}

// MARK: - Stream Delegate

extension VideoStreamHandler: StreamDelegate {
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let inputStream = aStream as? InputStream else { return }
            
            let bufferSize = 65536 // 64KB chunks
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
                
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    frameBuffer.append(data)
                    bytesReceived += Int64(bytesRead)
                    
                    // PROTECTION: Ne traiter que si buffer >= 68 bytes
                    if frameBuffer.count >= 68 {
                        processFrameBuffer()
                    }
                } else if bytesRead < 0 {
                    // Erreur de lecture
                    print("❌ Stream read error: \(inputStream.streamError?.localizedDescription ?? "unknown")")
                    break
                }
            }
            
        case .errorOccurred:
            if let error = aStream.streamError {
                print("❌ Video stream error: \(error)")
                onVideoError?(error)
            }
            
        case .endEncountered:
            print("📹 Video stream ended")
            stopStreaming()
            
        default:
            break
        }
    }
    
    private func processFrameBuffer() {
        // Look for PaVE header signature
        while frameBuffer.count >= 68 { // Minimum PaVE header size
            
            // Safe header parsing avec Data isolé
            let headerData = frameBuffer.prefix(min(frameBuffer.count, 1024))
            guard let header = PaVEHeader.parse(from: headerData) else {
                // Search for next PaVE signature
                let paveSignature = Data([0x50, 0x61, 0x56, 0x45])
                if let range = frameBuffer.range(of: paveSignature) {
                    // Found signature, skip to it
                    let skipBytes = range.lowerBound
                    if skipBytes > 0 {
                        frameBuffer.removeFirst(skipBytes)
                    }
                } else {
                    // No signature found, keep last 3 bytes (in case signature is split)
                    if frameBuffer.count > 3 {
                        frameBuffer.removeFirst(frameBuffer.count - 3)
                    }
                    break
                }
                continue
            }
            
            let totalFrameSize = Int(header.headerSize) + Int(header.payloadSize)
            
            // Sanity check renforcé
            guard totalFrameSize > 68 && totalFrameSize < 1_000_000 else {
                frameBuffer.removeFirst(min(4, frameBuffer.count))
                continue
            }
            
            // Check if we have the complete frame
            guard frameBuffer.count >= totalFrameSize else {
                break // Wait for more data
            }
            
            // PROTECTION MAXIMALE pour l'extraction du payload
            let payloadStart = Int(header.headerSize)
            let payloadSize = Int(header.payloadSize)
            
            // Vérifications strictes
            guard payloadStart > 0,
                  payloadStart < frameBuffer.count,
                  payloadSize > 0,
                  payloadSize < 500_000 else {
                frameBuffer.removeFirst(min(4, frameBuffer.count))
                continue
            }
            
            let payloadEnd = payloadStart + payloadSize
            
            guard payloadEnd > payloadStart,
                  payloadEnd <= frameBuffer.count else {
                frameBuffer.removeFirst(min(4, frameBuffer.count))
                continue
            }
            
            // Extraction ULTRA-sécurisée avec copie manuelle byte par byte
            var h264Payload = Data()
            h264Payload.reserveCapacity(payloadSize)
            
            var extractionSuccess = false
            frameBuffer.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
                guard let baseAddress = bufferPointer.baseAddress else { return }
                guard bufferPointer.count >= payloadEnd else { return }
                
                let payloadPointer = baseAddress.advanced(by: payloadStart)
                let rawBuffer = UnsafeRawBufferPointer(start: payloadPointer, count: payloadSize)
                h264Payload.append(contentsOf: rawBuffer)
                extractionSuccess = true
            }
            
            guard extractionSuccess, h264Payload.count == payloadSize else {
                frameBuffer.removeFirst(min(4, frameBuffer.count))
                continue
            }
            
            guard h264Payload.count > 0 else {
                frameBuffer.removeFirst(min(totalFrameSize, frameBuffer.count))
                continue
            }
            
            // Decode frame
            decodeFrame(h264Payload, frameNumber: header.frameNumber)
            
            // Remove processed frame from buffer
            let bytesToRemove = min(totalFrameSize, frameBuffer.count)
            if bytesToRemove > 0 && bytesToRemove <= frameBuffer.count {
                frameBuffer.removeFirst(bytesToRemove)
            } else {
                frameBuffer.removeAll(keepingCapacity: true)
                break
            }
            
            // Update stats
            updateStatistics()
            
            // Callback
            onFrameReceived?(h264Payload)
        }
        
        // Limit buffer size
        if frameBuffer.count > maxBufferSize {
            print("⚠️ Frame buffer overflow (\(frameBuffer.count) bytes), clearing...")
            frameBuffer.removeAll(keepingCapacity: true)
        }
    }
    
    private func decodeFrame(_ h264Data: Data, frameNumber: UInt32) {
        guard h264Data.count > 4 else { return }
        
        // Parser les NAL units
        let nalUnits = parseNALUnits(from: h264Data)
        
        var hasVideoData = false
        
        for nal in nalUnits where nal.count > 0 {
            let nalType = nal[0] & 0x1F
            
            switch nalType {
            case 7: // SPS
                if spsData == nil || spsData != nal {
                    spsData = nal
                    print("✅ Found SPS (\(nal.count) bytes)")
                    // Réinitialiser le decoder
                    if let session = decompressionSession {
                        VTDecompressionSessionInvalidate(session)
                        decompressionSession = nil
                    }
                    if ppsData != nil {
                        createDecoderWithSPSPPS()
                    }
                }
                
            case 8: // PPS
                if ppsData == nil || ppsData != nal {
                    ppsData = nal
                    print("✅ Found PPS (\(nal.count) bytes)")
                    // Réinitialiser le decoder
                    if let session = decompressionSession {
                        VTDecompressionSessionInvalidate(session)
                        decompressionSession = nil
                    }
                    if spsData != nil {
                        createDecoderWithSPSPPS()
                    }
                }
                
            case 1, 5: // P-frame ou I-frame
                hasVideoData = true
                
            default:
                break
            }
        }
        
        // Décoder seulement si on a une frame vidéo ET un decoder
        guard hasVideoData, let session = decompressionSession else {
            return
        }
        
        // Convertir directement en AVCC sans passer par Annex-B
        var avccData = Data()
        
        for nal in nalUnits where nal.count > 0 {
            let nalType = nal[0] & 0x1F
            
            // Ignorer SPS/PPS dans le stream vidéo (déjà dans le format description)
            guard nalType == 1 || nalType == 5 else { continue }
            
            // Length prefix (4 bytes, big-endian)
            let length = nal.count
            let lengthBytes: [UInt8] = [
                UInt8((length >> 24) & 0xFF),
                UInt8((length >> 16) & 0xFF),
                UInt8((length >> 8) & 0xFF),
                UInt8(length & 0xFF)
            ]
            avccData.append(contentsOf: lengthBytes)
            avccData.append(nal)
        }
        
        guard avccData.count > 0 else { return }
        
        decodeAVCCFrame(avccData, session: session, frameNumber: frameNumber)
    }

    private func decodeAVCCFrame(_ avccData: Data, session: VTDecompressionSession, frameNumber: UInt32) {
        guard avccData.count > 0 else { return }
        
        // Create block buffer
        var blockBuffer: CMBlockBuffer?
        
        let allocateStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avccData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard allocateStatus == kCMBlockBufferNoErr, let block = blockBuffer else {
            return
        }
        
        // Copy data
        avccData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else { return }
            CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }
        
        // Create sample buffer
        guard let formatDesc = formatDescription else {
            return
        }
        
        var sampleBuffer: CMSampleBuffer?
        var sampleSizeArray = [avccData.count]
        
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )
        
        guard createStatus == noErr, let sample = sampleBuffer else {
            return
        }
                
        // Decode en synchrone
        var flagsOut = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [],  // Mode synchrone
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
        
        if decodeStatus != noErr {
            // print("❌ Decode error: \(decodeStatus)")
        } else {
            // print("✅ Frame decoded successfully")
        }
        
        // Force le traitement immédiat
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }
    
    private func parseNALUnits(from data: Data) -> [Data] {
        var nalUnits: [Data] = []
        var offset = 0
        
        while offset < data.count - 4 {
            // Chercher start code (0x00000001 ou 0x000001)
            if data[offset] == 0x00 && data[offset + 1] == 0x00 {
                var startCodeLength = 0
                
                if offset + 3 < data.count && data[offset + 2] == 0x00 && data[offset + 3] == 0x01 {
                    startCodeLength = 4
                } else if offset + 2 < data.count && data[offset + 2] == 0x01 {
                    startCodeLength = 3
                }
                
                if startCodeLength > 0 {
                    let nalStart = offset + startCodeLength
                    
                    // Trouver le prochain start code
                    var nalEnd = data.count
                    for i in (nalStart + 3)..<data.count - 3 {
                        if data[i] == 0x00 && data[i + 1] == 0x00 &&
                           (data[i + 2] == 0x01 || (i + 3 < data.count && data[i + 2] == 0x00 && data[i + 3] == 0x01)) {
                            nalEnd = i
                            break
                        }
                    }
                    
                    if nalStart < nalEnd && nalEnd <= data.count {
                        let nalUnit = data.subdata(in: nalStart..<nalEnd)
                        nalUnits.append(nalUnit)
                    }
                    
                    offset = nalEnd
                    continue
                }
            }
            
            offset += 1
        }
        
        return nalUnits
    }
    
    private func decodeAnnexBFrame(_ h264Data: Data, session: VTDecompressionSession, frameNumber: UInt32) {
        guard h264Data.count > 4 else { return }
        
        // Convertir Annex-B (start codes) en AVCC (length-prefixed)
        var avccData = Data()
        var offset = 0
        
        while offset < h264Data.count - 4 {
            // Chercher start code
            if h264Data[offset] == 0x00 && h264Data[offset + 1] == 0x00 {
                var startCodeLength = 0
                
                if offset + 3 < h264Data.count && h264Data[offset + 2] == 0x00 && h264Data[offset + 3] == 0x01 {
                    startCodeLength = 4
                } else if offset + 2 < h264Data.count && h264Data[offset + 2] == 0x01 {
                    startCodeLength = 3
                }
                
                if startCodeLength > 0 {
                    let nalStart = offset + startCodeLength
                    
                    // Trouver le prochain start code ou fin
                    var nalEnd = h264Data.count
                    for i in (nalStart + 3)..<h264Data.count - 3 {
                        if h264Data[i] == 0x00 && h264Data[i + 1] == 0x00 &&
                           ((i + 2 < h264Data.count && h264Data[i + 2] == 0x01) ||
                            (i + 3 < h264Data.count && h264Data[i + 2] == 0x00 && h264Data[i + 3] == 0x01)) {
                            nalEnd = i
                            break
                        }
                    }
                    
                    let nalLength = nalEnd - nalStart
                    if nalLength > 0 && nalLength < h264Data.count {
                        // Écrire la longueur sur 4 bytes (big-endian)
                        let lengthBytes: [UInt8] = [
                            UInt8((nalLength >> 24) & 0xFF),
                            UInt8((nalLength >> 16) & 0xFF),
                            UInt8((nalLength >> 8) & 0xFF),
                            UInt8(nalLength & 0xFF)
                        ]
                        avccData.append(contentsOf: lengthBytes)
                        
                        // Ajouter les données NAL
                        if nalStart < nalEnd && nalEnd <= h264Data.count {
                            avccData.append(h264Data[nalStart..<nalEnd])
                        }
                    }
                    
                    offset = nalEnd
                    continue
                }
            }
            
            offset += 1
        }
        
        guard avccData.count > 0 else {
            print("⚠️ No valid AVCC data")
            return
        }
        
        // Create block buffer avec données AVCC
        var blockBuffer: CMBlockBuffer?
        
        let allocateStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avccData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard allocateStatus == kCMBlockBufferNoErr, let block = blockBuffer else {
            return
        }
        
        // Copy data
        avccData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else { return }
            CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }
        
        // Create sample buffer
        guard let formatDesc = formatDescription else {
            return
        }
        
        var sampleBuffer: CMSampleBuffer?
        var sampleSizeArray = [avccData.count]
        
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )
        
        guard createStatus == noErr, let sample = sampleBuffer else {
            return
        }
        
        // Decode
        var flagsOut = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
        
        if decodeStatus != noErr {
        }
    }
}

// MARK: - Decompression Callback

private func decompressionCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr, let buffer = imageBuffer else {
        if status != noErr {
        }
        return
    }
    
    guard let handler = decompressionOutputRefCon else {
        return
    }
    let videoHandler = Unmanaged<VideoStreamHandler>.fromOpaque(handler).takeUnretainedValue()
    
    videoHandler.displayFrame(imageBuffer: buffer, presentationTime: presentationTimeStamp)
}

// MARK: - Frame Display

extension VideoStreamHandler {
    
    fileprivate func displayFrame(imageBuffer: CVImageBuffer, presentationTime: CMTime) {
        guard let displayLayer = displayLayer else {
            return
        }
        
        // Vérifier le statut du layer
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        
        // Create sample buffer for display
        var formatDescription: CMFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard formatStatus == noErr, let formatDesc = formatDescription else {
            return
        }
        
        // Timing avec timestamp réaliste
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: Int64(frameCount), timescale: 30),
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        guard sampleStatus == noErr, let sample = sampleBuffer else {
            return
        }
        
        // Display on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let layer = self.displayLayer else { return }
            
            // Vérifier que le layer est prêt
            if !layer.isReadyForMoreMediaData {
                layer.flush()
            }
            
            // Enqueue la frame
            layer.enqueue(sample)
                        
            // Force l'affichage
            layer.setNeedsDisplay()
            self.videoView?.setNeedsDisplay(self.videoView?.bounds ?? .zero)
        }
    }
}

// MARK: - PaVE Header Parser

struct PaVEHeader {
    let signature: [UInt8]
    let version: UInt8
    let videoCodec: UInt8
    let headerSize: UInt16
    let payloadSize: UInt32
    let encodedStreamWidth: UInt16
    let encodedStreamHeight: UInt16
    let displayWidth: UInt16
    let displayHeight: UInt16
    let frameNumber: UInt32
    let timestamp: UInt32
    let totalChunks: UInt8
    let chunkIndex: UInt8
    let frameType: UInt8
    let control: UInt8
    
    static func parse(from data: Data) -> PaVEHeader? {
        guard data.count >= 68 else { return nil }
        
        func safeRead(_ index: Int) -> UInt8? {
            guard index >= 0, index < data.count else { return nil }
            let dataIndex = data.startIndex.advanced(by: index)
            guard dataIndex < data.endIndex else { return nil }
            return data[dataIndex]
        }
        
        guard let sig0 = safeRead(0), let sig1 = safeRead(1),
              let sig2 = safeRead(2), let sig3 = safeRead(3) else { return nil }
        
        let signature = [sig0, sig1, sig2, sig3]
        guard signature == [0x50, 0x61, 0x56, 0x45] else { return nil }
        
        guard let version = safeRead(4), let videoCodec = safeRead(5),
              let hSize0 = safeRead(6), let hSize1 = safeRead(7) else { return nil }
        
        let headerSize = UInt16(hSize0) | (UInt16(hSize1) << 8)
        
        guard let pSize0 = safeRead(8), let pSize1 = safeRead(9),
              let pSize2 = safeRead(10), let pSize3 = safeRead(11) else { return nil }
        
        let payloadSize = UInt32(pSize0) | (UInt32(pSize1) << 8) |
                         (UInt32(pSize2) << 16) | (UInt32(pSize3) << 24)
        
        guard let esw0 = safeRead(12), let esw1 = safeRead(13),
              let esh0 = safeRead(14), let esh1 = safeRead(15),
              let dw0 = safeRead(16), let dw1 = safeRead(17),
              let dh0 = safeRead(18), let dh1 = safeRead(19) else { return nil }
        
        let encodedStreamWidth = UInt16(esw0) | (UInt16(esw1) << 8)
        let encodedStreamHeight = UInt16(esh0) | (UInt16(esh1) << 8)
        let displayWidth = UInt16(dw0) | (UInt16(dw1) << 8)
        let displayHeight = UInt16(dh0) | (UInt16(dh1) << 8)
        
        guard let fn0 = safeRead(20), let fn1 = safeRead(21),
              let fn2 = safeRead(22), let fn3 = safeRead(23) else { return nil }
        
        let frameNumber = UInt32(fn0) | (UInt32(fn1) << 8) |
                         (UInt32(fn2) << 16) | (UInt32(fn3) << 24)
        
        guard let ts0 = safeRead(24), let ts1 = safeRead(25),
              let ts2 = safeRead(26), let ts3 = safeRead(27) else { return nil }
        
        let timestamp = UInt32(ts0) | (UInt32(ts1) << 8) |
                       (UInt32(ts2) << 16) | (UInt32(ts3) << 24)
        
        guard let totalChunks = safeRead(28), let chunkIndex = safeRead(29),
              let frameType = safeRead(30), let control = safeRead(31) else { return nil }
        
        return PaVEHeader(
            signature: signature, version: version, videoCodec: videoCodec,
            headerSize: headerSize, payloadSize: payloadSize,
            encodedStreamWidth: encodedStreamWidth, encodedStreamHeight: encodedStreamHeight,
            displayWidth: displayWidth, displayHeight: displayHeight,
            frameNumber: frameNumber, timestamp: timestamp,
            totalChunks: totalChunks, chunkIndex: chunkIndex,
            frameType: frameType, control: control
        )
    }
}
