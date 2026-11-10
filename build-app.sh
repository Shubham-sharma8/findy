#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Findy"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "==> Building ${APP_NAME} (Release)..."
swift build -c release

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "Assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp "Sources/Findy/Resources/Logo.png" "${APP_BUNDLE}/Contents/Resources/Logo.png"

if [ -d "${BUILD_DIR}/Findy_Findy.bundle" ]; then
    cp -R "${BUILD_DIR}/Findy_Findy.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi

printf "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Findy</string>
    <key>CFBundleExecutable</key>
    <string>Findy</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>app.findy.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Findy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>20</string>
    <key>LSCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Findy Contributors. Released under the MIT License.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Findy needs access to your Desktop folder to browse, search, and organize your files.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Findy needs access to your Documents folder to browse, search, and organize your files.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Findy needs access to your Downloads folder to browse, search, and clean up downloaded files.</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "${APP_BUNDLE}"
echo "==> Built and signed ${APP_BUNDLE} successfully."

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing ${APP_BUNDLE} to /Applications/${APP_BUNDLE}..."
    rm -rf "/Applications/${APP_BUNDLE}"
    cp -R "${APP_BUNDLE}" "/Applications/${APP_BUNDLE}"
    echo "==> Installed to /Applications/${APP_BUNDLE}"
fi
