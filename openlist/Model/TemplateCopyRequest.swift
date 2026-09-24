import Foundation

struct TemplateCopyRequest: Identifiable {
    enum Source { case task(UUID), list(UUID) }
    let id = UUID()
    let source: Source
}
