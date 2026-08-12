import Testing
import Foundation
@testable import Pium

@Suite("Secret redaction")
struct SecretRedactionTests {
    @Test func avalueIsReplacedWhereverItAppears() {
        let redaction = SecretRedaction(values: ["hunter2"])
        #expect(redaction.scrub("token=hunter2") == "token=<redacted>")
        #expect(
            redaction.scrub("hunter2 and hunter2 again")
                == "<redacted> and <redacted> again"
        )
    }

    /// The common leak: a script echoing what it was handed, or a verbose
    /// client printing the URL it called.
    @Test func avalueInsideALongerStringIsStillFound() {
        let redaction = SecretRedaction(values: ["s3cr3t"])
        #expect(
            redaction.scrub("GET https://api.example.com/?key=s3cr3t&page=2")
                == "GET https://api.example.com/?key=<redacted>&page=2"
        )
    }

    @Test func everyValueIsScrubbed() {
        let redaction = SecretRedaction(values: ["one", "two"])
        #expect(redaction.scrub("one two three") == "<redacted> <redacted> three")
    }

    /// A short secret that mangles unrelated text is a better failure than a
    /// token that survives, so length is not a reason to skip a value.
    @Test func ashortValueIsScrubbedToo() {
        let redaction = SecretRedaction(values: ["ab"])
        #expect(redaction.scrub("cabbage") == "c<redacted>bage")
    }

    /// A field the user left empty must not turn every gap in the output into
    /// a redaction marker.
    @Test func anemptyValueIsIgnored() {
        let redaction = SecretRedaction(values: ["", "  "])
        #expect(redaction.scrub("nothing to hide") == "nothing to hide")
    }

    @Test func nosecretsMeansNoChange() {
        #expect(SecretRedaction(values: []).scrub("plain text") == "plain text")
    }
}
