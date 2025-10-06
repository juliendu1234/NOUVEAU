import Cocoa

/// Splash screen displayed on app launch
class SplashWindowController: NSWindowController {
    
    private let splashImageView = NSImageView()
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Chargement...")
    
    var onComplete: (() -> Void)?
    
    init() {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1680, height: 1050)
        
        let window = NSWindow(
            contentRect: screen,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.black
        window.center()
        
        setupUI()
        startAnimation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        
        splashImageView.translatesAutoresizingMaskIntoConstraints = false
        splashImageView.imageScaling = .scaleProportionallyUpOrDown
        
        if let splashImage = NSImage(named: "splash") {
            splashImageView.image = splashImage
        } else {
            let label = NSTextField(labelWithString: "🚁")
            label.font = NSFont.systemFont(ofSize: 200)
            label.textColor = .white
            label.isBordered = false
            label.backgroundColor = .clear
            label.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
            
            let bitmapRep = label.bitmapImageRepForCachingDisplay(in: label.bounds)!
            label.cacheDisplay(in: label.bounds, to: bitmapRep)
            let image = NSImage(size: label.bounds.size)
            image.addRepresentation(bitmapRep)
            splashImageView.image = image
        }
        
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .large
        progressIndicator.startAnimation(nil)
        
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear
        
        let titleLabel = NSTextField(labelWithString: "ARDrone Parrot 2.0 - DualShock 4 - Swift")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 48, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        
        let subtitleLabel = NSTextField(labelWithString: "Technic informatique")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
        subtitleLabel.textColor = .systemGray
        subtitleLabel.alignment = .center
        subtitleLabel.isBordered = false
        subtitleLabel.backgroundColor = .clear
        
        contentView.addSubview(splashImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(progressIndicator)
        contentView.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            splashImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            splashImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -100),
            splashImageView.widthAnchor.constraint(equalToConstant: 300),
            splashImageView.heightAnchor.constraint(equalToConstant: 300),
            
            titleLabel.topAnchor.constraint(equalTo: splashImageView.bottomAnchor, constant: 30),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            progressIndicator.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 50),
            progressIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            statusLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 20),
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 400)
        ])
    }
    
    private func startAnimation() {
        let steps = [
            "Initialisation du système...",
            "Détection de la manette...",
            "Configuration du réseau...",
            "Prêt au décollage !"
        ]
        
        var delay: TimeInterval = 0.3
        var stepDelay: TimeInterval = 0.35
        
        for status in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.statusLabel.stringValue = status
            }
            delay += stepDelay
            stepDelay *= 0.9
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.6) { [weak self] in
            self?.fadeOutAndClose()
        }
    }
    
    private func fadeOutAndClose() {
        guard let window = window else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.close()
            self?.onComplete?()
        })
    }
}
