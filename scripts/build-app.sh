#!/bin/bash
# PokeTokenLBI.app 번들 조립 + /Applications 설치
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.5.6"
APP_NAME="PokeTokenLBI"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
GIT_COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
GIT_COMMIT_DATE="$(git log -1 --format='%cd' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || date '+%Y-%m-%d %H:%M')"
# The same instant in seconds: the date above is in the committer's time zone, so two builds can't be ordered by it.
GIT_COMMIT_TIME="$(git log -1 --format='%ct' 2>/dev/null || date '+%s')"

# Apply optional local patch (for private personal tweaks not committed to git)
LOCAL_PATCH="${PTB_LOCAL_PATCH:-$HOME/Library/Application Support/PokeTokenBar/local.patch}"
if [[ -f "$LOCAL_PATCH" ]]; then
    echo "==> Applying local private patch from $LOCAL_PATCH"
    git apply "$LOCAL_PATCH" 2>/dev/null || true
fi

# README 가 Apple Silicon + Intel 지원을 약속하므로 배포 바이너리는 universal(arm64 + x86_64)이어야 한다.
# `swift build --arch arm64 --arch x86_64` 는 Xcode(xcbuild)가 필요해 Command Line Tools 만으로는 실패하므로
# 아키텍처별로 따로 빌드한 뒤 lipo 로 합친다. 로컬 개발에서 빌드 시간을 줄이려면 PTB_NATIVE_ARCH_ONLY=1.
ARCHS=(arm64 x86_64)
if [[ "${PTB_NATIVE_ARCH_ONLY:-0}" == "1" ]]; then
    [[ "${PTB_REQUIRE_STABLE_SIGN:-0}" == "1" ]] && { echo "   ✗ 릴리스 빌드는 PTB_NATIVE_ARCH_ONLY 를 쓸 수 없다 (universal 필수)." >&2; exit 1; }
    ARCHS=("$(uname -m)")
fi
SLICES=()
for arch in "${ARCHS[@]}"; do
    echo "==> swift build -c release --arch $arch"
    swift build -c release --arch "$arch"
    SLICES+=("$(swift build -c release --arch "$arch" --show-bin-path)/PokeTokenBar")
done

echo "==> $APP 조립"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
lipo "$APP/Contents/MacOS/$APP_NAME" -verify_arch "${ARCHS[@]}"
echo "   archs: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
# 심볼 strip — 릴리스 바이너리 1.84MB → 0.80MB(-57%). codesign 전에 수행(서명 무효화 방지).
strip -rSTx "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || strip -rSx "$APP/Contents/MacOS/$APP_NAME"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.chattymin.poketokenbar</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>PTBCommitSHA</key><string>$GIT_COMMIT_SHA</string>
    <key>PTBCommitDate</key><string>$GIT_COMMIT_DATE</string>
    <key>PTBCommitTime</key><string>$GIT_COMMIT_TIME</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# The SMAppService agent of the builds before. The app now writes its own LaunchAgent plist (LoginItem); this one
# stays in the bundle so the old registration can still be found and removed.
mkdir -p "$APP/Contents/Library/LaunchAgents"
cat > "$APP/Contents/Library/LaunchAgents/io.github.chattymin.poketokenbar.login.plist" <<AGENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>io.github.chattymin.poketokenbar.login</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
AGENT

echo "==> codesign"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-PokeTokenBar Local}"
# 안정적 Keychain ACL 을 위해서는 인증서 존재가 아니라 유효한 codesigning identity 가 필요하다.
if security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
    # 안정적 자체 서명 신원 → 재빌드해도 Keychain "항상 허용" 유지
    codesign --force -s "$SIGN_IDENTITY" "$APP"
else
    # 인증서 없음 → ad-hoc (빌드마다 cdhash 변경 = Keychain 재프롬프트 가능)
    if [[ "${PTB_REQUIRE_STABLE_SIGN:-0}" == "1" ]]; then
        # 릴리스 경로(release.sh 가 세팅). ad-hoc 릴리스는 사용자 Keychain 승인을 깨므로 절대 금지.
        echo "   ✗ PTB_REQUIRE_STABLE_SIGN=1 인데 '$SIGN_IDENTITY' 유효 identity 없음 → ad-hoc 금지, 중단." >&2
        echo "     ./scripts/create-signing-cert.sh 실행 후 다시 시도하세요." >&2
        exit 1
    fi
    echo "   ('$SIGN_IDENTITY' 유효 codesigning identity 없음 → ad-hoc 서명 — 로컬 개발용)"
    echo "   반복 Keychain 허용 프롬프트를 줄이려면 ./scripts/create-signing-cert.sh 실행 후 다시 빌드하세요."
    codesign --force -s - "$APP"
fi

echo "==> 기존 인스턴스 종료 + /Applications 설치"
# Copied and checked next to the installed app before anything is quit, then swapped in: a full disk or a
# permission error used to leave the player with the app quit and deleted, and no message.
DEST="/Applications/$APP_NAME.app"
STAGED="/Applications/.$APP_NAME.app.new"
PREVIOUS="/Applications/.$APP_NAME.app.old"
rm -rf "$STAGED" "$PREVIOUS"
if ! cp -R "$APP" "$STAGED" || ! codesign --verify "$STAGED"; then
    rm -rf "$STAGED"
    echo "   ✗ copy to /Applications failed, the installed app is untouched" >&2
    exit 1
fi
# SIGTERM asks the app to quit, and it ends as a Quit does (its crash marker cleaned). One that does not within ten
# seconds (a hung main thread) is killed.
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "PokeTokenBar" 2>/dev/null || true
for _ in $(seq 1 20); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -x "PokeTokenBar" >/dev/null 2>&1 || break
    sleep 0.5
done
pkill -9 -x "$APP_NAME" 2>/dev/null || true
pkill -9 -x "PokeTokenBar" 2>/dev/null || true
if [[ -d "$DEST" ]] && ! mv "$DEST" "$PREVIOUS"; then
    rm -rf "$STAGED"
    echo "   ✗ could not move the installed app aside, left as it was" >&2
    exit 1
fi
if ! mv "$STAGED" "$DEST"; then
    [[ -d "$PREVIOUS" ]] && mv "$PREVIOUS" "$DEST"
    echo "   ✗ install failed, the previous app is back" >&2
    exit 1
fi
rm -rf "$PREVIOUS"

echo "완료: open /Applications/$APP_NAME.app"
