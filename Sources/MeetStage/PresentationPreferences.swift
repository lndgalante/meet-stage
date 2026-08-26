import Foundation
import SwiftUI

enum PresentationColor: String, CaseIterable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    var id: Self { self }

    var label: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .red:
            Color(red: 1, green: 0.29, blue: 0.25)
        case .orange:
            Color(red: 1, green: 0.47, blue: 0.14)
        case .yellow:
            Color(red: 1, green: 0.78, blue: 0.12)
        case .green:
            Color(red: 0.24, green: 0.78, blue: 0.35)
        case .blue:
            Color(red: 0.18, green: 0.64, blue: 1)
        case .purple:
            Color(red: 0.72, green: 0.44, blue: 1)
        }
    }

    var contrastingColor: Color {
        self == .yellow ? .black.opacity(0.78) : .white
    }
}

enum PresentationSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: Self { self }

    var label: String {
        rawValue.capitalized
    }
}

enum KeystrokeAppearance: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark

    var id: Self { self }

    var label: String {
        rawValue.capitalized
    }
}

enum StageFrameStyle: String, CaseIterable, Identifiable, Sendable {
    case none
    case midnight
    case ocean
    case sunset
    case graphite

    var id: Self { self }

    var label: String {
        rawValue.capitalized
    }
}

enum StageFrameAppearance {
    static let paddingRange = 0.02...0.14
    static let defaultPadding = 0.06
    static let cornerRadiusRange = 0.0...36.0
    static let defaultCornerRadius = 18.0
    static let blurRange = 0.0...1.0
    static let defaultBlur = 0.25
    static let shadowRange = 0.0...1.0
    static let defaultShadow = 0.68
}

enum StageLogoAppearance {
    static let maximumDataSize = 10 * 1_024 * 1_024
    static let minimumStagePadding = 0.10
}

/// Persists presentation settings behind typed properties.
///
/// The raw keys are compatibility contracts with existing BetterMeets
/// installations. Keeping them at this boundary prevents `CaptureManager`
/// and SwiftUI views from depending on storage details.
struct PresentationPreferencesStore {
    static let highlightsMouseClicksKey = "presentation.highlightsMouseClicks"
    static let highlightsKeystrokesKey = "presentation.highlightsKeystrokes"
    static let annotationLifetimeSecondsKey = "presentation.annotationLifetimeSeconds"
    static let annotationColorKey = "presentation.annotationColor"
    static let spotlightSizeKey = "presentation.spotlightSize"
    static let spotlightOutsideOpacityKey = "presentation.spotlightOutsideOpacity"
    static let clickHighlightColorKey = "presentation.clickHighlightColor"
    static let clickHighlightSizeKey = "presentation.clickHighlightSize"
    static let keystrokeHighlightSizeKey = "presentation.keystrokeHighlightSize"
    static let keystrokeAppearanceKey = "presentation.keystrokeAppearance"
    static let stageFrameStyleKey = "presentation.stageFrameStyle"
    static let stageFramePaddingKey = "presentation.stageFramePadding"
    static let stageFrameCornerRadiusKey = "presentation.stageFrameCornerRadius"
    static let stageFrameBlurKey = "presentation.stageFrameBlur"
    static let stageFrameShadowKey = "presentation.stageFrameShadow"
    static let autoZoomSizeKey = "presentation.autoZoomSize"
    static let stageLogoDataKey = "presentation.stageLogoData"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var highlightsMouseClicks: Bool {
        get { defaults.bool(forKey: Self.highlightsMouseClicksKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.highlightsMouseClicksKey) }
    }

    var highlightsKeystrokes: Bool {
        get { defaults.bool(forKey: Self.highlightsKeystrokesKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.highlightsKeystrokesKey) }
    }

    var annotationLifetimeSeconds: Int {
        get {
            let savedValue = defaults.object(forKey: Self.annotationLifetimeSecondsKey) as? NSNumber
            return AnnotationTiming.normalizedLifetimeSeconds(
                savedValue?.intValue ?? AnnotationTiming.defaultLifetimeSeconds
            )
        }
        nonmutating set {
            defaults.set(
                AnnotationTiming.normalizedLifetimeSeconds(newValue),
                forKey: Self.annotationLifetimeSecondsKey
            )
        }
    }

    var annotationColor: PresentationColor {
        get { value(forKey: Self.annotationColorKey, default: .orange) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.annotationColorKey) }
    }

    var spotlightSize: PresentationSize {
        get { value(forKey: Self.spotlightSizeKey, default: .medium) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.spotlightSizeKey) }
    }

    var spotlightOutsideOpacity: Double {
        get {
            double(
                forKey: Self.spotlightOutsideOpacityKey,
                default: SpotlightAppearance.defaultOutsideOpacity,
                range: SpotlightAppearance.outsideOpacityRange
            )
        }
        nonmutating set {
            defaults.set(
                SpotlightAppearance.normalizedOutsideOpacity(newValue),
                forKey: Self.spotlightOutsideOpacityKey
            )
        }
    }

    var clickHighlightColor: PresentationColor {
        get { value(forKey: Self.clickHighlightColorKey, default: .orange) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.clickHighlightColorKey) }
    }

    var clickHighlightSize: PresentationSize {
        get { value(forKey: Self.clickHighlightSizeKey, default: .medium) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.clickHighlightSizeKey) }
    }

    var keystrokeHighlightSize: PresentationSize {
        get { value(forKey: Self.keystrokeHighlightSizeKey, default: .medium) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.keystrokeHighlightSizeKey) }
    }

    var keystrokeAppearance: KeystrokeAppearance {
        get { value(forKey: Self.keystrokeAppearanceKey, default: .dark) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.keystrokeAppearanceKey) }
    }

    var stageFrameStyle: StageFrameStyle {
        get { value(forKey: Self.stageFrameStyleKey, default: .midnight) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.stageFrameStyleKey) }
    }

    var stageFramePadding: Double {
        get {
            double(
                forKey: Self.stageFramePaddingKey,
                default: StageFrameAppearance.defaultPadding,
                range: StageFrameAppearance.paddingRange
            )
        }
        nonmutating set {
            defaults.set(
                clamped(newValue, to: StageFrameAppearance.paddingRange),
                forKey: Self.stageFramePaddingKey
            )
        }
    }

    var stageFrameCornerRadius: Double {
        get {
            double(
                forKey: Self.stageFrameCornerRadiusKey,
                default: StageFrameAppearance.defaultCornerRadius,
                range: StageFrameAppearance.cornerRadiusRange
            )
        }
        nonmutating set {
            defaults.set(
                clamped(newValue, to: StageFrameAppearance.cornerRadiusRange),
                forKey: Self.stageFrameCornerRadiusKey
            )
        }
    }

    var stageFrameBlur: Double {
        get {
            double(
                forKey: Self.stageFrameBlurKey,
                default: StageFrameAppearance.defaultBlur,
                range: StageFrameAppearance.blurRange
            )
        }
        nonmutating set {
            defaults.set(
                clamped(newValue, to: StageFrameAppearance.blurRange),
                forKey: Self.stageFrameBlurKey
            )
        }
    }

    var stageFrameShadow: Double {
        get {
            double(
                forKey: Self.stageFrameShadowKey,
                default: StageFrameAppearance.defaultShadow,
                range: StageFrameAppearance.shadowRange
            )
        }
        nonmutating set {
            defaults.set(
                clamped(newValue, to: StageFrameAppearance.shadowRange),
                forKey: Self.stageFrameShadowKey
            )
        }
    }

    var autoZoomSize: PresentationSize {
        get { value(forKey: Self.autoZoomSizeKey, default: .medium) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.autoZoomSizeKey) }
    }

    var stageLogoData: Data? {
        get { defaults.data(forKey: Self.stageLogoDataKey) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Self.stageLogoDataKey)
            } else {
                defaults.removeObject(forKey: Self.stageLogoDataKey)
            }
        }
    }

    private func value<Value>(
        forKey key: String,
        default defaultValue: Value
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key) else {
            return defaultValue
        }
        guard let value = Value(rawValue: rawValue) else {
            AppLog.preferences.warning(
                "Ignoring invalid value for \(key, privacy: .public): \(rawValue, privacy: .private)"
            )
            return defaultValue
        }
        return value
    }

    private func double(
        forKey key: String,
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard let savedValue = defaults.object(forKey: key) as? NSNumber else {
            return defaultValue
        }
        return min(max(savedValue.doubleValue, range.lowerBound), range.upperBound)
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
