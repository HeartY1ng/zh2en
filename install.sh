#!/bin/bash
# 边打边学 Zh2En · 安装
#   ./install.sh             安装
#   ./install.sh --dry-run   只列出会做什么，什么都不改
#   ./install.sh --theme     顺便装上"清透玻璃"候选框外观（横排、一页 9 个候选）
#
# 缺鼠须管或雾凇拼音时，会问你要不要从官方 GitHub 自动下载安装：
#   鼠须管安装包会先校验苹果签名和公证（锁定官方团队 ID），不通过就停下，什么都不装。
#
# 规矩：先记账，再动手。每装一样东西都先写进 .installed（安装清单），
# ./uninstall.sh 只删清单里的东西。已经存在、又不是本项目装的文件，一律不覆盖。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DRY=0; THEME=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --theme) THEME=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "不认识的参数：$a"; exit 1 ;;
  esac
done

RIME="$HOME/Library/Rime"
SQUIRREL="${ZH2EN_SQUIRREL_APP:-/Library/Input Methods/Squirrel.app}"   # 环境变量只给测试用
SQUIRREL_TEAM="28HU5A7B46"   # 鼠须管官方安装包的苹果开发者团队 ID（rime/squirrel 发布页，2026-01 起）
APPS="$HOME/Applications"
APP_DEST="$APPS/Zh2En.app"
BUNDLE_ID="${BUNDLE_ID:-io.github.zh2en}"
MANIFEST="$HERE/.installed"
MANUAL=()   # 需要你手动做的事，最后一起列出来

say()  { echo "$@"; }
step() { echo; echo "▸ $*"; }
die()  { echo; echo "✗ $*" >&2; exit 1; }
run()  { if [ $DRY -eq 1 ]; then echo "  [预演] $*"; else "$@"; fi; }
record() {   # 记账（预演时不记）
  [ $DRY -eq 1 ] && return 0
  grep -qxF "$1" "$MANIFEST" 2>/dev/null || echo "$1" >> "$MANIFEST"
}
ours() { grep -qxF "file|$1" "$MANIFEST" 2>/dev/null; }
confirm() {   # 问一句。预演时当作"是"，把后面的步骤也演示出来；没有终端（非交互）时当作"否"
  if [ $DRY -eq 1 ]; then say "  [预演] 会问你：$1"; return 0; fi
  [ "${ZH2EN_ASSUME_YES:-}" = 1 ] && return 0
  [ -t 0 ] || return 1
  local a; read -r -p "  $1 [y/N] " a; [ "$a" = "y" ] || [ "$a" = "Y" ]
}

install_squirrel() {
  say "  没找到鼠须管（Rime 输入法引擎）。"
  confirm "要我从官方 GitHub（rime/squirrel）下载安装吗？中途要输一次电脑密码" \
    || die "没有鼠须管就用不了。也可以手动安装：https://rime.im 下载，或 brew install --cask squirrel-app"
  local tag url pkg sig
  tag=$(curl -fsSI --max-time 20 https://github.com/rime/squirrel/releases/latest \
        | awk -F/ 'tolower($1) ~ /^location:/ {print $NF}' | tr -d '\r\n')
  [ -n "$tag" ] || die "连不上 GitHub，拿不到最新版本号。稍后重试，或手动到 https://rime.im 下载。"
  url="https://github.com/rime/squirrel/releases/download/$tag/Squirrel-$tag.pkg"
  pkg="$HERE/.downloads/Squirrel-$tag.pkg"
  record "squirrel|$tag"
  run mkdir -p "$HERE/.downloads"
  run curl -fL --progress-bar -o "$pkg" "$url"
  if [ $DRY -eq 0 ]; then
    sig=$(spctl -a -vv -t install "$pkg" 2>&1 || true)
    if ! { echo "$sig" | grep -q "accepted" && echo "$sig" | grep -q "Notarized Developer ID" && echo "$sig" | grep -q "($SQUIRREL_TEAM)"; }; then
      rm -f "$pkg"
      die "鼠须管安装包的签名校验没通过（可能被篡改，或者官方换了签名团队），已经停下，什么都没装。
  校验结果：$sig"
    fi
    say "  ✓ 签名校验通过：官方签名 + 苹果公证（团队 $SQUIRREL_TEAM）"
  else
    say "  [预演] 校验苹果签名和公证（团队 $SQUIRREL_TEAM），不通过就停"
  fi
  run sudo installer -pkg "$pkg" -target /
  run rm -f "$pkg"
  run "$SQUIRREL/Contents/MacOS/Squirrel" --register-input-source
  run "$SQUIRREL/Contents/MacOS/Squirrel" --enable-input-source
  [ $DRY -eq 1 ] || say "  ✓ 鼠须管 $tag 已安装，并加进了输入法列表"
  MANUAL+=("如果输入法菜单里还看不到「鼠须管」，注销再登录一次。")
}

install_rime_ice() {
  # 只在 ~/Library/Rime 不存在、或者里面只有鼠须管自动生成的默认文件时，才自动装
  if [ -d "$RIME" ] && ls -A "$RIME" | grep -vqE '^(installation\.yaml|user\.yaml|build|.*\.userdb|sync|\.DS_Store)$'; then
    die "你的 ~/Library/Rime 里已经有自己的配置，为了不弄乱它，安装脚本不往里装雾凇。
  请按雾凇的说明手动安装：https://github.com/iDvel/rime-ice ，装好后重新运行本脚本。"
  fi
  say "  没找到雾凇拼音（鼠须管用的拼音方案和词库）。"
  confirm "要我从官方 GitHub（iDvel/rime-ice）下载吗？约 60MB" \
    || die "没有雾凇就用不了。也可以手动安装：https://github.com/iDvel/rime-ice"
  if [ -d "$RIME" ]; then   # 鼠须管自动生成的默认配置：挪到一边，卸载时原样放回
    local bak="$RIME.before-zh2en"
    [ -e "$bak" ] && die "$bak 已经存在，先处理掉它再重试。"
    record "rimebackup|$bak"
    run mv "$RIME" "$bak"
  fi
  record "rimedir|$RIME"
  run git clone --depth 1 https://github.com/iDvel/rime-ice.git "$RIME"
  [ $DRY -eq 1 ] || say "  ✓ 雾凇拼音已下载到 $RIME"
}

# put 源文件 目标：目标已存在、又不是本项目装的 → 不覆盖
put() {
  local src="$1" dst="$2"
  if [ $DRY -eq 1 ] && [ ! -f "$src" ]; then say "  [预演] cp $src $dst"; return 0; fi   # 预演时词典还没生成
  if [ -e "$dst" ] && ! ours "$dst"; then
    if [ -f "$src" ] && cmp -s "$src" "$dst"; then say "  · 已经有了：$dst"; record "file|$dst"; return 0; fi
    return 1
  fi
  [ -d "$(dirname "$dst")" ] || { record "dir|$(dirname "$dst")"; run mkdir -p "$(dirname "$dst")"; }
  record "file|$dst"
  run cp "$src" "$dst"
  [ $DRY -eq 1 ] || say "  ✓ $dst"
}

[ $DRY -eq 1 ] && say "== 预演：只列出会做什么，什么都不改 =="

step "检查环境"
ver=$(sw_vers -productVersion)
[ "${ver%%.*}" -ge 26 ] || die "需要 macOS 26 或更新（现在是 $ver）：浮窗用到了液态玻璃和新版系统翻译接口。"
command -v swiftc >/dev/null || die "没有 Swift 编译器。先运行：xcode-select --install"
command -v python3 >/dev/null || die "没有 python3。先运行：xcode-select --install"
command -v git >/dev/null || die "没有 git。先运行：xcode-select --install"
say "  ✓ macOS $ver · Swift · Python · git"
if [ -d "$SQUIRREL" ]; then say "  ✓ 鼠须管"; else install_squirrel; fi
if [ -f "$RIME/rime_ice.schema.yaml" ]; then say "  ✓ 雾凇拼音"; else install_rime_ice; fi

mkdir -p "$HERE/helper/.build/module-cache"
st=$(printf '%s\n' 'import Foundation' 'import Translation' \
  'let s = await LanguageAvailability().status(from: Locale.Language(identifier: "zh-Hans"), to: Locale.Language(identifier: "en"))' \
  'print(s)' | swift -module-cache-path "$HERE/helper/.build/module-cache" - 2>/dev/null | tail -1 || true)
if [ "$st" = "installed" ]; then
  say "  ✓ 系统翻译语言包（中文 → 英文）"
else
  MANUAL+=("下载系统翻译语言包：系统设置 → 通用 → 语言与地区 → 翻译语言，下载「中文（简体）」和「英语」。不下载的话浮窗没有直译。")
  say "  ! 系统翻译语言包还没下载（装完后会提醒你）"
fi

step "生成英文词典（第一次会下载 CC-CEDICT，约 4MB）"
if [ -f "$HERE/dict/cedict.tsv" ]; then say "  · 已经生成过"; else run python3 "$HERE/dict/build_dict.py"; fi

step "装进鼠须管（只新增文件，雾凇的原文件一个都不改）"
put "$HERE/dict/cedict.tsv"        "$RIME/zh2en/cedict.tsv"       || die "$RIME/zh2en/cedict.tsv 已经存在，而且不是本项目装的。"
put "$HERE/rime/english_hint.lua"  "$RIME/lua/english_hint.lua"   || die "$RIME/lua/english_hint.lua 已经存在，而且不是本项目装的。"
put "$HERE/rime/sentence_tap.lua"  "$RIME/lua/sentence_tap.lua"   || die "$RIME/lua/sentence_tap.lua 已经存在，而且不是本项目装的。"
CUSTOM="$RIME/rime_ice.custom.yaml"
if ! put "$HERE/rime/rime_ice.custom.yaml" "$CUSTOM"; then
  if grep -q "sentence_tap" "$CUSTOM" && grep -q "english_hint" "$CUSTOM"; then
    say "  · 你的 rime_ice.custom.yaml 里已经挂好了"
  else
    MANUAL+=("你已经有自己的 $CUSTOM，安装脚本不改它。请在它的 patch: 下面加上这两项（如果已经有 engine/filters/+ 列表，就把 lua_filter@*english_hint 加进那个列表），再到鼠须管菜单里点「重新部署」：
        engine/processors/@before 0: lua_processor@*sentence_tap
        engine/filters/+:
          - lua_filter@*english_hint")
    say "  ! 你已经有自己的 rime_ice.custom.yaml，没有改它（装完后告诉你加哪几行）"
  fi
fi
if [ $THEME -eq 1 ]; then
  put "$HERE/rime/theme/squirrel.custom.yaml" "$RIME/squirrel.custom.yaml" || say "  · 你已经有自己的 squirrel.custom.yaml，外观没装（不覆盖）"
  put "$HERE/rime/theme/default.custom.yaml"  "$RIME/default.custom.yaml"  || say "  · 你已经有自己的 default.custom.yaml，一页 9 个没装（不覆盖）"
fi
run "$SQUIRREL/Contents/MacOS/Squirrel" --reload
[ $DRY -eq 1 ] || say "  ✓ 已通知鼠须管重新部署"

step "编译浮窗小程序（第一次大约 1 分钟）"
run env BUNDLE_ID="$BUNDLE_ID" bash "$HERE/helper/build.sh"
if [ -e "$APP_DEST" ] && ! grep -qxF "app|$APP_DEST" "$MANIFEST" 2>/dev/null; then
  die "$APP_DEST 已经存在，而且不是本项目装的。"
fi
[ -d "$APPS" ] || { record "dir|$APPS"; run mkdir -p "$APPS"; }
record "bundle|$BUNDLE_ID"
record "app|$APP_DEST"
if pgrep -f "$APP_DEST/Contents/MacOS/Zh2En" >/dev/null; then run pkill -f "$APP_DEST/Contents/MacOS/Zh2En"; sleep 0.5; fi   # 只关我们装的那个
run rm -rf "$APP_DEST"   # 只会删到我们自己上次装的版本（上面已经确认过）
run ditto "$HERE/helper/.build/Zh2En.app" "$APP_DEST"
[ $DRY -eq 1 ] || say "  ✓ $APP_DEST"

step "DeepSeek 地道版（可选）"
say "  配了 key：一句话打完后，浮窗会补一句母语者真正会说的版本，再讲一个值得记的说法。"
say "  不配：只用苹果系统翻译，完全离线，一个字都不往外发。以后随时可以再配。"
if security find-generic-password -s zh2en -a deepseek >/dev/null 2>&1; then
  say "  · 已经配过了"
  record "keychain|zh2en|deepseek"
elif [ $DRY -eq 1 ]; then
  say "  [预演] 会问你要不要现在配置"
elif [ ! -t 0 ]; then
  say "  · 没有终端可以输入，先跳过：只用系统翻译。以后想配，运行：security add-generic-password -U -s zh2en -a deepseek -w"
else
  read -r -p "  现在配置 DeepSeek API key 吗？[y/N] " a
  if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
    record "keychain|zh2en|deepseek"
    say "  把 key 粘贴进去（屏幕上不会显示），回车；会让你再输一次确认："
    security add-generic-password -U -s zh2en -a deepseek -w
    say "  ✓ 已存进钥匙串（服务名 zh2en）"
  else
    say "  · 跳过：只用系统翻译"
  fi
fi

[ "${ZH2EN_SKIP_LAUNCH:-}" = 1 ] || run open "$APP_DEST"   # 测试安装脚本时可以不启动

echo
if [ $DRY -eq 1 ]; then
  say "== 预演结束。确认没问题再运行：./install.sh =="
  exit 0
fi
say "✅ 装好了。菜单栏右上角多了一个对话气泡图标。"
say "   试一下：输入法切到「鼠须管」，打一句「今天加班加到吐了。」"
say "   先看看效果：open -n $APP_DEST --args --demo"
if [ ${#MANUAL[@]} -gt 0 ]; then
  echo; say "还有几件事要你手动做："
  for i in "${!MANUAL[@]}"; do say "  $((i + 1)). ${MANUAL[$i]}"; done
fi
say "   卸载：./uninstall.sh（先预演），./uninstall.sh --yes（执行）"
