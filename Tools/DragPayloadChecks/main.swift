import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    precondition(condition(), message)
}
let session = UUID(), otherSession = UUID()
let a = UUID(), b = UUID()
func decode(_ value: String) -> DragPayload.BlockDrop {
    DragPayload.blockDrop(value, session: session)
}
check(decode(DragPayload.encodeBlocks([b, a], session: session)) == .blocks([b, a]), "Multi-row payload preserves selected visible order")
check(decode(DragPayload.encodeBlocks([a], session: session)) == .blocks([a]), "Versioned single row remains supported")
check(decode(DragPayload.encodeBlocks([a], session: otherSession)) == .invalid, "Identical block UUID from another library/session cannot move local content")
check(decode(DragPayload.block.encode(a)) == .invalid, "Unauthenticated single-row IDs are not ordinary text or local moves")
check(decode("openlist-block:bad") == .invalid, "Malformed legacy prefix never inserts literal text")
check(decode("openlist-blocks:v1:\(session.uuidString):\(a.uuidString),bad") == .invalid, "One malformed ID rejects the entire payload")
check(decode("openlist-blocks:v1:\(session.uuidString):\(a.uuidString),") == .invalid, "A missing trailing root rejects the entire payload")
check(decode(DragPayload.encodeBlocks([a, a], session: session)) == .invalid, "Duplicate roots are not silently accepted")
check(decode(DragPayload.encodeBlocks([], session: session)) == .invalid, "Empty internal moves are invalid")
check(decode("openlist-blocks:v2:\(session.uuidString):\(a.uuidString)") == .invalid, "Unknown versions fail closed")
check(decode(DragPayload.list.encode(a)) == .invalid, "List drags cannot turn into task text")
check(decode("Read the report\nand reply") == .text("Read the report\nand reply"), "External text keeps its native text path")
print("\(checks) drag payload checks passed")
