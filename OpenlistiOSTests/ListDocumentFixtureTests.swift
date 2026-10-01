#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import OpenlistiOS

@MainActor
struct ListDocumentFixtureTests {
    @Test func anExplicitFlagCannotSeedOutsideAReviewSession() throws {
        let library = try TestLibrary()
        let before = try contentIDs(in: library)

        ListDocumentFixture.seedIfRequested(into: library.store, reviewSession: nil,
                                            environment: ["OpenlistDocumentFixture": "1"])

        let after = try contentIDs(in: library)
        #expect(after.lists == before.lists)
        #expect(after.blocks == before.blocks)
    }

    @Test func aReviewSessionRequiresTheExactExplicitFlag() throws {
        let library = try TestLibrary()
        let before = try contentIDs(in: library)
        let environments: [[String: String]] = [[:], ["OpenlistDocumentFixture": "0"], ["OpenlistDocumentFixture": "true"]]

        for environment in environments {
            ListDocumentFixture.seedIfRequested(into: library.store, reviewSession: "document-gate-tests",
                                                environment: environment)

            let after = try contentIDs(in: library)
            #expect(after.lists == before.lists)
            #expect(after.blocks == before.blocks)
        }
    }

    @Test func anExplicitReviewRequestSavesTheDocumentAndProseExamples() throws {
        let library = try TestLibrary()
        let before = try contentIDs(in: library)

        ListDocumentFixture.seedIfRequested(into: library.store, reviewSession: "document-fixture-tests",
                                            environment: ["OpenlistDocumentFixture": "1"])

        let additions = library.store.allLists(includeArchived: true).filter { !before.lists.contains($0.id) }
        #expect(Set(additions.map(\.title)) == ["Document review", "Travel notes"])
        let review = try #require(additions.first { $0.title == "Document review" })
        let blocks = library.store.blocks(inList: review.id)
        let outline = BlockTree.flatten(blocks, respectCollapse: false)
        #expect(outline.map(\.block.text) == [
            "Before we go", "Renew passports", "Get passport photos", "Submit the passport applications",
            "Bring the travel folder.", "In Kyoto",
            "Ryokan check-in is at 15:00. Leave the bags at reception if we arrive early.", "Pick up the rail passes",
        ])
        #expect(outline.map(\.block.kind) == [.heading1, .task, .task, .task, .paragraph, .heading1, .paragraph, .task])
        let parent = try #require(blocks.first { $0.text == "Renew passports" })
        #expect(parent.isCollapsed)
        let children = BlockTree.children(of: parent.id, in: blocks)
        #expect(children.map(\.isCompleted) == [true, false])
        let document = ListDocument(blocks: blocks, sorting: review.sorting)
        #expect(document.page.rows.count == 6)
        #expect(document.progress(for: parent)?.done == 1)
        #expect(document.progress(for: parent)?.total == 2)

        let notes = try #require(additions.first { $0.title == "Travel notes" })
        let prose = library.store.blocks(inList: notes.id)
        #expect(prose.map(\.kind) == [.paragraph])
        #expect(prose.map(\.text) == ["Keep the train confirmation here."])
        #expect(ListDocument(blocks: prose, sorting: notes.sorting).page.rows.count == 1)

        let reader = ModelContext(library.container)
        #expect(try reader.fetchCount(FetchDescriptor<Block>()) == before.blocks.count + 9)
        #expect(try reader.fetchCount(FetchDescriptor<TaskList>()) == before.lists.count + 2)
    }

    private func contentIDs(in library: TestLibrary) throws -> (lists: Set<UUID>, blocks: Set<UUID>) {
        let context = library.container.mainContext
        return (Set(try context.fetch(FetchDescriptor<TaskList>()).map(\.id)),
                Set(try context.fetch(FetchDescriptor<Block>()).map(\.id)))
    }
}
#endif
