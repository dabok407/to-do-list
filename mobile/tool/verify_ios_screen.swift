import Foundation
import Vision
import Darwin

// Verify actual simulator pixels, independently of Flutter's accessibility
// tree, which can remain stale after a cold external deep-link launch.
guard CommandLine.arguments.count >= 4 else {
    fputs("Usage: verify_ios_screen.swift IMAGE TEXT TEXT ... [--allow-todoniq-banner-ocr]\n", stderr)
    exit(2)
}

func normalize(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace }
}

let bannerOCRFlag = "--allow-todoniq-banner-ocr"
let textArguments = Array(CommandLine.arguments.dropFirst(2))
let allowBannerOCR = textArguments.last == bannerOCRFlag
let expectedTexts = allowBannerOCR ? Array(textArguments.dropLast()) : textArguments
if textArguments.contains(bannerOCRFlag) {
    guard allowBannerOCR && expectedTexts.count == 2
        && expectedTexts.first == "Todoniq reminder test"
        && !expectedTexts.contains(bannerOCRFlag) else {
        fputs("The banner OCR flag requires exactly the Todoniq reminder test title and one body.\n", stderr)
        exit(2)
    }
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
// The English notification flow first verifies the exact title/body with
// Maestro and the app's brand in InfoPlist. Only that flow may opt into Vision's
// known whole-word Todonig/q confusion; the body always uses the raw OCR text.
let titleText = allowBannerOCR
    ? text.replacingOccurrences(of: "\\bTodonig\\b", with: "Todoniq", options: .regularExpression)
    : text
if titleText != text {
    print("IOS_TODONIQ_BANNER_OCR_ALIAS")
}
for (index, expected) in expectedTexts.enumerated() {
    let recognized = index == 0 ? titleText : text
    guard normalize(recognized).contains(normalize(expected)) else {
        fputs("Expected visible screen text: \(expected)\n", stderr)
        exit(1)
    }
}
print("IOS_COLD_WIDGET_SCREEN_OK")
