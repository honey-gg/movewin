#!/bin/zsh
# 搬窗口到外接屏 —— 双击运行
#
# 作用：把"落在内建屏（无头机上那块看不见的幻影屏）"的窗口，全部搬到外接屏。
#       没有外接屏时什么都不做，直接退出。
# 依赖：~/.local/bin/movewin
# 源码：~/WorkBuddy/2026-09-20-18-02-15/movewin/movewin.swift

BIN="$HOME/.local/bin/movewin"
SRC="$HOME/WorkBuddy/2026-09-20-18-02-15/movewin"
SETTINGS_URL="x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

pause() {
  if [ -t 0 ]; then
    printf '\n按任意键关闭此窗口…'
    read -k 1 -s 2>/dev/null
    print
  fi
}

if [ ! -x "$BIN" ]; then
  print "✗ 找不到 movewin：$BIN"
  print
  if [ -d "$SRC" ]; then
    print "  重新编译安装："
    print "    cd \"$SRC\" && swiftc -O -o movewin movewin.swift && cp movewin ~/.local/bin/"
  else
    print "  请把 movewin 放回 $BIN"
  fi
  pause
  exit 1
fi

clear
print "搬窗口到外接屏"
print "──────────────────────────────────────"
print

"$BIN" "$@"
rc=$?
print

if [ "$rc" = "2" ] && [ -t 0 ]; then
  answer=$(osascript -e 'display dialog "要把窗口从内建屏搬到外接屏，需要授予「辅助功能」权限。\n\n在「系统设置 → 隐私与安全性 → 辅助功能」里，勾选你运行本文件所用的终端（Terminal / iTerm），然后重新双击本文件。" buttons {"稍后", "打开系统设置"} default button "打开系统设置" with title "需要授权" with icon caution' -e 'button returned of result' 2>/dev/null)
  if [ "$answer" = "打开系统设置" ]; then
    open "$SETTINGS_URL"
  fi
fi

pause
exit $rc
