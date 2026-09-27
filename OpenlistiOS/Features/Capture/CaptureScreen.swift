//
//  CaptureScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// The Capture sheet (mockup 06). The shell's stub: the Capture feature adds
/// the tokenised field, parsed chips, destinations and the save.
struct CaptureScreen: View {
    let request: CaptureRequest
    @Environment(PhoneEnvironment.self) private var env
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        let navigator = env.navigator
        VStack(alignment: .leading, spacing: 10) {
            OLSheetHeader(confirmTitle: "Add", canConfirm: false, cancel: { navigator.dismissSheet() }, confirm: {})
            TextField("New task", text: $text, axis: .vertical)
                .font(OLFont.captureInput)
                .focused($isFocused)
            Text(destination)
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OLMetrics.gutter)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(236), .medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PhoneRoute.capture(request).screenIdentifier)
        .onAppear { isFocused = true }
    }

    private var destination: String {
        let list = request.listID.flatMap { env.store.list(id: $0) } ?? env.store.inboxList()
        return "Adds to \(list?.displayTitle ?? "Inbox")\(request.dueToday ? ", due today" : "")"
    }
}
