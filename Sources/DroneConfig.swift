import Foundation

// MARK: - Configuration Structures (de l'ancien code)

struct DroneControls {
    static let takeoff = "X"
    static let land = "SQUARE"
    static let emergency = "TRIANGLE"
    static let resetEmergency = "CIRCLE"
    static let quit = "OPTIONS"
    static let hoverMode = "SHARE"
    static let availableL1 = "L1"
    static let availableR1 = "R1"
    static let availableL2 = "L2"
    static let availableR2 = "R2"
    static let cameraFront = "DPAD_UP"
    static let cameraBottom = "DPAD_DOWN"
    static let recordVideo = "DPAD_LEFT"
    static let takePhoto = "DPAD_RIGHT"
}

struct StickConfig {
    static let altitude = "LEFT_Y"
    static let yaw = "LEFT_X"
    static let pitch = "RIGHT_Y"
    static let roll = "RIGHT_X"
}

struct HoverConfig {
    static let autoHoverEnabled = true
    static let inputTimeout: TimeInterval = 0.5
    static let hoverForceDelay: TimeInterval = 1.0
    static let disableAutoStabilization = true
}

struct DroneConfig {
    static let ip = "192.168.1.1"
    static let atPort: UInt16 = 5556
    static let navdataPort: UInt16 = 5554
    static let videoPort: UInt16 = 5555
    static let connectionTimeout: TimeInterval = 3.0
    static let reconnectInterval: TimeInterval = 5.0
}

// MARK: - ARDrone States

enum DroneState {
    case disconnected
    case connecting
    case connected
    case takingOff
    case flying
    case landing
    case emergency
    case hovering
}

enum DroneFlightMode {
    case manual
    case hover
}

struct DroneStatus {
    var state: DroneState = .disconnected
    var flightMode: DroneFlightMode = .manual
    var batteryLevel: Float = 0
    var altitude: Float = 0
    var isEmergency: Bool = false
}

struct FlightInputs {
    var pitch: Float = 0
    var roll: Float = 0
    var yaw: Float = 0
    var gaz: Float = 0
    var lastInputTime: Date = Date()
}
