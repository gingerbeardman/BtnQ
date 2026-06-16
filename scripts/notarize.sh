#!/bin/bash
set -e

# BtnQ Notarization Script
#
# Prerequisites:
#   1. Developer ID Application certificate installed
#   2. Keychain profile created via:
#      xcrun notarytool store-credentials "notarytool-password" \
#        --apple-id "your-email@example.com" \
#        --team-id "Q3Z639YB49" \
#        --password "xxxx-xxxx-xxxx-xxxx"

# Configuration
PROJECT_NAME="Didact"
APP_NAME="Didact"
SCHEME="Didact"
CONFIGURATION="Release"
KEYCHAIN_PROFILE="notarytool-password"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_step()    { echo -e "\n${GREEN}▶ $1${NC}"; }
print_error()   { echo -e "${RED}✖ $1${NC}"; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }

check_prerequisites() {
    print_step "Checking prerequisites..."
    if ! command -v xcodebuild &> /dev/null; then
        print_error "xcodebuild not found. Install Xcode Command Line Tools."; exit 1
    fi
    if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &> /dev/null; then
        print_error "Keychain profile '$KEYCHAIN_PROFILE' not found."
        echo "Create it with:"
        echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
        echo "    --apple-id \"your-email@example.com\" \\"
        echo "    --team-id \"Q3Z639YB49\" \\"
        echo "    --password \"xxxx-xxxx-xxxx-xxxx\""
        exit 1
    fi
    if [[ ! -f "$PROJECT_DIR/ExportOptions.plist" ]]; then
        print_error "ExportOptions.plist not found in project root."; exit 1
    fi
    print_success "Prerequisites OK"
}

clean_build() {
    print_step "Cleaning previous build..."
    rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
    print_success "Clean complete"
}

archive_app() {
    print_step "Archiving app..."
    xcodebuild -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -archivePath "$ARCHIVE_PATH" archive \
        | grep -E "^(Archive|error:|warning:|\*\*)" || true
    [[ -d "$ARCHIVE_PATH" ]] || { print_error "Archive failed"; exit 1; }
    print_success "Archive complete: $ARCHIVE_PATH"
}

export_app() {
    print_step "Exporting app with Developer ID signing..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
        | grep -E "^(Export|error:|warning:|\*\*)" || true
    [[ -d "$APP_PATH" ]] || { print_error "Export failed"; exit 1; }
    print_success "Export complete: $APP_PATH"
}

notarize_zip() {
    print_step "Notarizing app (this may take a few minutes)..."
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    print_success "App notarized and stapled"
}

create_dmg() {
    print_step "Creating DMG..."
    rm -f "$DMG_PATH"
    local stage="$BUILD_DIR/dmg"
    rm -rf "$stage"; mkdir -p "$stage"
    # HFS+ (decmpfs) compress the app: it survives into the DMG (smaller download)
    # and through a Finder/NSFileManager drag-install (smaller on disk). Transparent,
    # so the code signature and stapled ticket are unaffected.
    ditto --hfsCompression "$APP_PATH" "$stage/$APP_NAME.app"
    ln -s /Applications "$stage/Applications"   # drag-to-install
    hdiutil create -volname "$APP_NAME" -srcfolder "$stage" -ov -format UDZO "$DMG_PATH"
    rm -rf "$stage"
    print_success "DMG created: $DMG_PATH"

    print_step "Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    print_success "DMG notarized and stapled"
}

verify_build() {
    print_step "Verifying notarization..."
    echo "App:"; spctl -a -v "$APP_PATH" 2>&1 || true
    echo "DMG:"; spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1 || true
    print_success "Verification complete"
}

main() {
    echo "========================================="
    echo "  $PROJECT_NAME Notarization Script"
    echo "========================================="
    cd "$PROJECT_DIR"
    check_prerequisites
    clean_build
    archive_app
    export_app
    notarize_zip
    create_dmg
    verify_build
    echo ""
    print_success "Build complete!"
    echo "  App: $APP_PATH"
    echo "  DMG: $DMG_PATH"
}

main "$@"
