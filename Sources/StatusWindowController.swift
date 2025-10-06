import Cocoa
import AVFoundation
import GameController
import CoreWLAN

class StatusWindowController: NSWindowController {
    
    private let droneController: ARDroneController
    private var statusTimer: Timer?
    private var wifiTimer: Timer?
    
    private var lastAltitude: Double = 0
    private var lastAltitudeTime: Date?
    
    // UI Elements
    private let scrollView = NSScrollView()
    private let contentContainer = NSView()
    
    private let gamepadVisualizerView = GamepadVisualizerView()
    private let leftStickLabel = NSTextField(labelWithString: "L: X:0.00 Y:0.00")
    private let rightStickLabel = NSTextField(labelWithString: "R: X:0.00 Y:0.00")
    private let videoView = NSView()
    
    // Télémétrie - EN-TÊTE
    private let connectionDot = NSView()
    private let connectionLabel = NSTextField(labelWithString: "Déconnecté")
    private let controllerStatusLabel = NSTextField(labelWithString: "🎮 ---")
    private let ssidTitleLabel = NSTextField(labelWithString: "Wi-Fi:")
    private let ssidField = NSTextField(string: "")
    
    // Télémétrie - Colonne 1 (Batterie & Puissance)
    private let battTitleLabel = NSTextField(labelWithString: "🔋 Batterie:")
    private let battValueLabel = NSTextField(labelWithString: "---%")
    private let voltTitleLabel = NSTextField(labelWithString: "⚡ Voltage:")
    private let voltValueLabel = NSTextField(labelWithString: "---V")
    private let currentTitleLabel = NSTextField(labelWithString: "🔌 Courant:")
    private let currentValueLabel = NSTextField(labelWithString: "---mA")
    private let tempTitleLabel = NSTextField(labelWithString: "🌡️ Temp:")
    private let tempValueLabel = NSTextField(labelWithString: "---°C")
    
    // Télémétrie - Colonne 2 (Position & Altitude)
    private let altTitleLabel = NSTextField(labelWithString: "📏 Altitude:")
    private let altValueLabel = NSTextField(labelWithString: "---m")
    private let vSpeedTitleLabel = NSTextField(labelWithString: "↕️ Vitesse V:")
    private let vSpeedValueLabel = NSTextField(labelWithString: "---m/s")
    private let speedTitleLabel = NSTextField(labelWithString: "➡️ Vitesse H:")
    private let speedValueLabel = NSTextField(labelWithString: "---m/s")
    private let headingTitleLabel = NSTextField(labelWithString: "🧭 Cap:")
    private let headingValueLabel = NSTextField(labelWithString: "---°")
    
    // Télémétrie - Colonne 3 (Attitude)
    private let pitchTitleLabel = NSTextField(labelWithString: "↗️ Pitch:")
    private let pitchValueLabel = NSTextField(labelWithString: "---°")
    private let rollTitleLabel = NSTextField(labelWithString: "↔️ Roll:")
    private let rollValueLabel = NSTextField(labelWithString: "---°")
    private let yawTitleLabel = NSTextField(labelWithString: "↩️ Yaw:")
    private let yawValueLabel = NSTextField(labelWithString: "---°")
    
    // Télémétrie - Colonne 4 (Moteurs)
    private let motor1TitleLabel = NSTextField(labelWithString: "M1:")
    private let motor1ValueLabel = NSTextField(labelWithString: "---")
    private let motor2TitleLabel = NSTextField(labelWithString: "M2:")
    private let motor2ValueLabel = NSTextField(labelWithString: "---")
    
    // Télémétrie - Colonne 5 (État & Moteurs suite)
    private let stateTitleLabel = NSTextField(labelWithString: "🎯 État:")
    private let stateValueLabel = NSTextField(labelWithString: "Idle")
    private let modeTitleLabel = NSTextField(labelWithString: "🚁 Mode:")
    private let modeValueLabel = NSTextField(labelWithString: "---")
    private let motor3TitleLabel = NSTextField(labelWithString: "M3:")
    private let motor3ValueLabel = NSTextField(labelWithString: "---")
    private let motor4TitleLabel = NSTextField(labelWithString: "M4:")
    private let motor4ValueLabel = NSTextField(labelWithString: "---")
    
    // Control sliders
    private let eulerAngleSlider = NSSlider()
    private let eulerAngleLabel = NSTextField(labelWithString: "Max Angle: 14° (48%)")
    private let altitudeMaxSlider = NSSlider()
    private let altitudeMaxLabel = NSTextField(labelWithString: "Max Altitude: 3 m (26%)")
    private let vzMaxSlider = NSSlider()
    private let vzMaxLabel = NSTextField(labelWithString: "Max V Speed: 1.00 m/s (44%)")
    private let yawMaxSlider = NSSlider()
    private let yawMaxLabel = NSTextField(labelWithString: "Max Yaw: 3.0 rad/s (42%)")
    
    private var saveLocationPathField: NSTextField?
    
    private let wifiClient = CWWiFiClient.shared()
    private var lastObservedSSID: String?
    private var flightStartTime: Date?
    init(droneController: ARDroneController) {
        self.droneController = droneController
        
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1680, height: 1050)
        
        let window = NSWindow(
            contentRect: screen,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        window.title = "ARDrone Advanced Controller"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior = [.fullScreenPrimary]
        
        loadPersistedSSID()
        setupUI()
        setupCallbacks()
        startStatusUpdates()
        startWiFiMonitoring()
        
        // Set initial save location from preferences
        if let savedPath = UserDefaults.standard.string(forKey: "SaveLocationPath"),
           let url = URL(string: "file://\(savedPath)") {
            droneController.videoHandler.setSaveLocation(url)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        statusTimer?.invalidate()
        wifiTimer?.invalidate()
    }
    
    func enterFullScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.window?.toggleFullScreen(nil)
        }
    }
    
    private let ssidDefaultsKey = "ARDrone_DroneSSID"
    
    private func loadPersistedSSID() {
        let saved = UserDefaults.standard.string(forKey: ssidDefaultsKey) ?? "ardrone2_v2.4.8"
        ssidField.stringValue = saved
    }
    
    private func persistSSID(_ ssid: String) {
        UserDefaults.standard.set(ssid, forKey: ssidDefaultsKey)
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        
        scrollView.documentView = contentContainer
        contentView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            contentContainer.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentContainer.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentContainer.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.heightAnchor)
        ])
        
        var y: CGFloat = 14  // Reduced from 25 to bring content up
        
        let headerSection = createHeaderSection()
        contentContainer.addSubview(headerSection)
        NSLayoutConstraint.activate([
            headerSection.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: y),
            headerSection.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            headerSection.widthAnchor.constraint(equalToConstant: 1640),
            headerSection.heightAnchor.constraint(equalToConstant: 80)
        ])
        y += 95  // Reduced from 100
        
        let middleSection = createMiddleSection()
        contentContainer.addSubview(middleSection)
        NSLayoutConstraint.activate([
            middleSection.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: y),
            middleSection.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            middleSection.widthAnchor.constraint(equalToConstant: 1640),
            middleSection.heightAnchor.constraint(equalToConstant: 420)
        ])
        y += 435  // Reduced from 445
        
        let bottomSection = createBottomSectionVertical()
        contentContainer.addSubview(bottomSection)
        NSLayoutConstraint.activate([
            bottomSection.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: y),
            bottomSection.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            bottomSection.widthAnchor.constraint(equalToConstant: 1640),
            bottomSection.heightAnchor.constraint(equalToConstant: 420)  // Reduced from 500, will fit better now
        ])
        
        droneController.videoHandler.setupDisplayLayer(in: videoView)
    }
    
    private func createHeaderSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = NSTextField(labelWithString: "Technic informatique")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        
        let subtitleLabel = NSTextField(labelWithString: "ARDrone Parrot 2.0 - DualShock 4 - Swift")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: 20, weight: .light)
        subtitleLabel.textColor = .systemGray
        subtitleLabel.alignment = .center
        subtitleLabel.isBordered = false
        subtitleLabel.backgroundColor = .clear
        
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        
        return container
    }
    
    private func createMiddleSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let gamepadBox = NSView()
        gamepadBox.translatesAutoresizingMaskIntoConstraints = false
        gamepadBox.wantsLayer = true
        gamepadBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor
        gamepadBox.layer?.cornerRadius = 12
        
        gamepadVisualizerView.translatesAutoresizingMaskIntoConstraints = false
        gamepadVisualizerView.wantsLayer = true
        gamepadVisualizerView.layer?.masksToBounds = true
        leftStickLabel.translatesAutoresizingMaskIntoConstraints = false
        leftStickLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        leftStickLabel.textColor = .systemGray
        leftStickLabel.isBordered = false
        leftStickLabel.backgroundColor = .clear
        
        rightStickLabel.translatesAutoresizingMaskIntoConstraints = false
        rightStickLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        rightStickLabel.textColor = .systemGray
        rightStickLabel.isBordered = false
        rightStickLabel.backgroundColor = .clear
        rightStickLabel.alignment = .right
        
        gamepadBox.addSubview(gamepadVisualizerView)
        gamepadBox.addSubview(leftStickLabel)
        gamepadBox.addSubview(rightStickLabel)
        
        let videoBox = NSView()
        videoBox.translatesAutoresizingMaskIntoConstraints = false
        videoBox.wantsLayer = true
        videoBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 1.0).cgColor
        videoBox.layer?.cornerRadius = 12
        
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 1.0).cgColor
        videoBox.addSubview(videoView)
        
        container.addSubview(gamepadBox)
        container.addSubview(videoBox)
        
        NSLayoutConstraint.activate([
            gamepadBox.topAnchor.constraint(equalTo: container.topAnchor),
            gamepadBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gamepadBox.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gamepadBox.widthAnchor.constraint(equalToConstant: 800),
            
            gamepadVisualizerView.topAnchor.constraint(equalTo: gamepadBox.topAnchor, constant: 12),
            gamepadVisualizerView.leadingAnchor.constraint(equalTo: gamepadBox.leadingAnchor, constant: 12),
            gamepadVisualizerView.trailingAnchor.constraint(equalTo: gamepadBox.trailingAnchor, constant: -12),
            gamepadVisualizerView.heightAnchor.constraint(equalToConstant: 350),
            
            leftStickLabel.topAnchor.constraint(equalTo: gamepadVisualizerView.bottomAnchor, constant: 10),
            leftStickLabel.leadingAnchor.constraint(equalTo: gamepadBox.leadingAnchor, constant: 20),
            
            rightStickLabel.topAnchor.constraint(equalTo: gamepadVisualizerView.bottomAnchor, constant: 10),
            rightStickLabel.trailingAnchor.constraint(equalTo: gamepadBox.trailingAnchor, constant: -20),
            
            videoBox.topAnchor.constraint(equalTo: container.topAnchor),
            videoBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            videoBox.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            videoBox.widthAnchor.constraint(equalToConstant: 820),
            
            videoView.topAnchor.constraint(equalTo: videoBox.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: videoBox.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: videoBox.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: videoBox.bottomAnchor)
        ])
        
        return container
    }
    
    private func createBottomSectionVertical() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let telemetryBox = createTelemetrySection()
        let mappingAndSaveBox = createMappingAndSaveSection()
        
        container.addSubview(telemetryBox)
        container.addSubview(mappingAndSaveBox)
        
        NSLayoutConstraint.activate([
            telemetryBox.topAnchor.constraint(equalTo: container.topAnchor),
            telemetryBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            telemetryBox.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            telemetryBox.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.58),
            
            mappingAndSaveBox.topAnchor.constraint(equalTo: container.topAnchor),
            mappingAndSaveBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mappingAndSaveBox.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            mappingAndSaveBox.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.4)
        ])
        
        return container
    }
    
    private func createMappingAndSaveSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let mappingBox = createMappingSection()
        let saveLocationBox = createSaveLocationSection()
        
        container.addSubview(mappingBox)
        container.addSubview(saveLocationBox)
        
        NSLayoutConstraint.activate([
            mappingBox.topAnchor.constraint(equalTo: container.topAnchor),
            mappingBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mappingBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mappingBox.heightAnchor.constraint(equalToConstant: 310),
            
            saveLocationBox.topAnchor.constraint(equalTo: mappingBox.bottomAnchor, constant: 66),
            saveLocationBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            saveLocationBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            saveLocationBox.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    private func createTelemetrySection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor
        container.layer?.cornerRadius = 12
        
        let title = NSTextField(labelWithString: "📊 TÉLÉMÉTRIE TEMPS RÉEL")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        title.textColor = .white
        title.isBordered = false
        title.backgroundColor = .clear
        
        connectionDot.translatesAutoresizingMaskIntoConstraints = false
        connectionDot.wantsLayer = true
        connectionDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        connectionDot.layer?.cornerRadius = 5
        
        connectionLabel.translatesAutoresizingMaskIntoConstraints = false
        connectionLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        connectionLabel.textColor = .systemRed
        connectionLabel.isBordered = false
        connectionLabel.backgroundColor = .clear
        
        controllerStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        controllerStatusLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        controllerStatusLabel.textColor = .systemGray
        controllerStatusLabel.isBordered = false
        controllerStatusLabel.backgroundColor = .clear
        
        ssidTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        ssidTitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        ssidTitleLabel.textColor = .systemGray
        ssidTitleLabel.isBordered = false
        ssidTitleLabel.backgroundColor = .clear
        
        ssidField.translatesAutoresizingMaskIntoConstraints = false
        ssidField.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        ssidField.bezelStyle = .roundedBezel
        ssidField.target = self
        ssidField.action = #selector(ssidFieldChanged(_:))
        
        container.addSubview(title)
        container.addSubview(connectionDot)
        container.addSubview(connectionLabel)
        container.addSubview(controllerStatusLabel)
        container.addSubview(ssidTitleLabel)
        container.addSubview(ssidField)
        
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            
            connectionDot.trailingAnchor.constraint(equalTo: connectionLabel.leadingAnchor, constant: -6),
            connectionDot.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            connectionDot.widthAnchor.constraint(equalToConstant: 10),
            connectionDot.heightAnchor.constraint(equalToConstant: 10),
            
            connectionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            connectionLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            
            controllerStatusLabel.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 30),
            controllerStatusLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            
            ssidTitleLabel.leadingAnchor.constraint(equalTo: controllerStatusLabel.trailingAnchor, constant: 20),
            ssidTitleLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            
            ssidField.leadingAnchor.constraint(equalTo: ssidTitleLabel.trailingAnchor, constant: 6),
            ssidField.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            ssidField.widthAnchor.constraint(equalToConstant: 150)
        ])
        
        let allTitles = [battTitleLabel, voltTitleLabel, currentTitleLabel, tempTitleLabel,
                        altTitleLabel, vSpeedTitleLabel, speedTitleLabel, headingTitleLabel,
                        pitchTitleLabel, rollTitleLabel, yawTitleLabel,
                        motor1TitleLabel, motor2TitleLabel,
                        stateTitleLabel, modeTitleLabel, motor3TitleLabel, motor4TitleLabel]
        
        let allValues = [battValueLabel, voltValueLabel, currentValueLabel, tempValueLabel,
                        altValueLabel, vSpeedValueLabel, speedValueLabel, headingValueLabel,
                        pitchValueLabel, rollValueLabel, yawValueLabel,
                        motor1ValueLabel, motor2ValueLabel,
                        stateValueLabel, modeValueLabel, motor3ValueLabel, motor4ValueLabel]
        
        for label in allTitles + allValues {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isBordered = false
            label.backgroundColor = .clear
            container.addSubview(label)
        }
        
        for label in allTitles {
            label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)  // Increased from 14
            label.textColor = .systemGray
        }
        
        for label in allValues {
            label.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)  // Increased from 15
            label.textColor = .white
        }
        
        let colWidth: CGFloat = 240
        let rowHeight: CGFloat = 38
        let startY: CGFloat = 55
        
        // Column 1: État, Mode, Motors (moved here from column 4)
        layoutColumn(labels: [
            (stateTitleLabel, stateValueLabel),
            (modeTitleLabel, modeValueLabel),
            (motor1TitleLabel, motor1ValueLabel),
            (motor2TitleLabel, motor2ValueLabel),
            (motor3TitleLabel, motor3ValueLabel),
            (motor4TitleLabel, motor4ValueLabel)
        ], in: container, x: 20, y: startY, rowHeight: rowHeight)
        
        // Column 2: Pitch, Roll, Yaw
        layoutColumn(labels: [
            (pitchTitleLabel, pitchValueLabel),
            (rollTitleLabel, rollValueLabel),
            (yawTitleLabel, yawValueLabel)
        ], in: container, x: 20 + colWidth, y: startY, rowHeight: rowHeight)
        
        // Column 3: Altitude, Speeds, Heading
        layoutColumn(labels: [
            (altTitleLabel, altValueLabel),
            (vSpeedTitleLabel, vSpeedValueLabel),
            (speedTitleLabel, speedValueLabel),
            (headingTitleLabel, headingValueLabel)
        ], in: container, x: 20 + colWidth * 2, y: startY, rowHeight: rowHeight)
        
        // Column 4: Battery, Voltage, Current, Temp (motors removed)
        layoutColumn(labels: [
            (battTitleLabel, battValueLabel),
            (voltTitleLabel, voltValueLabel),
            (currentTitleLabel, currentValueLabel),
            (tempTitleLabel, tempValueLabel)
        ], in: container, x: 20 + colWidth * 3, y: startY, rowHeight: rowHeight)
        
        // Add control sliders section - now positioned after M4 (6th row) + 14px gap
        setupControlSliders(in: container, startY: startY + rowHeight * 6 + 14)
        
        return container
    }
    
    private func layoutColumn(labels: [(NSTextField, NSTextField)], in container: NSView, x: CGFloat, y: CGFloat, rowHeight: CGFloat) {
        for (idx, (title, value)) in labels.enumerated() {
            let currentY = y + CGFloat(idx) * rowHeight
            
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: x),
                title.topAnchor.constraint(equalTo: container.topAnchor, constant: currentY),
                
                value.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
                value.centerYAnchor.constraint(equalTo: title.centerYAnchor)
            ])
        }
    }
    
    private func setupControlSliders(in container: NSView, startY: CGFloat) {
        let sectionTitle = NSTextField(labelWithString: "⚙️ PARAMÈTRES DE CONTRÔLE")
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        sectionTitle.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        sectionTitle.textColor = .systemGray
        sectionTitle.isBordered = false
        sectionTitle.backgroundColor = .clear
        container.addSubview(sectionTitle)
        
        // Configure sliders
        eulerAngleSlider.translatesAutoresizingMaskIntoConstraints = false
        eulerAngleSlider.minValue = 0.0
        eulerAngleSlider.maxValue = 0.52  // 30 degrees in radians
        eulerAngleSlider.doubleValue = 0.25
        eulerAngleSlider.target = self
        eulerAngleSlider.action = #selector(eulerAngleChanged(_:))
        
        altitudeMaxSlider.translatesAutoresizingMaskIntoConstraints = false
        altitudeMaxSlider.minValue = 500
        altitudeMaxSlider.maxValue = 10000
        altitudeMaxSlider.doubleValue = 3000
        altitudeMaxSlider.target = self
        altitudeMaxSlider.action = #selector(altitudeMaxChanged(_:))
        
        vzMaxSlider.translatesAutoresizingMaskIntoConstraints = false
        vzMaxSlider.minValue = 200
        vzMaxSlider.maxValue = 2000
        vzMaxSlider.doubleValue = 1000
        vzMaxSlider.target = self
        vzMaxSlider.action = #selector(vzMaxChanged(_:))
        
        yawMaxSlider.translatesAutoresizingMaskIntoConstraints = false
        yawMaxSlider.minValue = 0.7
        yawMaxSlider.maxValue = 6.11
        yawMaxSlider.doubleValue = 3.0
        yawMaxSlider.target = self
        yawMaxSlider.action = #selector(yawMaxChanged(_:))
        
        // Configure labels
        for label in [eulerAngleLabel, altitudeMaxLabel, vzMaxLabel, yawMaxLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            label.isBordered = false
            label.backgroundColor = .clear
        }
        
        // Add to container
        container.addSubview(eulerAngleSlider)
        container.addSubview(eulerAngleLabel)
        container.addSubview(altitudeMaxSlider)
        container.addSubview(altitudeMaxLabel)
        container.addSubview(vzMaxSlider)
        container.addSubview(vzMaxLabel)
        container.addSubview(yawMaxSlider)
        container.addSubview(yawMaxLabel)
        
        // Layout in 2 columns
        let col1X: CGFloat = 20
        let col2X: CGFloat = 480
        let sliderWidth: CGFloat = 200
        let rowHeight: CGFloat = 35
        
        NSLayoutConstraint.activate([
            // Section title
            sectionTitle.topAnchor.constraint(equalTo: container.topAnchor, constant: startY),
            sectionTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: col1X),
            
            // Column 1 - Row 1: Euler Angle
            eulerAngleLabel.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 15),
            eulerAngleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: col1X),
            eulerAngleSlider.centerYAnchor.constraint(equalTo: eulerAngleLabel.centerYAnchor),
            eulerAngleSlider.leadingAnchor.constraint(equalTo: eulerAngleLabel.trailingAnchor, constant: 10),
            eulerAngleSlider.widthAnchor.constraint(equalToConstant: sliderWidth),
            
            // Column 1 - Row 2: VZ Max
            vzMaxLabel.topAnchor.constraint(equalTo: eulerAngleLabel.bottomAnchor, constant: rowHeight),
            vzMaxLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: col1X),
            vzMaxSlider.centerYAnchor.constraint(equalTo: vzMaxLabel.centerYAnchor),
            vzMaxSlider.leadingAnchor.constraint(equalTo: vzMaxLabel.trailingAnchor, constant: 10),
            vzMaxSlider.widthAnchor.constraint(equalToConstant: sliderWidth),
            
            // Column 2 - Row 1: Altitude Max
            altitudeMaxLabel.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 15),
            altitudeMaxLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: col2X),
            altitudeMaxSlider.centerYAnchor.constraint(equalTo: altitudeMaxLabel.centerYAnchor),
            altitudeMaxSlider.leadingAnchor.constraint(equalTo: altitudeMaxLabel.trailingAnchor, constant: 10),
            altitudeMaxSlider.widthAnchor.constraint(equalToConstant: sliderWidth),
            
            // Column 2 - Row 2: Yaw Max
            yawMaxLabel.topAnchor.constraint(equalTo: altitudeMaxLabel.bottomAnchor, constant: rowHeight),
            yawMaxLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: col2X),
            yawMaxSlider.centerYAnchor.constraint(equalTo: yawMaxLabel.centerYAnchor),
            yawMaxSlider.leadingAnchor.constraint(equalTo: yawMaxLabel.trailingAnchor, constant: 10),
            yawMaxSlider.widthAnchor.constraint(equalToConstant: sliderWidth)
        ])
    }
    
    // Slider action handlers
    @objc private func eulerAngleChanged(_ sender: NSSlider) {
        let radians = sender.doubleValue
        let degrees = radians * 180.0 / .pi
        let percentage = Int((sender.doubleValue - sender.minValue) / (sender.maxValue - sender.minValue) * 100)
        eulerAngleLabel.stringValue = String(format: "Max Angle: %.0f° (%d%%)", degrees, percentage)
        droneController.setConfig(key: "control:euler_angle_max", value: String(format: "%.2f", radians))
    }
    
    @objc private func altitudeMaxChanged(_ sender: NSSlider) {
        let millimeters = Int(sender.doubleValue)
        let meters = Double(millimeters) / 1000.0
        let percentage = Int((sender.doubleValue - sender.minValue) / (sender.maxValue - sender.minValue) * 100)
        altitudeMaxLabel.stringValue = String(format: "Max Altitude: %.1f m (%d%%)", meters, percentage)
        droneController.setConfig(key: "control:altitude_max", value: "\(millimeters)")
    }
    
    @objc private func vzMaxChanged(_ sender: NSSlider) {
        let mmPerSec = Int(sender.doubleValue)
        let mPerSec = Double(mmPerSec) / 1000.0  // mm/s to m/s
        let percentage = Int((sender.doubleValue - sender.minValue) / (sender.maxValue - sender.minValue) * 100)
        vzMaxLabel.stringValue = String(format: "Max V Speed: %.2f m/s (%d%%)", mPerSec, percentage)
        droneController.setConfig(key: "control:control_vz_max", value: "\(mmPerSec)")
    }
    
    @objc private func yawMaxChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        let percentage = Int((sender.doubleValue - sender.minValue) / (sender.maxValue - sender.minValue) * 100)
        yawMaxLabel.stringValue = String(format: "Max Yaw: %.1f rad/s (%d%%)", value, percentage)
        droneController.setConfig(key: "control:control_yaw", value: String(format: "%.2f", value))
    }
    
    // Public methods for gamepad button control
    func adjustEulerAngle(by percentChange: Double) {
        let range = eulerAngleSlider.maxValue - eulerAngleSlider.minValue
        let change = range * (percentChange / 100.0)
        let newValue = max(eulerAngleSlider.minValue, min(eulerAngleSlider.maxValue, eulerAngleSlider.doubleValue + change))
        eulerAngleSlider.doubleValue = newValue
        eulerAngleChanged(eulerAngleSlider)
    }
    
    func adjustVzMax(by percentChange: Double) {
        let range = vzMaxSlider.maxValue - vzMaxSlider.minValue
        let change = range * (percentChange / 100.0)
        let newValue = max(vzMaxSlider.minValue, min(vzMaxSlider.maxValue, vzMaxSlider.doubleValue + change))
        vzMaxSlider.doubleValue = newValue
        vzMaxChanged(vzMaxSlider)
    }
    
    @objc private func ssidFieldChanged(_ sender: NSTextField) {
        persistSSID(sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private func createMappingSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor
        container.layer?.cornerRadius = 12
        
        let title = NSTextField(labelWithString: "🎮 MAPPING DES CONTRÔLES")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        title.textColor = .white
        title.isBordered = false
        title.backgroundColor = .clear
        
        container.addSubview(title)
        
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16)
        ])
        
        // MAPPING CONFORME À L'ANCIEN CODE
        let mappings: [(String, String, NSColor)] = [
            ("✕", "Décollage", .systemBlue),
            ("□", "Atterrissage", .systemPink),
            ("△", "Arrêt d'urgence", .systemRed),
            ("○", "Reset urgence", .systemGreen),
            ("L1", "V Speed +5%", .systemOrange),
            ("R1", "Angle Max +5%", .systemOrange),
            ("L2", "V Speed -5%", .systemOrange),
            ("R2", "Angle Max -5%", .systemOrange),
            ("Share", "Mode Hover", .systemCyan),
            ("Options", "Déconnexion", .systemIndigo),
            ("D-Pad ↑", "Caméra avant", .systemOrange),
            ("D-Pad ↓", "Caméra bas", .systemOrange),
            ("D-Pad ←", "Enregistrement vidéo", .systemOrange),
            ("D-Pad →", "Prendre photo", .systemOrange)
        ]
        
        let cardWidth: CGFloat = 290
        let cardHeight: CGFloat = 32
        let spacing: CGFloat = 8
        let startX: CGFloat = 20
        let startY: CGFloat = 52
        
        for (idx, mapping) in mappings.enumerated() {
            let row = idx / 2
            let col = idx % 2
            
            let card = createMappingCard(button: mapping.0, action: mapping.1, color: mapping.2)
            container.addSubview(card)
            
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: startX + CGFloat(col) * (cardWidth + spacing)),
                card.topAnchor.constraint(equalTo: container.topAnchor, constant: startY + CGFloat(row) * (cardHeight + spacing)),
                card.widthAnchor.constraint(equalToConstant: cardWidth),
                card.heightAnchor.constraint(equalToConstant: cardHeight)
            ])
        }
        
        // Description sticks - improved visibility
        let hint = NSTextField(labelWithString: "🕹️ Stick Gauche: Yaw + Altitude  |  Stick Droit: Pitch + Roll")
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        hint.textColor = .systemCyan
        hint.isBordered = false
        hint.backgroundColor = .clear
        hint.alignment = .center
        
        container.addSubview(hint)
        
        NSLayoutConstraint.activate([
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            hint.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        
        return container
    }
    
    private func createMappingCard(button: String, action: String, color: NSColor) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
        card.layer?.cornerRadius = 8
        card.layer?.borderColor = color.withAlphaComponent(0.3).cgColor
        card.layer?.borderWidth = 1
        
        let buttonLabel = NSTextField(labelWithString: button)
        buttonLabel.translatesAutoresizingMaskIntoConstraints = false
        buttonLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)  // Increased from 13
        buttonLabel.textColor = color
        buttonLabel.alignment = .center
        buttonLabel.isBordered = false
        buttonLabel.backgroundColor = .clear
        
        let actionLabel = NSTextField(labelWithString: action)
        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        actionLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)  // Increased from 10
        actionLabel.textColor = .white
        actionLabel.isBordered = false
        actionLabel.backgroundColor = .clear
        
        card.addSubview(buttonLabel)
        card.addSubview(actionLabel)
        
        NSLayoutConstraint.activate([
            buttonLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            buttonLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            buttonLabel.widthAnchor.constraint(equalToConstant: 32),
            
            actionLabel.leadingAnchor.constraint(equalTo: buttonLabel.trailingAnchor, constant: 10),
            actionLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        
        return card
    }
    
    private func createSaveLocationSection() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor
        container.layer?.cornerRadius = 12
        
        let title = NSTextField(labelWithString: "💾 ENREGISTREMENT PHOTOS/VIDÉOS")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        title.textColor = .white
        title.isBordered = false
        title.backgroundColor = .clear
        
        let pathLabel = NSTextField(labelWithString: "Dossier:")
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        pathLabel.textColor = .systemGray
        pathLabel.isBordered = false
        pathLabel.backgroundColor = .clear
        
        let pathField = NSTextField()
        pathField.translatesAutoresizingMaskIntoConstraints = false
        pathField.isEditable = false
        pathField.isBordered = true
        pathField.bezelStyle = .roundedBezel
        pathField.font = NSFont.systemFont(ofSize: 12)
        pathField.placeholderString = "Sélectionner un dossier..."
        
        // Load saved path or use default
        let defaultPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        let savedPath = UserDefaults.standard.string(forKey: "SaveLocationPath") ?? defaultPath
        pathField.stringValue = savedPath
        
        let selectButton = NSButton(title: "Parcourir...", target: self, action: #selector(selectSaveLocation))
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectButton.bezelStyle = .rounded
        selectButton.controlSize = .regular
        
        container.addSubview(title)
        container.addSubview(pathLabel)
        container.addSubview(pathField)
        container.addSubview(selectButton)
        
        // Store reference for updates
        self.saveLocationPathField = pathField
        
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            title.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            pathLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 15),
            pathLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            
            pathField.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            pathField.leadingAnchor.constraint(equalTo: pathLabel.trailingAnchor, constant: 8),
            pathField.trailingAnchor.constraint(equalTo: selectButton.leadingAnchor, constant: -8),
            
            selectButton.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            selectButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            selectButton.widthAnchor.constraint(equalToConstant: 110)
        ])
        
        return container
    }
    
    @objc private func selectSaveLocation() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Sélectionner le dossier d'enregistrement"
        openPanel.message = "Choisissez où sauvegarder les photos et vidéos"
        
        if let window = self.window {
            openPanel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let url = openPanel.url {
                    let path = url.path
                    self?.saveLocationPathField?.stringValue = path
                    UserDefaults.standard.set(path, forKey: "SaveLocationPath")
                    self?.droneController.videoHandler.setSaveLocation(url)
                    print("📁 Save location updated: \(path)")
                }
            }
        }
    }
    
    // MARK: - Callbacks & Updates
    
    private func setupCallbacks() {
        droneController.onCriticalWarning = { [weak self] message in
            DispatchQueue.main.async {
                // Afficher en rouge clignotant
                self?.showWarningBanner(message, color: .systemRed)
            }
        }

        droneController.onInfoMessage = { [weak self] message in
            DispatchQueue.main.async {
                // Afficher en bleu
                self?.showWarningBanner(message, color: .systemBlue)
            }
        }
        
        droneController.onNavDataReceived = { [weak self] navData in
            self?.updateWithNavData(navData)
        }
        
        droneController.onFailsafeActivated = { [weak self] reason in
            DispatchQueue.main.async {
                self?.connectionLabel.stringValue = reason
                self?.connectionLabel.textColor = .systemOrange
                self?.connectionDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            }
        }
        
        droneController.onFailsafeRecovered = { [weak self] in
            DispatchQueue.main.async {
                self?.connectionLabel.stringValue = "Connecté"
                self?.connectionLabel.textColor = .systemGreen
                self?.connectionDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
            }
        }
    }
    
    private func startStatusUpdates() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }
    
    private func startWiFiMonitoring() {
        print("✅ Auto-connection monitoring active")
        
        // Vérifier toutes les 5 secondes (plus lent = moins de spam)
        wifiTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkDroneConnection()
        }
        
        // Première vérification après 3 secondes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.checkDroneConnection()
        }
    }
    
    private var warningBanner: NSTextField?

    private func showWarningBanner(_ message: String, color: NSColor) {
        // Supprimer l'ancien banner
        warningBanner?.removeFromSuperview()
        
        // Créer nouveau banner
        let banner = NSTextField(labelWithString: message)
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        banner.textColor = .white
        banner.backgroundColor = color
        banner.isBordered = false
        banner.alignment = .center
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 8
        
        guard let contentView = window?.contentView else { return }
        contentView.addSubview(banner)
        
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            banner.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 100),
            banner.widthAnchor.constraint(equalToConstant: 500),
            banner.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        warningBanner = banner
        
        // Auto-supprimer après 3 secondes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            banner.removeFromSuperview()
            if self?.warningBanner == banner {
                self?.warningBanner = nil
            }
        }
    }
    
    private var isAttemptingConnection = false
    private var connectionAttemptTime: Date?

    private func checkDroneConnection() {
        let isDroneConnected = droneController.isConnectedToDrone()
        let onDroneNetwork = isOn192Network()
        
        if isDroneConnected {
            // ✅ Drone connecté
            if connectionLabel.stringValue != "Connecté" {
                print("✅ Drone connected (receiving navdata)")
                connectionLabel.stringValue = "Connecté"
                connectionLabel.textColor = .systemGreen
                connectionDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                isAttemptingConnection = false
                connectionAttemptTime = nil
            }
        } else if onDroneNetwork {
            // Sur le réseau du drone
            if !isAttemptingConnection {
                // Première tentative
                print("🔌 On drone network - Connecting...")
                connectionLabel.stringValue = "Connexion..."
                connectionLabel.textColor = .systemYellow
                connectionDot.layer?.backgroundColor = NSColor.systemYellow.cgColor
                
                isAttemptingConnection = true
                connectionAttemptTime = Date()
                droneController.connect()
            } else if let attemptTime = connectionAttemptTime {
                // Vérifier si ça fait trop longtemps
                let elapsed = Date().timeIntervalSince(attemptTime)
                
                if elapsed > 10.0 {
                    // Plus de 10 secondes, réessayer
                    print("⏱️ Connection timeout - Retrying...")
                    isAttemptingConnection = false
                    connectionAttemptTime = nil
                }
            }
        } else {
            // Pas sur le réseau du drone
            if connectionLabel.stringValue != "Déconnecté" {
                print("❌ Not on drone network")
                connectionLabel.stringValue = "Déconnecté"
                connectionLabel.textColor = .systemRed
                connectionDot.layer?.backgroundColor = NSColor.systemRed.cgColor
                isAttemptingConnection = false
                connectionAttemptTime = nil
            }
        }
    }
    
    private func isOn192Network() -> Bool {
        // Vérifier si on est sur un réseau 192.168.1.x (réseau typique du drone)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        process.arguments = ["en0"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("inet 192.168.1.")
            }
        } catch {
            print("   ❌ Error checking network: \(error)")
        }
        
        return false
    }
    
    private func updateStatus() {
        // Mise à jour du statut de la manette
        let controllers = GCController.controllers()
        if let controller = controllers.first {
            let vendorName = controller.vendorName ?? "DualShock 4"
            controllerStatusLabel.stringValue = "🎮 \(vendorName)"
            controllerStatusLabel.textColor = .systemGreen
            
            if let gamepad = controller.extendedGamepad {
                gamepadVisualizerView.updateGamepad(gamepad)
                leftStickLabel.stringValue = String(format: "L: X:%.2f Y:%.2f",
                    gamepad.leftThumbstick.xAxis.value,
                    -gamepad.leftThumbstick.yAxis.value)
                rightStickLabel.stringValue = String(format: "R: X:%.2f Y:%.2f",
                    gamepad.rightThumbstick.xAxis.value,
                    -gamepad.rightThumbstick.yAxis.value)
            }
        } else {
            controllerStatusLabel.stringValue = "🎮 Déconnectée"
            controllerStatusLabel.textColor = .systemRed
        }
    }
    
    private func updateWithNavData(_ navData: NavData) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Batterie
            self.battValueLabel.stringValue = "\(navData.batteryPercentage)%"
            self.battValueLabel.textColor = navData.batteryPercentage > 30 ? .systemGreen :
                (navData.batteryPercentage > 15 ? .systemOrange : .systemRed)

            // Voltage
            let voltage = 10.5 + (Double(navData.batteryPercentage) / 100.0) * 2.1
            self.voltValueLabel.stringValue = String(format: "%.2fV", voltage)
            self.voltValueLabel.textColor = voltage > 11.1 ? .systemGreen : .systemOrange

            // Courant (estimation basée sur vitesse moteurs)
            let avgMotorSpeed = (Int(navData.motor1) + Int(navData.motor2) + Int(navData.motor3) + Int(navData.motor4)) / 4
            let current = avgMotorSpeed * 15
            self.currentValueLabel.stringValue = "\(current)mA"
            self.currentValueLabel.textColor = current > 7000 ? .systemOrange : .systemGreen

            // Température (estimation)
            let temp = 25.0 + Double(avgMotorSpeed) * 0.05
            self.tempValueLabel.stringValue = String(format: "%.0f°C", temp)
            self.tempValueLabel.textColor = temp > 45 ? .systemRed :
                (temp > 35 ? .systemOrange : .systemGreen)
            
            // Altitude
            self.altValueLabel.stringValue = String(format: "%.2fm", navData.altitudeMeters)
            self.altValueLabel.textColor = navData.altitudeMeters > 5.0 ? .systemOrange : .systemGreen
            
            // Vitesse verticale (calculée)
            var vSpeed = 0.0
            if let lastTime = self.lastAltitudeTime {
                let deltaTime = Date().timeIntervalSince(lastTime)
                if deltaTime > 0 {
                    vSpeed = (Double(navData.altitudeMeters) - self.lastAltitude) / deltaTime
                }
            }
            self.lastAltitude = Double(navData.altitudeMeters)
            self.lastAltitudeTime = Date()
            self.vSpeedValueLabel.stringValue = String(format: "%.2fm/s", vSpeed)
            self.vSpeedValueLabel.textColor = abs(vSpeed) > 1.0 ? .systemOrange : .systemGreen
            
            // Vitesse au sol
            self.speedValueLabel.stringValue = String(format: "%.2fm/s", navData.groundSpeed / 1000.0)
            
            // Cap
            let heading = (navData.yaw + 360).truncatingRemainder(dividingBy: 360)
            self.headingValueLabel.stringValue = String(format: "%.0f°", heading)
            
            // Pitch
            self.pitchValueLabel.stringValue = String(format: "%.1f°", navData.pitch)
            self.pitchValueLabel.textColor = abs(navData.pitch) > 30 ? .systemRed : .systemGreen
            
            // Roll
            self.rollValueLabel.stringValue = String(format: "%.1f°", navData.roll)
            self.rollValueLabel.textColor = abs(navData.roll) > 30 ? .systemRed : .systemGreen
            
            // Yaw
            self.yawValueLabel.stringValue = String(format: "%.1f°", navData.yaw)
            
            // Moteurs (avec code couleur selon RPM)
            let motorColor: (UInt8) -> NSColor = { rpm in
                if rpm > 200 { return .systemRed }
                if rpm > 100 { return .systemOrange }
                if rpm > 0 { return .systemGreen }
                return .systemGray
            }
            
            self.motor1ValueLabel.stringValue = "\(navData.motor1)"
            self.motor1ValueLabel.textColor = motorColor(navData.motor1)
            
            self.motor2ValueLabel.stringValue = "\(navData.motor2)"
            self.motor2ValueLabel.textColor = motorColor(navData.motor2)
            
            self.motor3ValueLabel.stringValue = "\(navData.motor3)"
            self.motor3ValueLabel.textColor = motorColor(navData.motor3)
            
            self.motor4ValueLabel.stringValue = "\(navData.motor4)"
            self.motor4ValueLabel.textColor = motorColor(navData.motor4)
            
            // État du drone
            let state = self.droneController.getCurrentControlState()
            self.stateValueLabel.stringValue = state
            switch state {
            case "Flying":
                self.stateValueLabel.textColor = .systemGreen
            case "Landed":
                self.stateValueLabel.textColor = .systemYellow
            case "Emergency":
                self.stateValueLabel.textColor = .systemRed
            default:
                self.stateValueLabel.textColor = .systemGray
            }
            
            // Mode de vol
            self.modeValueLabel.stringValue = state
            self.modeValueLabel.textColor = .systemBlue
        }
    }
}

// MARK: - Gamepad Visualizer View

class GamepadVisualizerView: NSView {
    
    private var pressedButtons: Set<String> = []
    private var leftStickX: CGFloat = 0
    private var leftStickY: CGFloat = 0
    private var rightStickX: CGFloat = 0
    private var rightStickY: CGFloat = 0
    private var leftTriggerValue: CGFloat = 0
    private var rightTriggerValue: CGFloat = 0
    
    private var controllerImage: NSImage?
    
    private let buttonPositions: [String: CGPoint] = [
        "Y": CGPoint(x: 472, y: 84),
        "B": CGPoint(x: 513, y: 124),
        "A": CGPoint(x: 472, y: 164),
        "X": CGPoint(x: 432, y: 124),
        "UP": CGPoint(x: 129, y: 95),
        "DOWN": CGPoint(x: 129, y: 155),
        "LEFT": CGPoint(x: 98, y: 124),
        "RIGHT": CGPoint(x: 158, y: 124),
        "L1": CGPoint(x: 120, y: 35),
        "R1": CGPoint(x: 480, y: 35),
        "L2": CGPoint(x: 90, y: 15),
        "R2": CGPoint(x: 510, y: 15),
        "OPTIONS": CGPoint(x: 190, y: 70),
        "MENU": CGPoint(x: 410, y: 70),
        "PS": CGPoint(x: 300, y: 285),
        "LEFT_STICK": CGPoint(x: 212, y: 199),
        "RIGHT_STICK": CGPoint(x: 390, y: 199),
        "TOUCHPAD": CGPoint(x: 300, y: 75)
    ]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
        
        if let imageURL = Bundle.module.url(forResource: "dualshock4", withExtension: "png"),
           let image = NSImage(contentsOf: imageURL) {
            controllerImage = image
        } else if let image = NSImage(named: "dualshock4") {
            controllerImage = image
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateGamepad(_ gamepad: GCExtendedGamepad) {
        pressedButtons.removeAll()
        
        if gamepad.buttonA.isPressed { pressedButtons.insert("A") }
        if gamepad.buttonB.isPressed { pressedButtons.insert("B") }
        if gamepad.buttonX.isPressed { pressedButtons.insert("X") }
        if gamepad.buttonY.isPressed { pressedButtons.insert("Y") }
        if gamepad.leftShoulder.isPressed { pressedButtons.insert("L1") }
        if gamepad.rightShoulder.isPressed { pressedButtons.insert("R1") }
        if gamepad.leftTrigger.value > 0.1 { pressedButtons.insert("L2") }
        if gamepad.rightTrigger.value > 0.1 { pressedButtons.insert("R2") }
        if gamepad.dpad.up.isPressed { pressedButtons.insert("UP") }
        if gamepad.dpad.down.isPressed { pressedButtons.insert("DOWN") }
        if gamepad.dpad.left.isPressed { pressedButtons.insert("LEFT") }
        if gamepad.dpad.right.isPressed { pressedButtons.insert("RIGHT") }
        if gamepad.buttonMenu.isPressed { pressedButtons.insert("MENU") }
        if let options = gamepad.buttonOptions, options.isPressed { pressedButtons.insert("OPTIONS") }
        if gamepad.leftThumbstickButton?.isPressed ?? false { pressedButtons.insert("LEFT_STICK") }
        if gamepad.rightThumbstickButton?.isPressed ?? false { pressedButtons.insert("RIGHT_STICK") }
        
        leftStickX = CGFloat(gamepad.leftThumbstick.xAxis.value)
        leftStickY = CGFloat(gamepad.leftThumbstick.yAxis.value)
        rightStickX = CGFloat(gamepad.rightThumbstick.xAxis.value)
        rightStickY = CGFloat(gamepad.rightThumbstick.yAxis.value)
        leftTriggerValue = CGFloat(gamepad.leftTrigger.value)
        rightTriggerValue = CGFloat(gamepad.rightTrigger.value)
        
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        if let image = controllerImage {
            let aspectRatio = image.size.width / image.size.height
            let viewAspectRatio = bounds.width / bounds.height
            var imageRect = bounds
            
            if aspectRatio > viewAspectRatio {
                let newHeight = bounds.width / aspectRatio
                imageRect = NSRect(x: 0, y: (bounds.height - newHeight) / 2, width: bounds.width, height: newHeight)
            } else {
                let newWidth = bounds.height * aspectRatio
                imageRect = NSRect(x: (bounds.width - newWidth) / 2, y: 0, width: newWidth, height: bounds.height)
            }
            
            image.draw(in: imageRect)
            
            let scaleX = imageRect.width / 600
            let scaleY = imageRect.height / 400
            
            for (button, imagePos) in buttonPositions {
                if pressedButtons.contains(button) {
                    let flippedY = 400 - imagePos.y
                    let scaledX = imagePos.x * scaleX + imageRect.origin.x
                    let scaledY = flippedY * scaleY + imageRect.origin.y
                    let absolutePos = CGPoint(x: scaledX, y: scaledY)
                    let color = colorForButton(button)
                    drawButtonOverlay(context: context, at: absolutePos, color: color, button: button, scale: min(scaleX, scaleY))
                }
            }
            
            if let leftStickImagePos = buttonPositions["LEFT_STICK"] {
                let flippedY = 400 - leftStickImagePos.y
                let scaledX = leftStickImagePos.x * scaleX + imageRect.origin.x
                let scaledY = flippedY * scaleY + imageRect.origin.y
                drawStickIndicator(context: context, at: CGPoint(x: scaledX, y: scaledY), xOffset: leftStickX * 20 * scaleX, yOffset: -leftStickY * 20 * scaleY, isPressed: pressedButtons.contains("LEFT_STICK"), scale: min(scaleX, scaleY))
            }
            
            if let rightStickImagePos = buttonPositions["RIGHT_STICK"] {
                let flippedY = 400 - rightStickImagePos.y
                let scaledX = rightStickImagePos.x * scaleX + imageRect.origin.x
                let scaledY = flippedY * scaleY + imageRect.origin.y
                drawStickIndicator(context: context, at: CGPoint(x: scaledX, y: scaledY), xOffset: rightStickX * 20 * scaleX, yOffset: -rightStickY * 20 * scaleY, isPressed: pressedButtons.contains("RIGHT_STICK"), scale: min(scaleX, scaleY))
            }
        }
    }
    
    private func colorForButton(_ button: String) -> NSColor {
        switch button {
        case "Y": return .systemGreen
        case "B": return .systemRed
        case "A": return .systemBlue
        case "X": return .systemPink
        case "UP", "DOWN", "LEFT", "RIGHT": return .systemYellow
        case "L1", "R1": return .systemOrange
        case "L2", "R2": return .systemPurple
        case "OPTIONS", "MENU": return .systemCyan
        case "PS": return .white
        case "LEFT_STICK", "RIGHT_STICK": return .systemGreen
        case "TOUCHPAD": return .systemTeal
        default: return .white
        }
    }
    
    private func drawButtonOverlay(context: CGContext, at position: CGPoint, color: NSColor, button: String, scale: CGFloat) {
        context.saveGState()
        
        if button == "TOUCHPAD" {
            let rect = CGRect(x: position.x - 80 * scale, y: position.y - 12 * scale, width: 160 * scale, height: 24 * scale)
            context.setFillColor(color.withAlphaComponent(0.5).cgColor)
            context.fill(rect)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2 * scale)
            context.stroke(rect)
        } else {
            let radius: CGFloat = 15 * scale
            let rect = CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
            
            context.setFillColor(color.withAlphaComponent(0.6).cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(3 * scale)
            context.strokeEllipse(in: rect)
            
            let glowRect = CGRect(x: position.x - radius - 5 * scale, y: position.y - radius - 5 * scale, width: (radius + 5 * scale) * 2, height: (radius + 5 * scale) * 2)
            context.setStrokeColor(color.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(5 * scale)
            context.strokeEllipse(in: glowRect)
        }
        
        context.restoreGState()
    }
    
    private func drawStickIndicator(context: CGContext, at position: CGPoint, xOffset: CGFloat, yOffset: CGFloat, isPressed: Bool, scale: CGFloat) {
        context.saveGState()
        
        let baseRadius: CGFloat = 30 * scale
        let baseRect = CGRect(x: position.x - baseRadius, y: position.y - baseRadius, width: baseRadius * 2, height: baseRadius * 2)
        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(2 * scale)
        context.strokeEllipse(in: baseRect)
        
        let stickPos = CGPoint(x: position.x + xOffset, y: position.y - yOffset)
        let stickRadius: CGFloat = 12 * scale
        let stickRect = CGRect(x: stickPos.x - stickRadius, y: stickPos.y - stickRadius, width: stickRadius * 2, height: stickRadius * 2)
        
        let stickColor = isPressed ? NSColor.systemRed : NSColor.systemGreen
        context.setFillColor(stickColor.withAlphaComponent(0.8).cgColor)
        context.fillEllipse(in: stickRect)
        context.setStrokeColor(stickColor.cgColor)
        context.setLineWidth(2 * scale)
        context.strokeEllipse(in: stickRect)
        
        context.restoreGState()
    }
}
