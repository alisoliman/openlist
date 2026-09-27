import Foundation
import UIKit

// Runs on an iOS simulator (Tools/make-rich-text-fixtures.sh). Reads the
// Mac's archives with the iPhone's codec, checks they mean what the samples
// say, and writes the archives the Mac suite reads back: the iPhone's own,
// and each Mac archive after a title edit on the iPhone.

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    guard condition() else {
        print("FAIL: \(message())")
        exit(1)
    }
    checks += 1
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for sample in Parity.samples {
    let intended = Parity.intended(sample)
    let own = RichTextCodec.encode(Parity.build(sample), kind: sample.kind)!
    check(Parity.decoded(own, text: sample.text, for: sample) == intended,
          "\(sample.name): the iPhone's own archive keeps the styling: \(Parity.decoded(own, text: sample.text, for: sample))")

    let mac = try Data(contentsOf: folder.appendingPathComponent("mac-\(sample.name).rtf"))
    check(Parity.decoded(mac, text: sample.text, for: sample) == intended,
          "\(sample.name): a Mac archive decodes to the same styling on the iPhone: \(Parity.decoded(mac, text: sample.text, for: sample))")
    check(Parity.storedPointSizes(mac) == Parity.storedPointSizes(own),
          "\(sample.name): the iPhone reads and writes the Mac's point scale: \(Parity.storedPointSizes(mac)) vs \(Parity.storedPointSizes(own))")

    let edited = Parity.editing(mac, for: sample)!
    check(Parity.decoded(edited, text: sample.edited, for: sample).map(\.text).joined() == sample.edited,
          "\(sample.name): an edit of a Mac archive keeps its text")

    try own.write(to: folder.appendingPathComponent("ios-\(sample.name).rtf"))
    try edited.write(to: folder.appendingPathComponent("ios-\(sample.name)-edited.rtf"))
}
print("\(checks) iPhone rich text checks passed; wrote \(Parity.samples.count * 2) fixtures")
