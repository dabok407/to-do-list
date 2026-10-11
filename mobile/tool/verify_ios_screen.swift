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

let expectedTexts = Array(CommandLine.arguments.dropFirst(2))
func recognizeText(correctBrand: Bool) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.usesLanguageCorrection = correctBrand
    if correctBrand { request.customWords = ["Todoniq"] }
    let handler = VNImageRequestHandler(
        url: URL(fileURLWithPath: CommandLine.arguments[1]), options: [:])
    try handler.perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
}

var text = try recognizeText(correctBrand: false)
print(text)
// Vision can read the small banner's final q as g. Retry only a missing
// Todoniq expectation with the brand's spelling, never the expected sentence.
// Every expected title/body still has to match the recognized pixels exactly.
let missingTexts = expectedTexts.filter { !normalize(text).contains(normalize($0)) }
if !missingTexts.isEmpty && missingTexts.allSatisfy({ $0.contains("Todoniq") }) {
    print("IOS_OCR_BRAND_RETRY")
    text = try recognizeText(correctBrand: true)
    print(text)
}
for expected in expectedTexts {
    guard normalize(text).contains(normalize(expected)) else {
        fputs("Expected visible screen text: \(expected)\n", stderr)
        exit(1)
    }
}
print("IOS_COLD_WIDGET_SCREEN_OK")
