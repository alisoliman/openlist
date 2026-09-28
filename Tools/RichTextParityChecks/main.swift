import AppKit
import Foundation

// The Mac and the iPhone share `Block.richData`. This reads archives the
// iPhone wrote (Fixtures/ios-*.rtf, made on an iOS simulator by
// Tools/make-rich-text-fixtures.sh from the Mac's own Fixtures/mac-*.rtf)
// and checks they mean on the Mac exactly what the samples say.

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    precondition(condition(), message())
    checks += 1
}

let fixtures = URL(fileURLWithPath: "Tools/RichTextParityChecks/Fixtures", isDirectory: true)
func fixture(_ name: String) -> Data {
    guard let data = try? Data(contentsOf: fixtures.appendingPathComponent(name)) else {
        fatalError("Missing \(name). Run Tools/make-rich-text-fixtures.sh.")
    }
    return data
}

if CommandLine.arguments.dropFirst().first == "write-mac-fixtures" {
    let folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    for sample in Parity.samples {
        let data = RichTextCodec.encode(Parity.build(sample), kind: sample.kind)!
        try data.write(to: folder.appendingPathComponent("mac-\(sample.name).rtf"))
    }
    print("Wrote \(Parity.samples.count) Mac rich text fixtures")
    exit(0)
}

for sample in Parity.samples {
    let intended = Parity.intended(sample)
    let own = RichTextCodec.encode(Parity.build(sample), kind: sample.kind)
    check(Parity.decoded(own, text: sample.text, for: sample) == intended,
          "\(sample.name): the Mac's own archive keeps the styling: \(Parity.decoded(own, text: sample.text, for: sample))")

    let mac = fixture("mac-\(sample.name).rtf")
    check(Parity.decoded(mac, text: sample.text, for: sample) == intended,
          "\(sample.name): the Mac archive the iPhone read still decodes the same on the Mac")

    let phone = fixture("ios-\(sample.name).rtf")
    check(Parity.decoded(phone, text: sample.text, for: sample) == intended,
          "\(sample.name): an archive written on the iPhone decodes to the same styling on the Mac: \(Parity.decoded(phone, text: sample.text, for: sample))")
    check(Parity.storedPointSizes(phone) == Parity.storedPointSizes(own!),
          "\(sample.name): the iPhone stores fonts at the Mac's point scale: \(Parity.storedPointSizes(phone)) vs \(Parity.storedPointSizes(own!))")

    // The Mac's archive, retitled on the iPhone, reads as the same edit made here.
    let expectedEdit = Parity.decoded(Parity.editing(mac, for: sample), text: sample.edited, for: sample)
    let phoneEdit = Parity.decoded(fixture("ios-\(sample.name)-edited.rtf"), text: sample.edited, for: sample)
    check(phoneEdit == expectedEdit && phoneEdit.map(\.text).joined() == sample.edited,
          "\(sample.name): an iPhone edit of a Mac archive keeps its styling on the Mac: \(phoneEdit) vs \(expectedEdit)")
}

// Typing inside a styled word keeps the style on either device.
let bolder = Parity.decoded(fixture("ios-task-styles-edited.rtf"), text: "Bolder ital code link strike end", for: Parity.samples[0])
check(bolder.first == ParityRun(text: "Bolder", bold: true), "Text typed into a bold word on the iPhone stays bold: \(bolder)")

print("\(checks) rich text parity checks passed")
