import SwiftUI

/// The inspector's note field stays plain text. Explicit controls make pasted
/// local references usable by pointer, keyboard and assistive technology.
struct TaskNoteLinks: View {
    let note: String
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let references = NoteItemLink.references(in: note)
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(references) { reference in
                    Button {
                        env.openLink(reference.url)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "link").font(.system(size: 10.5, weight: .medium)).accessibilityHidden(true)
                            Text(reference.title)
                        }
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .link))
                    .help(reference.url.absoluteString)
                    .accessibilityValue(reference.url.absoluteString)
                    .accessibilityHint(WidgetLink(url: reference.url) == nil
                        ? "Reveal the referenced item in this local library"
                        : "Open what this link names in Openlist")
                }
            }
            // The links line up with the note's text; their hover fill reaches past it.
            .padding(.leading, 7)
            .accessibilityIdentifier("task-note-links")
        }
    }
}
