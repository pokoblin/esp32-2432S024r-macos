// 生成横幅大标题用的小字库：只收 firmware/lib/sysmon_core/banner_titles.h 里出现的字。
// 用 macOS 自带的 CoreText 光栅化，输出 LovyanGFX 能从内存加载的 VLW 格式。
//
// 用法（在仓库根目录）：
//   swift sysmon/tools/make_banner_font.swift ~/Library/Fonts/SourceHanSansCN-Bold.otf 24
//
// 输出：
//   sysmon/firmware/src/banner_font.h              VLW 字节数组
//   sysmon/firmware/lib/sysmon_core/banner_glyphs.h 收了哪些字（native 测试据此检查漏字）
//
// VLW 格式（对照 LovyanGFX 的 VLWfont::loadFont）：
//   头部 6 个大端 int32：字数、版本 11、字号、0、ascent、descent
//   每个字 7 个大端 int32：码点、高、宽、advance、dY（基线到位图顶）、dX（左侧偏移）、0；按码点升序
//   然后按同样顺序是每个字的位图，逐行，每像素 1 字节 alpha
import CoreGraphics
import CoreText
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let size = Int(args[2]) else {
    FileHandle.standardError.write("用法: swift make_banner_font.swift <字体文件> <像素字号>\n".data(using: .utf8)!)
    exit(1)
}
let fontPath = (args[1] as NSString).expandingTildeInPath
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let titlesURL = root.appendingPathComponent("firmware/lib/sysmon_core/banner_titles.h")
let fontOut = root.appendingPathComponent("firmware/src/banner_font.h")
let glyphsOut = root.appendingPathComponent("firmware/lib/sysmon_core/banner_glyphs.h")

// 1. 从标题文件里抽字：所有 "..." 里的非 ASCII 字，去重后按码点排序
let titles = try String(contentsOf: titlesURL, encoding: .utf8)
var scalars = Set<Unicode.Scalar>()
// 按双引号切开，奇数段就是引号里的内容
for (i, part) in titles.components(separatedBy: "\"").enumerated() where i % 2 == 1 {
    for s in part.unicodeScalars where s.value > 0x7F { scalars.insert(s) }
}
let chars = scalars.sorted { $0.value < $1.value }
guard !chars.isEmpty, chars.allSatisfy({ $0.value <= 0xFFFF }) else {
    FileHandle.standardError.write("标题里没有可收的字，或有超出 BMP 的字\n".data(using: .utf8)!)
    exit(1)
}

// 2. 加载字体
guard let descs = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: fontPath) as CFURL) as? [CTFontDescriptor],
      let desc = descs.first else {
    FileHandle.standardError.write("读不了字体文件 \(fontPath)\n".data(using: .utf8)!)
    exit(1)
}
let font = CTFontCreateWithFontDescriptor(desc, CGFloat(size), nil)
let ascent = Int(CTFontGetAscent(font).rounded(.up))
let descent = Int(CTFontGetDescent(font).rounded(.up))

struct Glyph {
    var code: UInt32
    var width: Int, height: Int, advance: Int, dY: Int, dX: Int
    var alpha: [UInt8]
}

// 3. 逐字光栅化：灰度画布、黑底白字，灰度值就是覆盖率；再裁掉四周全空的行列
let pad = size
let canvasW = size * 3, canvasH = size * 3
let baselineY = pad + descent  // 画布坐标从下往上
var glyphs: [Glyph] = []
for ch in chars {
    var unichar = UniChar(ch.value)
    var glyph = CGGlyph()
    guard CTFontGetGlyphsForCharacters(font, &unichar, &glyph, 1) else {
        FileHandle.standardError.write("字体里没有「\(Character(ch))」\n".data(using: .utf8)!)
        exit(1)
    }
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)

    let ctx = CGContext(data: nil, width: canvasW, height: canvasH, bitsPerComponent: 8, bytesPerRow: canvasW,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.setShouldAntialias(true)
    ctx.setShouldSmoothFonts(false)
    var origin = CGPoint(x: pad, y: baselineY)
    CTFontDrawGlyphs(font, &glyph, &origin, 1, ctx)

    // 内存里第 0 行是画布最上面一行
    let data = ctx.data!.bindMemory(to: UInt8.self, capacity: canvasW * canvasH)
    var top = canvasH, bottom = -1, left = canvasW, right = -1
    for row in 0..<canvasH {
        for col in 0..<canvasW where data[row * canvasW + col] > 0 {
            top = min(top, row); bottom = max(bottom, row)
            left = min(left, col); right = max(right, col)
        }
    }
    guard bottom >= 0 else { continue }
    var alpha: [UInt8] = []
    for row in top...bottom {
        for col in left...right { alpha.append(data[row * canvasW + col]) }
    }
    // 基线在内存里的行号：它上面那一行就是基线以上第 1 行
    let baselineRow = canvasH - baselineY
    glyphs.append(Glyph(code: ch.value, width: right - left + 1, height: bottom - top + 1,
                        advance: Int(advance.width.rounded()), dY: baselineRow - top, dX: left - pad,
                        alpha: alpha))
}

// 4. 拼 VLW
var bytes: [UInt8] = []
func put(_ v: Int) {
    let u = UInt32(bitPattern: Int32(v))
    bytes += [UInt8(u >> 24 & 0xFF), UInt8(u >> 16 & 0xFF), UInt8(u >> 8 & 0xFF), UInt8(u & 0xFF)]
}
put(glyphs.count); put(11); put(size); put(0); put(ascent); put(descent)
for g in glyphs {
    put(Int(g.code)); put(g.height); put(g.width); put(g.advance); put(g.dY); put(g.dX); put(0)
}
for g in glyphs { bytes += g.alpha }

// 5. 写文件
// 命令里的字体路径把家目录写成 ~，生成的文件里不留本机用户名
let shownPath = fontPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
let cmd = "swift sysmon/tools/make_banner_font.swift \(shownPath) \(size)"
let fontName = (CTFontCopyFullName(font) as String)
var header = """
// 由 \(cmd) 生成，不要手改。
// 字体：\(fontName)（SIL Open Font License 1.1），\(size)px，\(glyphs.count) 个字，\(bytes.count) 字节。
// 只给横幅大标题用（见 lib/sysmon_core/banner_titles.h）。
#pragma once
#include <stdint.h>

static const uint8_t kBannerFontVlw[] = {

"""
for start in stride(from: 0, to: bytes.count, by: 16) {
    let line = bytes[start..<min(start + 16, bytes.count)].map { String(format: "0x%02x", $0) }.joined(separator: ", ")
    header += "  \(line),\n"
}
header += "};\n"
try header.write(to: fontOut, atomically: true, encoding: .utf8)

let glyphText = String(String.UnicodeScalarView(glyphs.compactMap { Unicode.Scalar($0.code) }))
let glyphsHeader = """
// 由 \(cmd) 生成，不要手改。
// 横幅小字库里收了哪些字，按码点升序；native 测试据此检查横幅标题有没有漏字。
#pragma once

namespace sysmon {

constexpr const char* kBannerGlyphs = "\(glyphText)";

}  // namespace sysmon

"""
try glyphsHeader.write(to: glyphsOut, atomically: true, encoding: .utf8)
print("\(glyphs.count) 个字，\(bytes.count) 字节：\(glyphText)")
