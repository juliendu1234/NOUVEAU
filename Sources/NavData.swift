import Foundation

/// Complete AR.Drone 2.0 navigation data structure
struct NavData {
    // Control State (32-bit flags)
    var controlState: UInt32 = 0
    
    // Battery level (0-100%)
    var batteryPercentage: Int = 0
    
    // Euler angles (degrees)
    var pitch: Float = 0.0      // Theta
    var roll: Float = 0.0       // Phi
    var yaw: Float = 0.0        // Psi
    
    // Altitude (millimeters)
    var altitude: Int32 = 0
    
    // Velocities (mm/s)
    var velocityX: Float = 0.0
    var velocityY: Float = 0.0
    var velocityZ: Float = 0.0
    
    // Angular velocities (degrees/s)
    var angularVelocityX: Float = 0.0
    var angularVelocityY: Float = 0.0
    var angularVelocityZ: Float = 0.0
    
    // Motor PWM values (0-255)
    var motor1: UInt8 = 0
    var motor2: UInt8 = 0
    var motor3: UInt8 = 0
    var motor4: UInt8 = 0
    
    // GPS data
    var gpsLatitude: Double = 0.0
    var gpsLongitude: Double = 0.0
    var gpsAltitude: Double = 0.0
    var gpsNumSatellites: Int = 0
    
    // Vision detection
    var numTrackedTargets: Int = 0
    var detectedTags: [Int] = []
    
    // Timestamps
    var timestamp: UInt32 = 0
    var sequenceNumber: UInt32 = 0
    
    // Flight state flags
    var isFlying: Bool { controlState & (1 << 0) != 0 }
    var isVideoEnabled: Bool { controlState & (1 << 1) != 0 }
    var isVisionEnabled: Bool { controlState & (1 << 2) != 0 }
    var isControlAlgorithmChanged: Bool { controlState & (1 << 3) != 0 }
    var isAltitudeControlActive: Bool { controlState & (1 << 4) != 0 }
    var isUserFeedbackOn: Bool { controlState & (1 << 5) != 0 }
    var isControlReceived: Bool { controlState & (1 << 6) != 0 }
    var isTrimReceived: Bool { controlState & (1 << 7) != 0 }
    var isTrimRunning: Bool { controlState & (1 << 8) != 0 }
    var isTrimSucceeded: Bool { controlState & (1 << 9) != 0 }
    var isNavDataDemoOnly: Bool { controlState & (1 << 10) != 0 }
    var isNavDataBootstrap: Bool { controlState & (1 << 11) != 0 }
    var isMotorsDown: Bool { controlState & (1 << 12) != 0 }
    var isGyrometersDown: Bool { controlState & (1 << 13) != 0 }
    var isBatteryLow: Bool { controlState & (1 << 14) != 0 }
    var isBatteryHigh: Bool { controlState & (1 << 15) != 0 }
    var isTimerElapsed: Bool { controlState & (1 << 16) != 0 }
    var isNotEnoughPower: Bool { controlState & (1 << 17) != 0 }
    var isAngelsOutOfRange: Bool { controlState & (1 << 18) != 0 }
    var isTooMuchWind: Bool { controlState & (1 << 19) != 0 }
    var isUltrasonicSensorDeaf: Bool { controlState & (1 << 20) != 0 }
    var isCutoutDetected: Bool { controlState & (1 << 21) != 0 }
    var isPicVersionNumberOK: Bool { controlState & (1 << 22) != 0 }
    var isATCodecThreadOn: Bool { controlState & (1 << 23) != 0 }
    var isNavDataThreadOn: Bool { controlState & (1 << 24) != 0 }
    var isVideoThreadOn: Bool { controlState & (1 << 25) != 0 }
    var isAcquisitionThreadOn: Bool { controlState & (1 << 26) != 0 }
    var isControlWatchdogDelayed: Bool { controlState & (1 << 27) != 0 }
    var isADCWatchdogDelayed: Bool { controlState & (1 << 28) != 0 }
    var isCommunicationProblemOccurred: Bool { controlState & (1 << 29) != 0 }
    var isEmergency: Bool { controlState & (1 << 30) != 0 }
    
    // Wind estimation
    var windSpeed: Float = 0.0
    var windAngle: Float = 0.0
    var windCompensationPhi: Float = 0.0
    var windCompensationTheta: Float = 0.0
    
    // Computed values
    var groundSpeed: Float {
        return sqrt(velocityX * velocityX + velocityY * velocityY)
    }
    
    var altitudeMeters: Float {
        return Float(altitude) / 1000.0
    }
    
    var isHealthy: Bool {
        return !isEmergency &&
               !isBatteryLow &&
               !isMotorsDown &&
               !isGyrometersDown &&
               !isCutoutDetected &&
               !isNotEnoughPower &&
               !isUltrasonicSensorDeaf &&
               !isCommunicationProblemOccurred
    }
}

/// NavData option tags (for parsing)
enum NavDataTag: UInt16 {
    case demo = 0
    case time = 1
    case rawMeasures = 2
    case physMeasures = 3
    case gyrosOffsets = 4
    case eulerAngles = 5
    case references = 6
    case trims = 7
    case rcReferences = 8
    case pwm = 9
    case altitude = 10
    case visionRaw = 11
    case visionOf = 12
    case vision = 13
    case visionPerf = 14
    case trackersSend = 15
    case visionDetect = 16
    case watchdog = 17
    case adcDataFrame = 18
    case videoStream = 19
    case games = 20
    case pressureRaw = 21
    case magneto = 22
    case windSpeed = 23
    case kalmanPressure = 24
    case hdVideoStream = 25
    case wifi = 26
    case gps = 27
    case cks = 0xFFFF
}

/// NavData parser
class NavDataParser {
    
    func parse(_ data: Data) -> NavData? {
        guard data.count >= 16 else { return nil }
        
        var navData = NavData()
        var offset = 0
        
        // Header (4 bytes)
        let header = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        
        guard header == 0x88776655 || header == 0x55667788 else {
            return nil
        }
        
        // State (4 bytes)
        navData.controlState = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        
        // Sequence number (4 bytes)
        navData.sequenceNumber = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        
        // Vision flag (4 bytes)
        offset += 4
        
        // Parse options
        while offset + 4 <= data.count {
            guard offset + 2 <= data.count else { break }
            let tag = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
            offset += 2
            
            guard offset + 2 <= data.count else { break }
            let size = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
            offset += 2
            
            // CKS = fin
            if tag == 0xFFFF {
                break
            }
            
            guard size >= 4 && offset + Int(size) - 4 <= data.count else { break }
            
            let optionData = data.subdata(in: offset..<(offset + Int(size) - 4))
            
            if let optionTag = NavDataTag(rawValue: tag) {
                parseOption(optionTag, data: optionData, navData: &navData)
            }
            
            offset += Int(size) - 4
        }
        
        return navData
    }
    
    private func parseOption(_ tag: NavDataTag, data: Data, navData: inout NavData) {
        switch tag {
        case .demo:
            parseDemoOption(data, navData: &navData)
        case .time:
            parseTimeOption(data, navData: &navData)
        case .pwm:
            parsePWMOption(data, navData: &navData)
        case .altitude:
            parseAltitudeOption(data, navData: &navData)
        case .windSpeed:
            parseWindOption(data, navData: &navData)
        default:
            break
        }
    }
    
    private func parseDemoOption(_ data: Data, navData: inout NavData) {
        guard data.count >= 64 else { return }
        
        var offset = 0
        
        // Control state (déjà parsé)
        offset += 4
        
        // Battery percentage
        navData.batteryPercentage = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) })
        offset += 4
        
        // Theta (pitch) - en millidegrés
        navData.pitch = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) } / 1000.0
        offset += 4
        
        // Phi (roll) - en millidegrés
        navData.roll = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) } / 1000.0
        offset += 4
        
        // Psi (yaw) - en millidegrés
        navData.yaw = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) } / 1000.0
        offset += 4
        
        // Altitude - en millimètres
        navData.altitude = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
        offset += 4
        
        // Velocities - en mm/s
        navData.velocityX = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
        offset += 4
        navData.velocityY = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
        offset += 4
        navData.velocityZ = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
        offset += 4
    }
    
    private func parseTimeOption(_ data: Data, navData: inout NavData) {
        guard data.count >= 4 else { return }
        navData.timestamp = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }
    
    private func parsePWMOption(_ data: Data, navData: inout NavData) {
        guard data.count >= 16 else { return }
        
        // AR.Drone SDK: PWM values are stored as 4 consecutive UInt8 values
        // Each motor PWM is a single byte (0-255) representing motor speed
        // SDK Reference: NavData Option PWM (tag 9) - Chapter 6.6.3
        navData.motor1 = data[0]
        navData.motor2 = data[1]
        navData.motor3 = data[2]
        navData.motor4 = data[3]
    }
    
    private func parseAltitudeOption(_ data: Data, navData: inout NavData) {
        guard data.count >= 4 else { return }
        navData.altitude = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    }
    
    private func parseWindOption(_ data: Data, navData: inout NavData) {
        guard data.count >= 12 else { return }
        
        navData.windSpeed = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Float.self) }
        navData.windAngle = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Float.self) }
        navData.windCompensationTheta = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: Float.self) }
    }
}
