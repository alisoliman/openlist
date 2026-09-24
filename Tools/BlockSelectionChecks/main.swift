import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(value(), message)
}

let ids = (0..<6).map { _ in UUID() }
let document = UUID(), inspector = UUID()
var controller = BlockSelection()
var selected = controller.select(ids[1], in: document, visible: ids, selected: [])
check(selected == [ids[1]] && controller.scopeID == document, "Editing a line selects it alone, in its pane's scope")
selected = controller.select(ids[4], in: document, visible: ids, selected: selected)
check(selected == [ids[4]], "Editing another line replaces the selection")
check(controller.select(UUID(), in: document, visible: ids, selected: selected) == [ids[4]],
      "A line not on show leaves the selection as it was")
selected = controller.reconcile(in: document, visible: [ids[4], ids[1], ids[4]], selected: selected)
check(selected == [ids[4]] && controller.visibleIDs == [ids[4], ids[1]], "Repeated appearances count once in their first visible position")
check(controller.reconcile(in: inspector, visible: [ids[0]], selected: selected) == selected,
      "Background pane updates cannot destroy the active selection")
selected = controller.select(ids[0], in: inspector, visible: [ids[0]], selected: selected)
check(selected == [ids[0]] && controller.scopeID == inspector, "Changing panes starts a new visible scope")
selected = controller.reconcile(in: inspector, visible: [], selected: selected)
check(selected.isEmpty && controller.visibleIDs.isEmpty, "An empty filtered view clears hidden selection")
controller.clear()
check(controller.scopeID == nil && controller.visibleIDs.isEmpty, "Clearing forgets the pane and its rows")
print("\(checks) block selection checks passed")
