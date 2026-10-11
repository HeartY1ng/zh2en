#!/bin/bash
# 边打边学 Zh2En · 卸载
#   ./uninstall.sh         只预演：列出会做什么，什么都不改
#   ./uninstall.sh --yes   真正执行
#
# 按安装清单（.installed）倒序撤销 install.sh 做过的事，删除一律"移进废纸篓"。
# 鼠须管、雾凇拼音如果是安装脚本帮你装的，会问你要不要一起删；你自己原来装的，一律不动。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/.installed"
DO=0; [ "${1:-}" = "--yes" ] && DO=1
RIME="$HOME/Library/Rime"
SQUIRREL="${ZH2EN_SQUIRREL_APP:-/Library/Input Methods/Squirrel.app}"   # 环境变量只给测试用

run() {
  if [ $DO -eq 1 ]; then echo "  ▶ $*"; "$@" || echo "    （这一步没成功，继续往下）"
  else echo "  [预演] $*"; fi
}
to_trash() { if [ -e "$1" ]; then run trash "$1"; fi; }
ask() {   # 问一句（从终端读，因为下面的循环占用了标准输入）。预演时当作"是"，把会做的事列出来
  if [ $DO -eq 0 ]; then echo "  [预演] 会问你：$1"; return 0; fi
  [ "${ZH2EN_ASSUME_YES:-}" = 1 ] && return 0
  local a; read -r -p "  $1 [y/N] " a < /dev/tty || return 1; [ "$a" = "y" ] || [ "$a" = "Y" ]
}

if [ $DO -eq 1 ]; then echo "== 卸载 =="; else echo "== 预演（不会改任何东西；加 --yes 才执行）=="; fi

# 没有清单（比如删过仓库又重新克隆）：按默认位置来，只认和本项目一模一样的文件
if [ ! -f "$MANIFEST" ]; then
  echo "没找到安装清单，按默认位置清理（只删和本项目内容完全相同的文件）"
  LIST=""
  for pair in "dict/cedict.tsv|$RIME/zh2en/cedict.tsv" "rime/english_hint.lua|$RIME/lua/english_hint.lua" \
              "rime/sentence_tap.lua|$RIME/lua/sentence_tap.lua" "rime/rime_ice.custom.yaml|$RIME/rime_ice.custom.yaml" \
              "rime/theme/squirrel.custom.yaml|$RIME/squirrel.custom.yaml" "rime/theme/default.custom.yaml|$RIME/default.custom.yaml"; do
    src="$HERE/${pair%%|*}"; dst="${pair#*|}"
    if [ -f "$dst" ] && { [ "${src##*/}" = cedict.tsv ] || cmp -s "$src" "$dst"; }; then LIST+="file|$dst"$'\n'; fi
  done
  LIST+="app|$HOME/Applications/Zh2En.app"$'\n'"bundle|io.github.zh2en"$'\n'"keychain|zh2en|deepseek"
else
  LIST="$(cat "$MANIFEST")"
fi

BUNDLE_ID="$(echo "$LIST" | awk -F'|' '$1=="bundle"{print $2}' | tail -1)"
BUNDLE_ID="${BUNDLE_ID:-io.github.zh2en}"
APP="$(echo "$LIST" | awk -F'|' '$1=="app"{print $2}' | tail -1)"

echo
echo "【浮窗小程序】"
if [ -n "$APP" ] && pgrep -f "$APP/Contents/MacOS/Zh2En" >/dev/null; then run pkill -f "$APP/Contents/MacOS/Zh2En"; fi
if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then run defaults delete "$BUNDLE_ID"; fi
to_trash "$HOME/Library/Preferences/$BUNDLE_ID.plist"
to_trash "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
to_trash "$(getconf DARWIN_USER_CACHE_DIR)$BUNDLE_ID"   # 动画的图形缓存
to_trash "${TMPDIR:-/tmp}/zh2en"                         # 正在打的句子的临时状态文件

echo
echo "【按安装清单倒序撤销】"
echo "$LIST" | tail -r | while IFS='|' read -r kind a b; do
  case "$kind" in
    file|app) to_trash "$a" ;;
    keychain)
      if security find-generic-password -s "$a" -a "$b" >/dev/null 2>&1; then
        run security delete-generic-password -s "$a" -a "$b"
      fi ;;
    dir)   # 安装时新建的目录：空了才删
      if [ -d "$a" ] && [ -z "$(ls -A "$a" 2>/dev/null)" ]; then run rmdir "$a"; fi ;;
    rimedir)   # 安装脚本下载的雾凇拼音
      if [ -d "$a" ] && ask "雾凇拼音（$a）是安装脚本下载的，要一起删掉吗？里面也有鼠须管记住的你的常用词"; then
        to_trash "$a"
      fi ;;
    rimebackup)   # 安装前鼠须管自动生成的默认配置：原样放回
      if [ -d "$a" ]; then
        if [ -e "$RIME" ]; then echo "  · 你保留了雾凇，安装前的默认配置还在 $a，需要的话自己处理"
        else run mv "$a" "$RIME"; fi
      fi ;;
    squirrel)   # 安装脚本装的鼠须管
      if [ -d "$SQUIRREL" ] && ask "鼠须管（$a 版）是安装脚本装的，要一起卸掉吗？会要你输入电脑密码"; then
        run "$SQUIRREL/Contents/MacOS/Squirrel" --disable-input-source
        if pgrep -x Squirrel >/dev/null; then run killall Squirrel; fi
        run sudo mv "$SQUIRREL" "$HOME/.Trash/Squirrel-$(date +%Y%m%d-%H%M%S).app"
        if pkgutil --pkg-info im.rime.inputmethod.Squirrel >/dev/null 2>&1; then
          run sudo pkgutil --forget im.rime.inputmethod.Squirrel
        fi
      fi ;;
  esac
done
if [ -d "$RIME/zh2en" ] && [ -z "$(ls -A "$RIME/zh2en" 2>/dev/null)" ]; then run rmdir "$RIME/zh2en"; fi
if [ -d "$SQUIRREL" ] && [ -d "$RIME" ]; then
  run "$SQUIRREL/Contents/MacOS/Squirrel" --reload
fi
if [ $DO -eq 1 ]; then rm -rf "$HERE/.downloads"; fi
if [ $DO -eq 1 ] && [ -f "$MANIFEST" ]; then rm -f "$MANIFEST"; fi

echo
echo "【可能要你手动做的】"
echo "  · 如果安装时让你往自己的 rime_ice.custom.yaml 里加过 sentence_tap / english_hint 两行，把它们删掉，再在鼠须管菜单里点「重新部署」"
echo "  · 鼠须管和雾凇如果是你自己原来装的，这里没动。不想要了：系统设置 → 键盘 → 输入法 里移除「鼠须管」，再删掉 /Library/Input Methods/Squirrel.app 和 ~/Library/Rime"
echo "  · 卸掉了鼠须管的话，注销再登录一次，输入法菜单里的残留就没了"
echo "  · 不想要系统翻译语言包了：系统设置 → 通用 → 语言与地区 → 翻译语言"
if [ $DO -eq 0 ]; then echo; echo "== 预演结束。确认没问题再运行：./uninstall.sh --yes =="; fi
