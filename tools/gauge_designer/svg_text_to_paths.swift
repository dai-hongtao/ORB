#!/usr/bin/env swift

import Foundation
import CoreGraphics
import CoreText

struct Options {
  let inputURL: URL
  let outputURL: URL
}

func printUsage() {
  let scriptName = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "svg_text_to_paths.swift"
  FileHandle.standardError.write(Data("""
  用法:
    swift \(scriptName) input.svg [-o output.svg]

  说明:
    把当前仪表盘导出的 SVG 文字节点转成 path。
  """.utf8))
}

func parseArguments() -> Options? {
  let args = Array(CommandLine.arguments.dropFirst())
  guard !args.isEmpty else {
    return nil
  }

  var inputPath: String?
  var outputPath: String?
  var index = 0

  while index < args.count {
    let arg = args[index]
    switch arg {
    case "-o", "--output":
      index += 1
      guard index < args.count else {
        return nil
      }
      outputPath = args[index]
    case "-h", "--help":
      return nil
    default:
      if inputPath == nil {
        inputPath = arg
      } else {
        return nil
      }
    }
    index += 1
  }

  guard let inputPath else {
    return nil
  }

  let inputURL = URL(fileURLWithPath: inputPath)
  let resolvedOutput = outputPath ?? {
    let directory = inputURL.deletingLastPathComponent()
    let stem = inputURL.deletingPathExtension().lastPathComponent
    return directory.appendingPathComponent("\(stem)-outlined.svg").path
  }()

  return Options(
    inputURL: inputURL,
    outputURL: URL(fileURLWithPath: resolvedOutput)
  )
}

func parseLength(_ raw: String?) -> CGFloat? {
  guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
    return nil
  }
  ["mm", "px", "pt"].forEach { unit in
    if value.hasSuffix(unit) {
      value.removeLast(unit.count)
    }
  }
  guard let number = Double(value) else {
    return nil
  }
  return CGFloat(number)
}

func cssWeightValue(_ raw: String?) -> CGFloat {
  guard let raw else {
    return 0
  }
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  switch trimmed {
  case "normal":
    return 0
  case "bold":
    return 0.4
  default:
    if let numeric = Double(trimmed) {
      return max(-1, min(1, CGFloat((numeric - 400) / 500)))
    }
    return 0
  }
}

func decodeXML(_ text: String) -> String {
  return text
    .replacingOccurrences(of: "&lt;", with: "<")
    .replacingOccurrences(of: "&gt;", with: ">")
    .replacingOccurrences(of: "&quot;", with: "\"")
    .replacingOccurrences(of: "&apos;", with: "'")
    .replacingOccurrences(of: "&amp;", with: "&")
}

func escapeAttribute(_ text: String) -> String {
  return text
    .replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "\"", with: "&quot;")
}

func parseFontStack(_ raw: String?) -> [String] {
  return (raw ?? "")
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "") }
    .filter { !$0.isEmpty }
}

func resolveFontFamily(_ raw: String?) -> String {
  let installedFamilies = Set((CTFontManagerCopyAvailableFontFamilyNames() as NSArray) as? [String] ?? [])
  let genericFallbacks = [
    "sans-serif": "Helvetica",
    "serif": "Times New Roman",
    "monospace": "Menlo",
    "system-ui": "Helvetica"
  ]

  for family in parseFontStack(raw) {
    if installedFamilies.contains(family) {
      return family
    }
    if let fallback = genericFallbacks[family.lowercased()], installedFamilies.contains(fallback) {
      return fallback
    }
  }

  return parseFontStack(raw).first ?? "Helvetica"
}

func makeFont(family: String, size: CGFloat, weight: CGFloat) -> CTFont {
  let attributes: [CFString: Any] = [
    kCTFontFamilyNameAttribute: family,
    kCTFontTraitsAttribute: [
      kCTFontWeightTrait: weight
    ]
  ]
  let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
  return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

func formatNumber(_ value: CGFloat) -> String {
  let rounded = abs(value) < 0.00005 ? 0 : Double(value)
  var text = String(format: "%.4f", rounded)
  while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
    text.removeLast()
  }
  return text.isEmpty ? "0" : text
}

func svgPathData(from path: CGPath) -> String {
  var commands: [String] = []
  path.applyWithBlock { elementPointer in
    let element = elementPointer.pointee
    let points = element.points
    switch element.type {
    case .moveToPoint:
      commands.append("M \(formatNumber(points[0].x)) \(formatNumber(points[0].y))")
    case .addLineToPoint:
      commands.append("L \(formatNumber(points[0].x)) \(formatNumber(points[0].y))")
    case .addQuadCurveToPoint:
      commands.append("Q \(formatNumber(points[0].x)) \(formatNumber(points[0].y)) \(formatNumber(points[1].x)) \(formatNumber(points[1].y))")
    case .addCurveToPoint:
      commands.append("C \(formatNumber(points[0].x)) \(formatNumber(points[0].y)) \(formatNumber(points[1].x)) \(formatNumber(points[1].y)) \(formatNumber(points[2].x)) \(formatNumber(points[2].y))")
    case .closeSubpath:
      commands.append("Z")
    @unknown default:
      break
    }
  }
  return commands.joined(separator: " ")
}

func makePathData(
  text: String,
  x: CGFloat,
  y: CGFloat,
  fontFamily: String,
  fontSize: CGFloat,
  fontWeight: CGFloat,
  textAnchor: String,
  dominantBaseline: String
) -> String? {
  let font = makeFont(family: fontFamily, size: fontSize, weight: fontWeight)
  let attributes = [NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font]
  let attributed = NSAttributedString(string: text, attributes: attributes)
  let line = CTLineCreateWithAttributedString(attributed)

  var ascent: CGFloat = 0
  var descent: CGFloat = 0
  var leading: CGFloat = 0
  let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

  let startX: CGFloat
  switch textAnchor {
  case "middle":
    startX = x - width / 2
  case "end":
    startX = x - width
  default:
    startX = x
  }

  let baselineY: CGFloat
  switch dominantBaseline {
  case "middle", "central":
    baselineY = y + (ascent - descent) / 2
  case "text-after-edge", "ideographic":
    baselineY = y - descent
  case "hanging":
    baselineY = y + ascent
  default:
    baselineY = y
  }

  let mutablePath = CGMutablePath()
  let glyphRuns = CTLineGetGlyphRuns(line) as NSArray

  for runObject in glyphRuns {
    let run = runObject as! CTRun
    let glyphCount = CTRunGetGlyphCount(run)
    guard glyphCount > 0 else {
      continue
    }

    var glyphs = Array(repeating: CGGlyph(), count: glyphCount)
    var positions = Array(repeating: CGPoint.zero, count: glyphCount)
    CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
    CTRunGetPositions(run, CFRangeMake(0, 0), &positions)

    for index in 0 ..< glyphCount {
      guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) else {
        continue
      }
      let position = positions[index]
      let transform = CGAffineTransform(
        a: 1,
        b: 0,
        c: 0,
        d: -1,
        tx: startX + position.x,
        ty: baselineY - position.y
      )
      mutablePath.addPath(glyphPath, transform: transform)
    }
  }

  guard !mutablePath.isEmpty else {
    return nil
  }
  return svgPathData(from: mutablePath)
}

func parseAttributes(_ raw: String) -> [String: String] {
  let pattern = #"([A-Za-z_:][A-Za-z0-9:._-]*)\s*=\s*("([^"]*)"|'([^']*)')"#
  let regex = try! NSRegularExpression(pattern: pattern, options: [])
  let nsRange = NSRange(raw.startIndex..., in: raw)
  var attributes: [String: String] = [:]

  for match in regex.matches(in: raw, options: [], range: nsRange) {
    guard
      let nameRange = Range(match.range(at: 1), in: raw),
      let valueRange = Range(match.range(at: 3).location != NSNotFound ? match.range(at: 3) : match.range(at: 4), in: raw)
    else {
      continue
    }
    attributes[String(raw[nameRange])] = decodeXML(String(raw[valueRange]))
  }

  return attributes
}

func makePathElement(attributes: [String: String], text: String) -> String? {
  guard
    let x = parseLength(attributes["x"]),
    let y = parseLength(attributes["y"]),
    let fontSize = parseLength(attributes["font-size"])
  else {
    return nil
  }

  let fontFamily = resolveFontFamily(attributes["font-family"])
  let fontWeight = cssWeightValue(attributes["font-weight"])
  let textAnchor = attributes["text-anchor"] ?? "start"
  let dominantBaseline = attributes["dominant-baseline"] ?? "alphabetic"

  guard let pathData = makePathData(
    text: decodeXML(text),
    x: x,
    y: y,
    fontFamily: fontFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    textAnchor: textAnchor,
    dominantBaseline: dominantBaseline
  ) else {
    return nil
  }

  var pathAttributes = [
    #"d="\#(escapeAttribute(pathData))""#,
    #"fill-rule="nonzero""#,
    #"fill="\#(escapeAttribute(attributes["fill"] ?? "#111111"))""#
  ]

  ["opacity", "fill-opacity", "transform"].forEach { key in
    if let value = attributes[key], !value.isEmpty {
      pathAttributes.append(#"\#(key)="\#(escapeAttribute(value))""#)
    }
  }

  return "<path \(pathAttributes.joined(separator: " ")) />"
}

func stripStyleBlocks(from svg: String) -> String {
  let regex = try! NSRegularExpression(pattern: #"<style\b[^>]*>[\s\S]*?</style>"#, options: [.caseInsensitive])
  let range = NSRange(svg.startIndex..., in: svg)
  return regex.stringByReplacingMatches(in: svg, options: [], range: range, withTemplate: "")
}

func convertTextNodes(in svg: String) -> String {
  let regex = try! NSRegularExpression(pattern: #"<text\b([^>]*)>([\s\S]*?)</text>"#, options: [.caseInsensitive])
  let matches = regex.matches(in: svg, options: [], range: NSRange(svg.startIndex..., in: svg))
  var output = svg

  for match in matches.reversed() {
    guard
      let fullRange = Range(match.range(at: 0), in: output),
      let attrsRange = Range(match.range(at: 1), in: output),
      let textRange = Range(match.range(at: 2), in: output)
    else {
      continue
    }

    let attributes = parseAttributes(String(output[attrsRange]))
    let text = String(output[textRange])
    if let pathElement = makePathElement(attributes: attributes, text: text) {
      output.replaceSubrange(fullRange, with: pathElement)
    }
  }

  return stripStyleBlocks(from: output)
}

func run() throws {
  guard let options = parseArguments() else {
    printUsage()
    throw NSError(domain: "svg_text_to_paths", code: 64)
  }

  let input = try String(contentsOf: options.inputURL, encoding: .utf8)
  let output = convertTextNodes(in: input)
  try output.write(to: options.outputURL, atomically: true, encoding: .utf8)
  FileHandle.standardOutput.write(Data("已输出: \(options.outputURL.path)\n".utf8))
}

do {
  try run()
} catch {
  if (error as NSError).code != 64 {
    FileHandle.standardError.write(Data("转曲失败: \(error.localizedDescription)\n".utf8))
  }
  exit(1)
}
