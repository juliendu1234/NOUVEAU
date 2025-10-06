//
//  GamepadManager 2.swift
//  ARDroneController
//
//  Created by Julien Favre on 03/10/2025.
//


import Foundation
import GameController
import IOKit.hid

/// Manages DualShock 4 controller input with global background monitoring
class GamepadManager {
    
    private let droneController: ARDroneController
    private var currentController: GCController?
    private var isFlying = false
    
    private let deadzone: Float = 0.10
    
    // Controller health monitoring
    private var lastControllerCheckTime: Date?
    private var controllerCheckTimer: Timer?
    
    // NOUVEAU : IOHIDManager pour monitoring global
    private var hidManager: IOHIDManager?
    private var isGlobalMonitoringActive = false
    private var wasInBackground = false
    
    init(droneController: ARDroneController) {
        self.droneController = droneController
    }
    
    // MARK: - Controller Monitoring
    
    func startMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected),
            name: .GCControllerDidConnect,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        
        // Écouter les changements de focus app
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        GCController.startWirelessControllerDiscovery {
                    }
        
        if let controller = GCController.controllers().first {
            setupController(controller)
        }
        
        startControllerHealthCheck()
        setupGlobalHIDMonitoring()
    }
    
    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self)
        GCController.stopWirelessControllerDiscovery()
        controllerCheckTimer?.invalidate()
        controllerCheckTimer = nil
        currentController = nil
        
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        isGlobalMonitoringActive = false
    }
    
    // MARK: - Background Monitoring
    
    @objc private func appDidResignActive() {
                wasInBackground = true
        
        // Si le drone vole, forcer hover pour sécurité
        if isFlying {
                        droneController.hover()
        }
    }
    
    @objc private func appDidBecomeActive() {
        if wasInBackground {
                        wasInBackground = false
        }
    }
    
    // MARK: - Global HID Monitoring (fonctionne en arrière-plan)
    
    private func setupGlobalHIDMonitoring() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
                        return
        }
        
        // Filtrer uniquement les gamepads (DualShock 4)
        let deviceMatch: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick
            ]
        ]
        
        IOHIDManagerSetDeviceMatchingMultiple(manager, deviceMatch as CFArray)
        
        // Callback pour les événements
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let gamepadManager = Unmanaged<GamepadManager>.fromOpaque(context).takeUnretainedValue()
            gamepadManager.handleHIDInput(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        
        // Ouvrir en mode global
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        if openResult == kIOReturnSuccess {
                        isGlobalMonitoringActive = true
        } else {
                    }
    }
    
    private func handleHIDInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)
        
        // Si on est en arrière-plan et qu'on reçoit un input critique
        if wasInBackground {
            // Vérifier si c'est un bouton d'urgence (Triangle = usage 4 sur DualShock 4)
            if usage == 4 && integerValue == 1 {
                                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    self.droneController.emergency()
                }
            }
            
            // Vérifier si c'est le bouton Land (Square = usage 1)
            if usage == 1 && integerValue == 1 {
                                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    self.droneController.land()
                }
            }
        }
    }
    
    // MARK: - Controller Health Check
    
    private func startControllerHealthCheck() {
        controllerCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkControllerHealth()
        }
    }
    
    private func checkControllerHealth() {
        if GCController.controllers().isEmpty && currentController != nil {
            handleUnexpectedDisconnection()
        }
    }
    
    private func handleUnexpectedDisconnection() {
        print("⚠️ Controller disconnected!")
        currentController = nil
        
        // SDK-compliant failsafe: If flying when controller disconnects, hover and alert
        if isFlying {
            print("🚨 FAILSAFE: Controller lost during flight - initiating hover")
            droneController.hover()
            
            // Alert user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Manette Déconnectée"
                alert.informativeText = "La manette a été déconnectée pendant le vol. Le drone est en mode hover. Reconnectez la manette ou atterrissez manuellement."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    // MARK: - Controller Events
    
    @objc private func controllerConnected(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
                setupController(controller)
    }
    
    @objc private func controllerDisconnected(_ notification: Notification) {
        guard notification.object is GCController else { return }
                handleUnexpectedDisconnection()
    }
    
    // MARK: - Controller Setup
    
    private func setupController(_ controller: GCController) {
        currentController = controller
        
        guard let gamepad = controller.extendedGamepad else {
                        return
        }
        
        // ✕ (Cross/A) - DÉCOLLAGE
        gamepad.buttonA.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                self?.handleTakeoff()
            }
        }
        
        // □ (Square/X) - ATTERRISSAGE
        gamepad.buttonX.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                self?.handleLand()
            }
        }
        
        // △ (Triangle/Y) - ARRÊT D'URGENCE
        gamepad.buttonY.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                self?.handleEmergency()
            }
        }
        
        // ○ (Circle/B) - RESET URGENCE
        gamepad.buttonB.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                self?.handleResetEmergency()
            }
        }
        
        // SHARE - MODE HOVER
        if let shareButton = gamepad.buttonOptions {
            shareButton.pressedChangedHandler = { [weak self] (button, value, pressed) in
                if pressed {
                    self?.handleHover()
                }
            }
        }
        
        // OPTIONS - QUITTER (disconnect)
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                self?.droneController.disconnect()
                            }
        }
        
        // D-PAD UP - CAMÉRA AVANT
        gamepad.dpad.up.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                self?.droneController.switchVideoChannel(.hori)
            }
        }
        
        // D-PAD DOWN - CAMÉRA BAS
        gamepad.dpad.down.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                self?.droneController.switchVideoChannel(.vert)
            }
        }
        
        // D-PAD LEFT - ENREGISTRER VIDÉO
        gamepad.dpad.left.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                if self?.droneController.videoHandler.isRecording == true {
                    self?.droneController.stopVideoRecording()
                } else {
                    self?.droneController.startVideoRecording()
                }
            }
        }
        
        // D-PAD RIGHT - PRENDRE PHOTO
        gamepad.dpad.right.pressedChangedHandler = { [weak self] (button, value, pressed) in
            if pressed {
                _ = self?.droneController.capturePhoto()
            }
        }
        
        // STICKS ANALOGIQUES
        gamepad.valueChangedHandler = { [weak self] (_: GCExtendedGamepad, element: GCControllerElement) in
            // Only process stick movements, ignore button presses to avoid false commands
            if element == gamepad.leftThumbstick.xAxis || 
               element == gamepad.leftThumbstick.yAxis ||
               element == gamepad.rightThumbstick.xAxis || 
               element == gamepad.rightThumbstick.yAxis {
                self?.handleControllerInput(gamepad)
            }
        }
        
            }
    
    // MARK: - Input Handling
    
    private func handleControllerInput(_ gamepad: GCExtendedGamepad) {
        let yaw = applyDeadzone(gamepad.leftThumbstick.xAxis.value)
        let gaz = applyDeadzone(gamepad.leftThumbstick.yAxis.value)
        let roll = applyDeadzone(gamepad.rightThumbstick.xAxis.value)
        let pitch = -applyDeadzone(gamepad.rightThumbstick.yAxis.value)
        
        droneController.setMovement(
            roll: roll,
            pitch: pitch,
            yaw: yaw,
            gaz: gaz
        )
    }
    
    // MARK: - Action Handlers
    
    private func handleTakeoff() {
        guard !isFlying else { return }
                droneController.takeoff()
        isFlying = true
    }
    
    private func handleLand() {
        guard isFlying else { return }
                droneController.land()
        isFlying = false
    }
    
    private func handleEmergency() {
                droneController.emergency()
        isFlying = false
    }
    
    private func handleResetEmergency() {
                droneController.resetEmergency()
    }
    
    private func handleHover() {
        guard isFlying else { return }
                droneController.hover()
    }

    // MARK: - Helper Functions
    
    private func applyDeadzone(_ value: Float) -> Float {
        if abs(value) < deadzone {
            return 0.0
        }
        
        let sign = value < 0 ? -1.0 : 1.0
        let scaledValue = (abs(value) - deadzone) / (1.0 - deadzone)
        return Float(sign) * scaledValue
    }
}
