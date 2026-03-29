import UIKit
import AudioToolbox

final class HapticManager {
    static let shared = HapticManager()
    private init() {}

    /// Light impact — +/- buttons, minor taps
    func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium impact — start workout, timer step complete
    func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Selection tick — expand/collapse, picker, calendar
    func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Notification success — exercise complete, weight confirmed
    func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Notification warning — close timer mid-workout
    func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Timer step complete — short chime + medium haptic
    func timerStepComplete() {
        AudioServicesPlaySystemSound(1057) // short tink
        medium()
    }

    /// Timer fully complete — triumphant chime + success haptic
    func timerComplete() {
        AudioServicesPlaySystemSound(1025) // ascending chime
        success()
    }

    /// PR celebration — escalating burst + success
    func celebration() {
        let light = UIImpactFeedbackGenerator(style: .light)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let notif = UINotificationFeedbackGenerator()

        light.prepare()
        medium.prepare()
        heavy.prepare()
        notif.prepare()

        light.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { medium.impactOccurred() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { heavy.impactOccurred() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { notif.notificationOccurred(.success) }
    }
}
