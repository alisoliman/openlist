import Foundation

@MainActor
func runPhoneCaptureEntryChecks() {
    let navigator = PhoneNavigator()
    let typed = CaptureRequest(listID: UUID(), dueToday: true)
    navigator.open(.capture(typed))
    navigator.open(.capture(CaptureRequest(listens: true)))
    check(navigator.sheet == .capture(typed), "A new voice request cannot replace an existing phone draft or its destination")
    navigator.dismissSheet()
    let voice = CaptureRequest(listens: true)
    navigator.open(.capture(voice))
    check(navigator.sheet == .capture(voice), "A fresh voice request opens the phone capture in listening mode")
    navigator.open(.capture(CaptureRequest()))
    check(navigator.sheet == .capture(voice), "A second capture request cannot replace a listening phone capture")
    navigator.dismissSheet()
    navigator.open(.capture(typed))
    check(navigator.sheet == .capture(typed), "A fresh typed draft still opens normally after dismissal")
}
