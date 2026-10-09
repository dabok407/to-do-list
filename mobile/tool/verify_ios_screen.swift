import Foundation
import Vision
import Darwin

// Verify actual simulator pixels, independently of Flutter's accessibility
// tree, which can remain stale after a cold external deep-link launch.
guard CommandLine.arguments.count >= 4 else {
    fputs("Usage: verify_ios_screen.swift IMAGE TITLE STATE\n", stderr)
    exit(2)
}

func normalize(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace }
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["ko-KR", "en-US"]
request.usesLanguageCorrection = false
let handler = VNImageRequestHandler(
    url: URL(fileURLWithPath: CommandLine.arguments[1]), options: [:])
try handler.perform([request])
let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: "\n")
print(text)
for expected in CommandLine.arguments.dropFirst(2) {
    guard normalize(text).contains(normalize(expected)) else {
        fputs("Expected visible screen text: \(expected)\n", stderr)
        exit(1)
    }
}
print("IOS_COLD_WIDGET_SCREEN_OK")
