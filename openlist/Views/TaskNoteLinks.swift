import SwiftUI

/// Plain TextEditor intentionally stays plain. Explicit controls make pasted
/// local references usable by pointer, keyboard and assistive technology.
struct TaskNoteLinks: View {
    let note: String
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let references = NoteItemLink.references(in: note)
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(references) { reference in
                    Button(reference.title, systemImage: "link") {
                        env.localLinks.receive(reference.url)
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .link))
                    .help(reference.url.absoluteString)
                    .accessibilityValue(reference.url.absoluteString)
                    .accessibilityHint("Reveal the referenced item in this local library")
                }
            }
            // The links line up with the note's text; their hover fill reaches past it.
            .padding(.leading, 7)
            .accessibilityIdentifier("task-note-links")
        }
    }
}
