import Cocoa
import AVFoundation
import GameController
import CoreLocation

class AppDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    
    private let droneController = ARDroneController()
    private var gamepadManager: GamepadManager?
    private var splashWindow: SplashWindowController?
    private var statusWindow: StatusWindowController?
    private var hotkeyManager: GlobalHotkeyManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚁 ARDrone Controller - Starting")
        print("👤 User: QuadLife")
        print("📅 \(Date())")
                
        // Setup gamepad manager
        gamepadManager = GamepadManager(droneController: droneController)
        gamepadManager?.startMonitoring()
        
        // Setup global hotkeys
        hotkeyManager = GlobalHotkeyManager(droneController: droneController)
        print("✅ Global hotkeys active:")
        print("   - Cmd+Shift+E = Emergency Stop")
        print("   - Cmd+Shift+R = Reset Emergency")
        print("   - Cmd+Shift+L = Land")
        
        // Show splash screen
        splashWindow = SplashWindowController()
        splashWindow?.window?.makeKeyAndOrderFront(nil)
        
        splashWindow?.onComplete = { [weak self] in
            self?.showMainWindow()
        }
    }
    
    private func showMainWindow() {
        splashWindow?.close()
        splashWindow = nil
        
        statusWindow = StatusWindowController(droneController: droneController)
        statusWindow?.window?.makeKeyAndOrderFront(nil)
        
        // EMPÊCHER LA PERTE DE FOCUS
        statusWindow?.window?.level = .floating  // Toujours au-dessus
        statusWindow?.window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        
        // Intercepter les tentatives de désactivation
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            
            // Si une autre app essaie de prendre le focus (ex: FaceTime)
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                print("⚠️ Another app tried to take focus: \(app.localizedName ?? "Unknown")")
                
                // Si le drone vole, garder le focus
                if self?.droneController.isFlying() == true {
                    print("🚁 Drone is flying - Keeping focus")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        
        statusWindow?.enterFullScreen()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 Application terminating - Landing drone")
        
        // Atterrir si en vol
        if droneController.isFlying() {
            droneController.land()
            Thread.sleep(forTimeInterval: 2.0)
        }
        
        droneController.disconnect()
        gamepadManager?.stopMonitoring()
    }
    
    private func checkAccessibilityPermissions() {
        // Vérifier SANS afficher le prompt système
        let accessEnabled = AXIsProcessTrusted()
        
        if !accessEnabled {
            // Seulement maintenant, afficher le prompt
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let _ = AXIsProcessTrustedWithOptions(options)
            
            // Afficher notre propre alerte APRÈS (pas avant)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "⚠️ Permissions requises"
                alert.informativeText = """
                Cette app nécessite les permissions d'accessibilité pour :
                
                • Contrôler le drone même en arrière-plan
                • Utiliser les raccourcis globaux (Cmd+Shift+E)
                
                ⚙️ L'app a été ajoutée automatiquement.
                Si elle n'apparaît pas, relancez l'app.
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } else {
            print("✅ Accessibility permissions already granted")
        }
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Empêcher la mise en veille pendant l'utilisation
ProcessInfo.processInfo.beginActivity(
    options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
    reason: "Drone control requires continuous operation"
)

print("""
╔═══════════════════════════════════════════════════════════╗
║  ARDrone Parrot 2.0 - DualShock 4 Controller             ║
║  Technic informatique                                     ║
║                                                           ║
║  🎮 Manette : DualShock 4 (Bluetooth/USB)                ║
║  🚁 Drone   : AR.Drone 2.0                               ║
║  📡 Réseau  : Wi-Fi Direct (192.168.1.1)                 ║
║                                                           ║
║  ⌨️  RACCOURCIS GLOBAUX (fonctionnent partout) :         ║
║     Cmd+Shift+E = 🚨 Arrêt d'urgence                     ║
║     Cmd+Shift+R = 🔄 Reset urgence                       ║
║     Cmd+Shift+L = 🛬 Atterrissage                        ║
╚═══════════════════════════════════════════════════════════╝
""")

app.run()
