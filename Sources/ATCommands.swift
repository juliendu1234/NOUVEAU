import Foundation

/// Complete AT Command set for AR.Drone 2.0
/// Implements all 32-bit control flags and advanced commands
class ATCommands {
    
    // MARK: - Control State Flags (32-bit)
    
    /// Basic control flags
    struct ControlFlags {
        static let defaultMask: UInt32 = (1 << 18) | (1 << 20) | (1 << 22) | (1 << 24) | (1 << 28)
        static let takeoff: UInt32 = (1 << 9) | defaultMask
        static let land: UInt32 = defaultMask
        static let emergency: UInt32 = (1 << 8) | defaultMask
    }
    
    // Bit definitions for REF command
    enum ControlBit: Int {
        case input = 0           // Bit 0: Input control
        case video = 1           // Bit 1: Video enable
        case vision = 2          // Bit 2: Vision enable
        case control = 3         // Bit 3: Control algorithm changed
        case altitude = 4        // Bit 4: Altitude control active
        case userFeedback = 5    // Bit 5: User feedback start
        case startButton = 6     // Bit 6: Control received
        case trim = 7            // Bit 7: Trim command
        case emergencyReset = 8  // Bit 8: Emergency mode
        case takeoff = 9         // Bit 9: Takeoff
        case outdoor = 18        // Bit 18: Outdoor mode
        case shell = 20          // Bit 20: Hull protection
        case autonomous = 22     // Bit 22: Autonomous flight
        case manual = 24         // Bit 24: Manual control
        case indoor = 28         // Bit 28: Indoor mode
    }
    
    // MARK: - Configuration Categories
    
    enum ConfigCategory: String {
        case general = "general"
        case control = "control"
        case network = "network"
        case pic = "pic"
        case video = "video"
        case leds = "leds"
        case detect = "detect"
        case syslog = "syslog"
        case userbox = "userbox"
        case custom = "custom"
    }
    
    // MARK: - Video Configuration
    
    enum VideoCodec: Int {
        case vlib = 0x40     // VLIB codec
        case p264 = 0x80     // P264 codec
        case mp4_360p = 0x81 // MP4 360p
        case h264_360p = 0x82 // H264 360p
        case mp4_720p = 0x83 // MP4 720p
        case h264_720p = 0x84 // H264 720p
        case h264_auto = 0x85 // H264 auto
        case h264_360p_slrs = 0x86 // H264 360p SLRS
        case h264_720p_slrs = 0x87 // H264 720p SLRS
        case h264_auto_slrs = 0x88 // H264 auto SLRS
    }
    
    enum VideoChannel: Int {
        case hori = 0  // Horizontal camera
        case vert = 1  // Vertical camera
        case large = 2 // Large view
        case small = 3 // Small view
    }
    
    // MARK: - LED Animation
    
    enum LEDAnimation: Int {
        case blinkGreenRed = 0
        case blinkGreen = 1
        case blinkRed = 2
        case blinkOrange = 3
        case snakeGreenRed = 4
        case fire = 5
        case standard = 6
        case red = 7
        case green = 8
        case redSnake = 9
        case blank = 10
        case rightMissile = 11
        case leftMissile = 12
        case doubleMissile = 13
        case frontLeftGreenOthersRed = 14
        case frontRightGreenOthersRed = 15
        case rearRightGreenOthersRed = 16
        case rearLeftGreenOthersRed = 17
        case leftGreenRightRed = 18
        case leftRedRightGreen = 19
        case blinkStandard = 20
    }
    
    // MARK: - Flight Animation
    
    enum FlightAnimation: Int {
        case phiM30Deg = 0
        case phi30Deg = 1
        case thetaM30Deg = 2
        case theta30Deg = 3
        case theta20DegYaw200Deg = 4
        case theta20DegYawM200Deg = 5
        case turnaround = 6
        case turnaroundGodown = 7
        case yawShake = 8
        case yawDance = 9
        case phiDance = 10
        case thetaDance = 11
        case vzDance = 12
        case wave = 13
        case phiThetaMixed = 14
        case doublePhiThetaMixed = 15
        case flipAhead = 16
        case flipBehind = 17
        case flipLeft = 18
        case flipRight = 19
    }
    
    // MARK: - Command Generation
    
    private var sequenceNumber: Int32 = 1
    
    func getNextSequence() -> Int32 {
        let current = sequenceNumber
        sequenceNumber += 1
        return current
    }
    
    /// REF command - Basic control (takeoff, land, emergency)
    func ref(_ mode: UInt32) -> String {
        return "AT*REF=\(getNextSequence()),\(mode)\r"
    }
    
    /// PCMD command - Progressive control (movement)
    func pcmd(enable: Bool, roll: Float, pitch: Float, gaz: Float, yaw: Float) -> String {
        let flag = enable ? 1 : 0
        let rollInt = floatToInt(roll)
        let pitchInt = floatToInt(pitch)
        let gazInt = floatToInt(gaz)
        let yawInt = floatToInt(yaw)
        return "AT*PCMD=\(getNextSequence()),\(flag),\(rollInt),\(pitchInt),\(gazInt),\(yawInt)\r"
    }
    
    /// PCMD_MAG command - Movement with magnetometer
    func pcmdMag(enable: Bool, roll: Float, pitch: Float, gaz: Float, yaw: Float, psi: Float, psiAccuracy: Float) -> String {
        let flag = enable ? 1 : 0
        let rollInt = floatToInt(roll)
        let pitchInt = floatToInt(pitch)
        let gazInt = floatToInt(gaz)
        let yawInt = floatToInt(yaw)
        let psiInt = floatToInt(psi)
        let psiAccInt = floatToInt(psiAccuracy)
        return "AT*PCMD_MAG=\(getNextSequence()),\(flag),\(rollInt),\(pitchInt),\(gazInt),\(yawInt),\(psiInt),\(psiAccInt)\r"
    }
    
    /// FTRIM command - Flat trim calibration
    func ftrim() -> String {
        return "AT*FTRIM=\(getNextSequence())\r"
    }
    
    /// CONFIG command - Set configuration parameter
    func config(key: String, value: String) -> String {
        return "AT*CONFIG=\(getNextSequence()),\"\(key)\",\"\(value)\"\r"
    }
    
    /// CONFIG_IDS command - Configuration ID
    func configIds(sessionId: String, userId: String, applicationId: String) -> String {
        return "AT*CONFIG_IDS=\(getNextSequence()),\"\(sessionId)\",\"\(userId)\",\"\(applicationId)\"\r"
    }
    
    /// COMWDG command - Communication watchdog
    func comwdg() -> String {
        return "AT*COMWDG=\(getNextSequence())\r"
    }
    
    /// CALIB command - Magnetometer calibration
    func calib(deviceNumber: Int) -> String {
        return "AT*CALIB=\(getNextSequence()),\(deviceNumber)\r"
    }
    
    /// LED command - LED animation
    func led(animation: LEDAnimation, frequency: Float, duration: Int) -> String {
        let freqInt = floatToInt(frequency)
        return "AT*LED=\(getNextSequence()),\(animation.rawValue),\(freqInt),\(duration)\r"
    }
    
    /// ANIM command - Flight animation
    func anim(animation: FlightAnimation, duration: Int) -> String {
        return "AT*ANIM=\(getNextSequence()),\(animation.rawValue),\(duration)\r"
    }
    
    /// CTRL command - Control mode
    func ctrl(mode: Int, miscValue: Int = 0) -> String {
        return "AT*CTRL=\(getNextSequence()),\(mode),\(miscValue)\r"
    }
    
    // MARK: - Configuration Helpers
    
    /// Set video codec
    func setVideoCodec(_ codec: VideoCodec) -> String {
        return config(key: "video:video_codec", value: String(codec.rawValue))
    }
    
    /// Set video channel
    func setVideoChannel(_ channel: VideoChannel) -> String {
        return config(key: "video:video_channel", value: String(channel.rawValue))
    }
    
    /// Set hull protection
    func setHullProtection(_ enabled: Bool) -> String {
        return config(key: "control:flight_without_shell", value: enabled ? "FALSE" : "TRUE")
    }
    
    /// Set video recording
    func setVideoRecording(_ enabled: Bool) -> String {
        return config(key: "video:video_on_usb", value: enabled ? "TRUE" : "FALSE")
    }
    
    /// Set bitrate control mode
    func setBitrateControl(_ mode: Int) -> String {
        return config(key: "video:bitrate_ctrl_mode", value: String(mode))
    }
    
    /// Set video bitrate
    func setVideoBitrate(_ bitrate: Int) -> String {
        return config(key: "video:bitrate", value: String(bitrate))
    }
    
    /// Set FPS
    func setFPS(_ fps: Int) -> String {
        return config(key: "video:codec_fps", value: String(fps))
    }
    
    /// Set SSID (single mode)
    func setSSID(_ ssid: String) -> String {
        return config(key: "network:ssid_single_player", value: ssid)
    }
    
    /// Set network mode
    func setNetworkMode(_ mode: Int) -> String {
        return config(key: "network:wifi_mode", value: String(mode))
    }
    
    // MARK: - Helper Functions
    
    private func floatToInt(_ value: Float) -> Int32 {
        return Int32(bitPattern: value.bitPattern)
    }
    
    /// Build custom control flags
    func buildControlFlags(bits: [ControlBit]) -> UInt32 {
        var flags: UInt32 = ControlFlags.defaultMask
        for bit in bits {
            flags |= (1 << bit.rawValue)
        }
        return flags
    }
}
