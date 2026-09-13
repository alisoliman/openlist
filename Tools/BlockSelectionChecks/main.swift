import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(value(), message)
}

let ids = (0..<6).map { _ in UUID() }
let document = UUID(), inspector = UUID()
var controller = BlockSelection()
var selected = controller.select(ids[1], gesture: .replace, in: document, visible: ids, selected: [])
selected = controller.select(ids[4], gesture: .range, in: document, visible: ids, selected: selected)
check(selected == Set(ids[1...4]), "Forward ranges follow visible order")
selected = controller.select(ids[2], gesture: .range, in: document, visible: ids, selected: selected)
check(selected == Set(ids[1...2]), "Shrinking a range keeps the original anchor")
selected = controller.select(ids[5], gesture: .toggle, in: document, visible: ids, selected: selected)
check(selected == Set([ids[1], ids[2], ids[5]]), "Additive selection retains disjoint rows")
selected = controller.select(ids[5], gesture: .toggle, in: document, visible: ids, selected: selected)
check(selected == Set([ids[1], ids[2]]), "Cmd-click can remove one selected row")
selected = controller.select(ids[3], gesture: .addingRange, in: document, visible: ids, selected: selected)
check(selected == Set(ids[1...5]), "An additive backward range retains earlier disjoint choices")
check(controller.ordered(selected) == Array(ids[1...5]), "Operations use display order, never Set iteration order")
selected = controller.reconcile(in: document, visible: [ids[4], ids[1], ids[4]], selected: selected)
check(controller.ordered(selected) == [ids[4], ids[1]], "Repeated appearances count once in their first visible position")
check(controller.anchorID == nil && controller.focusID == nil, "Filtered-out anchors and focus do not leave stale ranges")
check(controller.reconcile(in: inspector, visible: [ids[0]], selected: selected) == selected,
      "Background pane updates cannot destroy the active selection")
selected = controller.select(ids[0], gesture: .range, in: inspector, visible: [ids[0]], selected: selected)
check(selected == [ids[0]], "Changing panes starts a new visible scope")
controller.clear()
selected = controller.step(1, extending: false, in: document, visible: ids, selected: [])
check(selected == [ids[0]], "Keyboard navigation starts at the first row")
selected = controller.step(1, extending: true, in: document, visible: ids, selected: selected)
selected = controller.step(1, extending: true, in: document, visible: ids, selected: selected)
check(selected == Set(ids[0...2]), "Shift-arrow extends a keyboard range")
selected = controller.step(-1, extending: true, in: document, visible: ids, selected: selected)
check(selected == Set(ids[0...1]), "Reversing Shift-arrow shrinks the range")
selected = controller.reconcile(in: document, visible: [], selected: selected)
check(selected.isEmpty && controller.visibleIDs.isEmpty, "An empty filtered view clears hidden selection")
print("\(checks) block selection checks passed")
