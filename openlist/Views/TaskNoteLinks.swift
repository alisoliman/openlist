import SwiftUI

/// Plain TextEditor intentionally stays plain. Explicit controls make pasted
/// local references usable by pointer, keyboard and assistive technology.
struct TaskNoteLinks: View {
    let note: String
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let references = NoteItemLink.references(in: note)
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(references) { reference in
                    Button(reference.title, systemImage: "link") {
                        env.localLinks.receive(reference.url)
                    }
                    .buttonStyle(.borderless)
                    .help(reference.url.absoluteString)
                    .accessibilityValue(reference.url.absoluteString)
                    .accessibilityHint("Reveal the referenced item in this local library")
                }
            }
            .font(.callout)
            .accessibilityIdentifier("task-note-links")
        }
    }
}
