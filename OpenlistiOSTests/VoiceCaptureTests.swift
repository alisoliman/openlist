import Foundation
import Testing
import UIKit
@testable import OpenlistiOS

@MainActor
struct VoiceCaptureTests {
    @Test func voicePreferenceDefaultsToReviewAndPersists() {
        let suite = "PhoneVoicePreferences-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.afterVoiceCapture == .reviewBeforeSaving)
        settings.afterVoiceCapture = .saveAutomatically
        #expect(AppSettings(defaults: defaults).afterVoiceCapture == .saveAutomatically)
        defaults.set("unrecognized", forKey: "settings.afterVoiceCapture")
        #expect(AppSettings(defaults: defaults).afterVoiceCapture == .reviewBeforeSaving)
    }

    @Test func dockTouchAndAccessibilityActionsAreDistinct() {
        let control = OLCaptureButton.CaptureControl()
        #expect(control.isAccessibilityElement)
        #expect(control.accessibilityTraits.contains(.button))
        #expect(control.gestureRecognizers?.count == 1)
        #expect(control.hold.minimumPressDuration == 0.45)
        var actions: [CapturePress.Action] = []
        control.perform = { actions.append($0) }
        control.sendActions(for: .touchDown)
        control.sendActions(for: .touchUpInside)
        #expect(actions == [.typed])
        #expect(control.accessibilityActivate())
        #expect(control.accessibilitySayTasks())
        #expect(actions == [.typed, .typed, .voice])
        control.sendActions(for: .touchDown)
        control.sendActions(for: .touchCancel)
        control.sendActions(for: .touchUpInside)
        #expect(actions == [.typed, .typed, .voice])
    }

    @Test func holdReleaseCannotTapOrStop() {
        var press = CapturePress()
        press.begin()
        #expect(press.recognizeHold() == .voice)
        #expect(press.recognizeHold() == nil)
        #expect(press.end(inside: true) == nil)
        #expect(!press.isPressed)
        press.begin()
        #expect(press.end(inside: true) == .typed)
    }

    @Test func cancelPreventsLateVoiceDelivery() async {
        let voice = VoiceCapture()
        var deliveries = 0
        voice.onHeard = { _ in deliveries += 1 }
        voice.start(.fixture("Never add this task"), vocabulary: SpokenCapture.Vocabulary(),
                    afterCapture: .saveAutomatically)
        let lateStop = voice.listener.onStop
        voice.stop()
        voice.cancel()
        lateStop?("Delayed words")
        for _ in 0..<20 { await Task.yield() }
        #expect(deliveries == 0)
        #expect(voice.phase == .idle)
    }

    @Test(arguments: [false, true], [false, true])
    func sceneDepartureRequiresReview(isBackground: Bool, alreadyUnderstanding: Bool) async {
        let voice = VoiceCapture()
        var reviewed: [String] = []
        var saves = 0
        voice.onHeard = { tasks in
            if voice.completionMode == .saveAutomatically { saves += 1 }
            else { reviewed += tasks.map { $0.snapshot.title } }
        }
        voice.start(.fixture("Review when back"), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
        if alreadyUnderstanding { voice.stop() }
        let generation = voice.generation
        voice.sceneDepartedActive(isBackground: isBackground)
        #expect(voice.phase == .understanding)
        #expect(!voice.listener.isActive)
        #expect(voice.generation == generation)
        voice.sceneDepartedActive(isBackground: true)
        for _ in 0..<20 { await Task.yield() }
        #expect(reviewed == ["Review when back"])
        #expect(saves == 0)
    }

    @Test func permissionPromptDoesNotCancelPreparationButBackgroundDoes() async {
        let voice = VoiceCapture()
        var deliveries = 0
        voice.onHeard = { _ in deliveries += 1 }
        voice.start(.fixture("", preparing: true), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
        let generation = voice.generation
        let lateStop = voice.listener.onStop
        voice.sceneDepartedActive(isBackground: false)
        #expect(voice.phase == .preparing(progress: nil))
        #expect(voice.generation == generation)
        voice.sceneDepartedActive(isBackground: true)
        lateStop?("Late prepared words")
        for _ in 0..<20 { await Task.yield() }
        #expect(voice.phase == .idle)
        #expect(deliveries == 0)
    }

    @Test func activeDoneStillAutoSavesAndCancelStillWinsAfterDeparture() async {
        let voice = VoiceCapture()
        var modes: [AppSettings.AfterVoiceCapture] = []
        voice.onHeard = { _ in modes.append(voice.completionMode) }
        voice.start(.fixture("Intentional Done"), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
        voice.stop()
        for _ in 0..<20 { await Task.yield() }
        #expect(modes == [.saveAutomatically])
        voice.start(.fixture("Cancel after departure"), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
        let lateStop = voice.listener.onStop
        voice.sceneDepartedActive(isBackground: false)
        voice.cancel()
        lateStop?("Late cancelled words")
        for _ in 0..<20 { await Task.yield() }
        #expect(modes == [.saveAutomatically])
        #expect(voice.phase == .idle)
    }
}
