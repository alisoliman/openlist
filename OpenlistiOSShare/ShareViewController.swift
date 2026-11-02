//
//  ShareViewController.swift
//  OpenlistiOSShare
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Share sheet's Add to Openlist: what was shared, as a task to edit,
/// with a link it came with as its note. Add leaves it for the app, which
/// files it into the Inbox, or the list an `@` names, the next time it comes
/// forward; the extension never opens the library itself.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareCaptureView(model: model, cancel: { [weak self] in self?.cancel() },
                                                                  add: { [weak self] in self?.add() }))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.load(items) }
    }

    private func add() {
        do {
            try SharedCaptures.append([SharedCapture(text: model.title, note: model.note)])
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            model.failure = error is SharedCaptures.Unavailable ? error.localizedDescription
                : "It couldn’t be added. \(error.localizedDescription)"
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

/// What the Share sheet was given, read once: the words for a title, and a
/// web link for the note.
@Observable
final class ShareModel {
    var title = ""
    var note = ""
    var failure: String?
    var isLoading = true

    func load(_ items: [NSExtensionItem]) async {
        var words = items.compactMap { $0.attributedContentText?.string ?? $0.attributedTitle?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
        var link: URL?
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if link == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = await Self.load(URL.self, from: provider), !url.isFileURL {
                link = url
            } else if words.isEmpty, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = await Self.load(String.self, from: provider) {
                words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Text that is itself a web address is the note, the title left to write.
        if link == nil, let address = URL(string: words), ["http", "https"].contains(address.scheme?.lowercased() ?? ""),
           !words.contains(where: \.isWhitespace) {
            link = address
            words = ""
        }
        if words == link?.absoluteString { words = "" }
        title = words
        note = link?.absoluteString ?? ""
        isLoading = false
    }

    /// One of the provider's items as `type`, or nil when it hasn't one.
    private static func load<Item: _ObjectiveCBridgeable & Sendable>(_ type: Item.Type, from provider: NSItemProvider) async -> Item?
    where Item._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { item, _ in continuation.resume(returning: item) }
        }
    }
}

/// The sheet: the task's words to edit, the link under them, Cancel and Add.
struct ShareCaptureView: View {
    @Bindable var model: ShareModel
    let cancel: () -> Void
    let add: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New task", text: $model.title, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($focused)
                        .accessibilityIdentifier("share.title")
                    if !model.note.isEmpty {
                        Label(model.note, systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                } footer: {
                    Text(model.failure ?? "Goes to your Inbox the next time you open Openlist. A date, #label or @list in the words is read then too.")
                        .foregroundStyle(model.failure == nil ? Color.secondary : Color.red)
                }
            }
            .navigationTitle("Add to Openlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .fontWeight(.semibold)
                        .disabled(model.isLoading || (model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && model.note.isEmpty))
                }
            }
        }
        .onChange(of: model.isLoading) { _, loading in if !loading { focused = true } }
    }
}
