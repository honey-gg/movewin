# movewin

把「落在内建屏（含无头机上的幻影内建屏）」上的窗口，按比例搬到外接屏。没有外接屏时什么都不做。

单文件 Swift 工具，无 Xcode 工程，直接 `swiftc` 编译。

## 编译

```bash
swiftc -O -o ~/.local/bin/movewin movewin.swift
```

## 用法

```bash
movewin              # 直接搬
movewin --dry-run    # 只打印会怎么搬，不实际动窗口
movewin --check      # 检查屏幕拓扑
movewin -v           # 详细输出
movewin --prompt     # 交互确认
```

双击 `搬窗口到外接屏.command` 也可以直接运行。

## 说明

需要「辅助功能」权限才能移动其他应用的窗口。首次运行 macOS 会提示到「系统设置 → 隐私与安全性 → 辅助功能」里授权。
