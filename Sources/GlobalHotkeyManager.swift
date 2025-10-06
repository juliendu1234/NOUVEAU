import Cocoa
import Carbon

/// Global hotkey manager for emergency drone control
/// Works even when app is in background
class GlobalHotkeyManager {
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private weak var droneController: ARDroneController?
    
    init(droneController: ARDroneController) {
        self.droneController = droneController
        setupGlobalHotkeys()
    }
    
    private func setupGlobalHotkeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        // Create context pointer
        let context = UnsafeMutablePointer<ARDroneController>.allocate(capacity: 1)
        context.initialize(to: droneController!)
        
        // Install event handler
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let controller = userData.assumingMemoryBound(to: ARDroneController.self).pointee
                
                // Get hotkey ID
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                switch hotKeyID.id {
                case 1: // Emergency Stop
                    print("🚨 GLOBAL EMERGENCY HOTKEY (Cmd+Shift+E)")
                    controller.emergency()
                    
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        
                        let alert = NSAlert()
                        alert.messageText = "🚨 ARRÊT D'URGENCE ACTIVÉ"
                        alert.informativeText = "Le drone va atterrir immédiatement.\nAppuyez sur Cmd+Shift+R pour réinitialiser."
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    
                case 2: // Reset Emergency
                    print("🔄 GLOBAL RESET HOTKEY (Cmd+Shift+R)")
                    controller.resetEmergency()
                    
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        
                        let alert = NSAlert()
                        alert.messageText = "✅ Urgence réinitialisée"
                        alert.informativeText = "Le drone peut redécoller."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    
                case 3: // Land
                    print("🛬 GLOBAL LAND HOTKEY (Cmd+Shift+L)")
                    controller.land()
                    
                default:
                    break
                }
                
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )
        
        // Register Cmd+Shift+E (Emergency)
        let emergencyID = EventHotKeyID(signature: OSType(0x45535450), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            UInt32(cmdKey | shiftKey),
            emergencyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        print("✅ Global hotkey: Cmd+Shift+E = Emergency Stop")
        
        // Register Cmd+Shift+R (Reset)
        let resetID = EventHotKeyID(signature: OSType(0x52535450), id: 2)
        var resetRef: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(cmdKey | shiftKey),
            resetID,
            GetApplicationEventTarget(),
            0,
            &resetRef
        )
        print("✅ Global hotkey: Cmd+Shift+R = Reset Emergency")
        
        // Register Cmd+Shift+L (Land)
        let landID = EventHotKeyID(signature: OSType(0x4C4E4450), id: 3)
        var landRef: EventHotKeyRef?
        RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            UInt32(cmdKey | shiftKey),
            landID,
            GetApplicationEventTarget(),
            0,
            &landRef
        )
        print("✅ Global hotkey: Cmd+Shift+L = Land")
    }
    
    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }
}
