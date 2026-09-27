import Foundation

struct MockupDetectionSettings: Sendable {
    var contrast: Double = 3
    var detectsDarkOnLight = true
    var maximumImageDimension = 2048

    static func load(from defaults: UserDefaults = .standard) -> Self {
        var settings = Self()
        if let value = defaults.object(forKey: "mockupDetection.contrast") as? Double,
           value.isFinite, (1...3).contains(value) {
            settings.contrast = value
        }
        if let value = defaults.object(forKey: "mockupDetection.darkOnLight") as? Bool {
            settings.detectsDarkOnLight = value
        }
        if let value = defaults.object(forKey: "mockupDetection.resolution") as? Int,
           [512, 1024, 2048, 4096].contains(value) {
            settings.maximumImageDimension = value
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(contrast, forKey: "mockupDetection.contrast")
        defaults.set(detectsDarkOnLight, forKey: "mockupDetection.darkOnLight")
        defaults.set(maximumImageDimension, forKey: "mockupDetection.resolution")
    }
}
