//
//  SampleData.swift
//  openlist
//

import Foundation

/// Seeds a small set of lists into an empty debug review-session library (see
/// `AppEnvironment.bootstrap`), so screenshots and QA open with something to
/// look at rather than an empty canvas.
enum SampleData {
    @MainActor
    static func seed(into store: Store) {
        guard let inbox = store.inboxList() else { return }
        let section = store.defaultSection()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        store.withoutLogging {
            // A couple of unfiled captures waiting in the Inbox.
            appendTask(store, to: DocumentContext(listID: inbox.id), "Press ⌘/ to see the keyboard shortcuts")
            let renew = appendTask(store, to: DocumentContext(listID: inbox.id), "Renew gym membership")
            renew.dueDate = calendar.date(byAdding: .day, value: 3, to: today)

            // Today
            let personal = store.createList(title: "Personal", icon: "🌱", accent: .green, in: section)
            let personalDoc = DocumentContext(listID: personal.id)
            appendHeading(store, to: personalDoc, "This week", kind: .heading2)

            let groceries = appendTask(store, to: personalDoc, "Do the weekly shop")
            groceries.dueDate = today
            groceries.recurrence = .weekly
            let milk = store.insertChild(kind: .task, text: "Oat milk", of: groceries)
            milk.sortIndex = 0
            let bread = store.insertChild(kind: .task, text: "Sourdough", of: groceries)
            bread.sortIndex = 1_024
            bread.isCompleted = true
            bread.completedAt = .now

            let call = appendTask(store, to: personalDoc, "Call Mum")
            call.dueDate = calendar.date(byAdding: .hour, value: 3, to: .now)
            call.includesTime = true
            call.isStarred = true

            let bills = appendTask(store, to: personalDoc, "Pay the electricity bill")
            bills.dueDate = calendar.date(byAdding: .day, value: -1, to: today)
            bills.recurrence = .monthly

            appendParagraph(store, to: personalDoc, "Meter reading goes on the portal before the 5th.")

            // A project-shaped list showing off nesting and block variety.
            let trip = store.createList(title: "Japan trip", icon: "🗻", accent: .indigo, in: section)
            let tripDoc = DocumentContext(listID: trip.id)
            trip.summary = "Two weeks in October — Tokyo, Hakone, Kyoto."

            appendHeading(store, to: tripDoc, "Before we go", kind: .heading2)
            let passport = appendTask(store, to: tripDoc, "Check passport expiry")
            passport.isCompleted = true
            passport.completedAt = calendar.date(byAdding: .day, value: -2, to: .now)

            let booking = appendTask(store, to: tripDoc, "Book the Hakone ryokan")
            booking.dueDate = calendar.date(byAdding: .day, value: 5, to: today)
            store.insertChild(kind: .task, text: "Compare two nights vs three", of: booking).sortIndex = 0
            store.insertChild(kind: .task, text: "Check the onsen has private baths", of: booking).sortIndex = 1_024

            appendTask(store, to: tripDoc, "Order yen")
            appendHeading(store, to: tripDoc, "Packing", kind: .heading2)
            appendBullet(store, to: tripDoc, "Universal adapter")
            appendBullet(store, to: tripDoc, "Comfortable walking shoes")
            appendBullet(store, to: tripDoc, "Portable battery")

            // A reading list demonstrating plain documents.
            let reading = store.createList(title: "Reading", icon: "📚", accent: .amber, in: section)
            let readingDoc = DocumentContext(listID: reading.id)
            appendTask(store, to: readingDoc, "Finish The Overstory")
            appendTask(store, to: readingDoc, "Start Piranesi")
            appendParagraph(store, to: readingDoc, "Anything by Le Guin next.")
        }

        store.save()
    }

    // MARK: - Builders

    @MainActor
    @discardableResult
    private static func appendTask(_ store: Store, to document: DocumentContext, _ text: String) -> Block {
        store.appendBlock(kind: .task, text: text, to: document)
    }

    @MainActor
    @discardableResult
    private static func appendHeading(_ store: Store, to document: DocumentContext, _ text: String, kind: BlockKind) -> Block {
        store.appendBlock(kind: kind, text: text, to: document)
    }

    @MainActor
    @discardableResult
    private static func appendParagraph(_ store: Store, to document: DocumentContext, _ text: String) -> Block {
        store.appendBlock(kind: .paragraph, text: text, to: document)
    }

    @MainActor
    @discardableResult
    private static func appendBullet(_ store: Store, to document: DocumentContext, _ text: String) -> Block {
        store.appendBlock(kind: .bullet, text: text, to: document)
    }
}
