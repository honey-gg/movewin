// movewin.swift
// 把「落在内建屏（含无头机上的幻影内建屏）」上的窗口，按比例搬到外接屏。
// 没有外接屏时什么都不做。
//
// 编译: swiftc -O -o ~/.local/bin/movewin movewin.swift
// 用法: movewin [-n|--dry-run] [--check] [-v] [--prompt]

import Cocoa
import ApplicationServices

// MARK: - 参数

var dryRun = false
var checkOnly = false
var verbose = false
var wantPrompt = false

for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "-n", "--dry-run": dryRun = true
    case "--check": checkOnly = true
    case "-v", "--verbose": verbose = true
    case "--prompt": wantPrompt = true
    case "-h", "--help":
        print("""
        movewin — 把内建屏上的窗口搬到外接屏

          movewin              搬（默认）
          movewin -n           只看会搬哪些，不动手
          movewin --check      只打印显示器布局与权限状态
          movewin -v           显示每个窗口的搬运细节
          movewin --prompt     权限不足时弹出系统授权对话框
        """)
        exit(0)
    default:
        FileHandle.standardError.write("未知参数: \(arg)\n".data(using: .utf8)!)
        exit(1)
    }
}

func say(_ s: String) { print(s) }
func warn(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

// MARK: - 显示器

struct DisplayInfo {
    let id: CGDirectDisplayID
    let isBuiltin: Bool
    let name: String
    let bounds: CGRect   // 全屏范围，AX/CG 全局坐标系（原点=主屏左上角）
    let visible: CGRect  // 扣掉菜单栏 / Dock 之后的可用区
}

guard let primary = NSScreen.screens.first else {
    warn("拿不到任何显示器信息，退出。")
    exit(1)
}
// NSScreen 坐标系原点在主屏左下角，翻成 AX/CG 的左上角原点
let primaryTop = primary.frame.maxY

var displays: [DisplayInfo] = []
for s in NSScreen.screens {
    guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
    let id = CGDirectDisplayID(num.uint32Value)
    let f = s.frame
    let v = s.visibleFrame
    displays.append(DisplayInfo(
        id: id,
        isBuiltin: CGDisplayIsBuiltin(id) != 0,
        name: s.localizedName,
        bounds: CGRect(x: f.minX, y: primaryTop - f.maxY, width: f.width, height: f.height),
        visible: CGRect(x: v.minX, y: primaryTop - v.maxY, width: v.width, height: v.height)
    ))
}

let mainID = CGMainDisplayID()
let builtins = displays.filter { $0.isBuiltin }
var externals = displays.filter { !$0.isBuiltin }

// 仅供自测：模拟"没有外接屏"的场景，验证空操作分支
if ProcessInfo.processInfo.environment["MOVEWIN_TEST_NO_EXTERNAL"] == "1" { externals = [] }

if checkOnly {
    say("显示器布局（坐标系原点 = 主屏左上角）:")
    for d in displays {
        let tag = d.isBuiltin ? "内建" : "外接"
        let mainTag = d.id == mainID ? "  ← 主显示器" : ""
        say(String(format: "  [%@] %@  id=%u%@", tag, d.name, d.id, mainTag))
        say(String(format: "        全屏  %@", NSStringFromRect(NSRectFromCGRect(d.bounds))))
        say(String(format: "        可用  %@", NSStringFromRect(NSRectFromCGRect(d.visible))))
    }
    let trusted = AXIsProcessTrusted()
    say("辅助功能权限: \(trusted ? "已授权" : "未授权")")
    say(trusted ? "状态正常。" : "需要在「系统设置 → 隐私与安全性 → 辅助功能」里勾选运行本命令的程序。")
    exit(trusted ? 0 : 2)
}

// 没有外接屏 → 不操作
guard !externals.isEmpty else {
    say("只有一个显示器（无外接屏），未做任何操作。")
    exit(0)
}
guard !builtins.isEmpty else {
    say("没有内建屏，无需移动。")
    exit(0)
}

// 目标屏：优先选主显示器（如果它是外接的），否则取第一块外接屏
let target = externals.first { $0.id == mainID } ?? externals[0]

// MARK: - 权限

guard AXIsProcessTrusted() else {
    warn("没有辅助功能（辅助功能）权限，无法移动别的 App 的窗口。")
    warn("请到「系统设置 → 隐私与安全性 → 辅助功能」里，勾选运行本命令的程序（终端 / WorkBuddy）。")
    if wantPrompt {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        warn("已弹出授权请求，授权后再跑一次即可。")
    } else {
        warn("授权后重新运行；或加 --prompt 让系统自动弹窗。")
    }
    exit(2)
}

// MARK: - AX 小工具

func copyAttr<T>(_ el: AXUIElement, _ attr: CFString) -> T? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success, let r = raw else { return nil }
    return r as? T
}

func axPoint(_ el: AXUIElement, _ attr: CFString) -> CGPoint? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success, let r = raw else { return nil }
    guard CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    guard AXValueGetValue(r as! AXValue, .cgPoint, &p) else { return nil }
    return p
}

func axSize(_ el: AXUIElement, _ attr: CFString) -> CGSize? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success, let r = raw else { return nil }
    guard CFGetTypeID(r) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    guard AXValueGetValue(r as! AXValue, .cgSize, &s) else { return nil }
    return s
}

func setPosition(_ el: AXUIElement, _ p: CGPoint) -> Bool {
    var point = p
    guard let v = AXValueCreate(.cgPoint, &point) else { return false }
    return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) == .success
}

// MARK: - 搬运

let myPID = ProcessInfo.processInfo.processIdentifier
var moved = 0
var scanned = 0
var skippedFullscreen = 0

say("内建屏: \(builtins.map(\.name).joined(separator: ", "))")
say("目标屏: \(target.name)\(target.id == mainID ? "（主显示器）" : "")")
if dryRun { say("—— 试运行，不会真的移动 ——") }
say("")

for app in NSWorkspace.shared.runningApplications {
    guard app.activationPolicy == .regular else { continue }
    guard app.processIdentifier != myPID, app.processIdentifier > 0 else { continue }

    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    guard let wins: [AXUIElement] = copyAttr(axApp, kAXWindowsAttribute as CFString), !wins.isEmpty else { continue }

    for (idx, w) in wins.enumerated() {
        scanned += 1
        guard let pos = axPoint(w, kAXPositionAttribute as CFString),
              let size = axSize(w, kAXSizeAttribute as CFString) else { continue }
        guard size.width > 1, size.height > 1 else { continue }

        let frame = CGRect(origin: pos, size: size)
        // 窗口中心落在哪块屏上，就认为它属于哪块屏
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let home = displays.first(where: { $0.bounds.contains(center) }), home.isBuiltin else { continue }

        // "AXFullScreen" 是系统实际使用的属性名（公开头文件里没有常量）
        if let fs: Bool = copyAttr(w, "AXFullScreen" as CFString), fs {
            skippedFullscreen += 1
            if verbose { say("跳过（全屏窗口）: \(app.localizedName ?? "?")") }
            continue
        }

        // 按比例映射到目标屏可用区，保证落点一定在屏内
        let availSrcW = max(1, home.bounds.width - size.width)
        let availSrcH = max(1, home.bounds.height - size.height)
        let ratioX = min(1, max(0, (frame.minX - home.bounds.minX) / availSrcW))
        let ratioY = min(1, max(0, (frame.minY - home.bounds.minY) / availSrcH))
        let availDstW = max(0, target.visible.width - size.width)
        let availDstH = max(0, target.visible.height - size.height)
        let newOrigin = CGPoint(x: target.visible.minX + ratioX * availDstW,
                                y: target.visible.minY + ratioY * availDstH)

        let title: String = copyAttr(w, kAXTitleAttribute as CFString) ?? "窗口 \(idx + 1)"
        let appName = app.localizedName ?? "pid \(app.processIdentifier)"

        if verbose || dryRun {
            say(String(format: "%@ — %@  (%d,%d) → (%d,%d)",
                       appName, title,
                       Int(frame.minX), Int(frame.minY), Int(newOrigin.x), Int(newOrigin.y)))
        } else {
            say("搬: \(appName) — \(title)")
        }

        if !dryRun {
            if setPosition(w, newOrigin) { moved += 1 }
            else { warn("  失败: \(appName) — \(title)") }
        } else {
            moved += 1
        }
    }
}

say("")
if dryRun {
    say("试运行结束: 有 \(moved) 个窗口在内建屏上，可被搬到 \(target.name)。")
} else {
    say("完成: 移动了 \(moved) 个窗口到 \(target.name)（扫描 \(scanned) 个窗口）。")
    if moved == 0 { say("内建屏上没有窗口，一切正常。") }
}
if skippedFullscreen > 0 {
    say("另有 \(skippedFullscreen) 个全屏窗口被跳过（全屏窗口需先退出全屏才能搬）。")
}
