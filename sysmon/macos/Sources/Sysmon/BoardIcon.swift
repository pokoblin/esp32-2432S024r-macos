import AppKit

/// 菜单栏图标：画成 ESP32-WROOM 模组的样子（顶部天线走线、中间金属屏蔽罩、两侧引脚）。
/// 模板图，系统会按菜单栏的明暗自动着色；未连接时加一道斜杠。
enum BoardIcon {
    static func image(connected: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()

            // 模组外框
            let body = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 1.5, width: 9, height: 15), xRadius: 1.2, yRadius: 1.2)
            body.lineWidth = 1.2
            body.stroke()

            // PCB 天线的蛇形走线
            let antenna = NSBezierPath()
            antenna.lineWidth = 1
            antenna.move(to: NSPoint(x: 6.5, y: 5.5))
            antenna.line(to: NSPoint(x: 6.5, y: 3.5))
            antenna.line(to: NSPoint(x: 9, y: 3.5))
            antenna.line(to: NSPoint(x: 9, y: 5.5))
            antenna.line(to: NSPoint(x: 11.5, y: 5.5))
            antenna.line(to: NSPoint(x: 11.5, y: 3.5))
            antenna.stroke()

            // 金属屏蔽罩
            NSBezierPath(roundedRect: NSRect(x: 6, y: 7.5, width: 6, height: 7.5), xRadius: 0.6, yRadius: 0.6).fill()

            // 两侧引脚
            for y in stride(from: 8.0, through: 15.0, by: 2.33) {
                NSRect(x: 1.5, y: y - 0.5, width: 2.5, height: 1).fill()
                NSRect(x: 14, y: y - 0.5, width: 2.5, height: 1).fill()
            }

            if !connected {
                // 先挖出一道空隙再画斜杠，让斜杠在图形上清晰可辨
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 2, y: 2))
                slash.line(to: NSPoint(x: 16, y: 16))
                slash.lineCapStyle = .round
                NSGraphicsContext.current?.compositingOperation = .clear
                slash.lineWidth = 3.5
                slash.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                slash.lineWidth = 1.4
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = connected ? "Sysmon 已连接" : "Sysmon 未连接"
        return image
    }
}
