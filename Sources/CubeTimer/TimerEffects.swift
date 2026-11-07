import AppKit
import AVFoundation
import Foundation
import UserNotifications

final class CompletionNotifications: NSObject, UNUserNotificationCenterDelegate,
                                             CompletionNotificationClient {
    static let shared = CompletionNotifications()
    private let center = UNUserNotificationCenter.current()
    private let identifier = "cube-timer-completion"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func schedule(after seconds: TimeInterval, title: String, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = AppStrings.localized("notification.nextStep")
        // Foreground delivery omits .sound in willPresent; the app plays its
        // volume-adjusted copy. Background delivery uses the bundled CAF.
        content.sound = playSound
            ? UNNotificationSound(named: UNNotificationSoundName(rawValue: CompletionAudio.notificationFile))
            : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func canDeliverSound() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let permitted = settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional
                continuation.resume(returning: permitted && settings.soundSetting == .enabled)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}


final class PresetSound: PresetSoundClient {
    private var player: AVAudioPlayer?

    func play(volume: Double) {
        if player == nil {
            guard let url = PresetAudio.playbackURL() else {
                NSLog("Pomodoro Float preset audio is missing from the app bundle")
                return
            }
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.numberOfLoops = 0
                player?.prepareToPlay()
            } catch {
                NSLog("Pomodoro Float could not load its preset audio: %@", String(describing: error))
                return
            }
        }
        guard let player else { return }
        player.stop()
        player.currentTime = 0
        player.volume = Float(max(0, min(1, volume)))
        if !player.play() {
            NSLog("Pomodoro Float could not start its preset audio")
        }
    }
}

final class CompletionSound: CompletionSoundClient {
    private var player: AVAudioPlayer?

    func play(volume: Double) {
        guard let url = CompletionAudio.playbackURL() else {
            NSLog("Pomodoro Float completion audio is missing from the app bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(max(0, min(1, volume)))
            player.numberOfLoops = 0
            player.prepareToPlay()
            self.player = player
            if !player.play() {
                NSLog("Pomodoro Float could not start its completion audio")
            }
        } catch {
            NSLog("Pomodoro Float could not play its completion audio: %@", String(describing: error))
        }
    }
}

@MainActor
final class SystemTimerAccessibilityAnnouncer: TimerAccessibilityAnnouncementClient {
    func announce(_ message: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
