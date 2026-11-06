#!/bin/bash
set -e

APP_NAME="bloom"
APPDIR="${PWD}/${APP_NAME}.AppDir"
INSTALL_PREFIX="${PWD}/appimage-staging"

rm -rf "$INSTALL_PREFIX"
meson setup build --prefix="$INSTALL_PREFIX" --reconfigure
meson compile -C build
meson install -C build

BINARY="$INSTALL_PREFIX/bin/$APP_NAME"

if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY"
    exit 1
fi

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/glib-2.0/schemas"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$APPDIR/usr/share/applications"

cp "$BINARY" "$APPDIR/usr/bin/"
chmod +x "$APPDIR/usr/bin/$APP_NAME"

ldd "$BINARY" | grep "=> /" | awk '{print $3}' | while read -r lib; do
    if [[ "$lib" =~ ^/(lib|lib64|usr/lib/x86_64-linux-gnu)/(libc|libm|libdl|libpthread|librt|ld-linux) ]]; then
        continue
    fi
    cp -L "$lib" "$APPDIR/usr/lib/" 2>/dev/null || true
done

if [ -d "$INSTALL_PREFIX/share/glib-2.0/schemas" ]; then
    cp "$INSTALL_PREFIX/share/glib-2.0/schemas/"*.xml "$APPDIR/usr/share/glib-2.0/schemas/" 2>/dev/null || true
fi

cp /usr/share/glib-2.0/schemas/*.xml "$APPDIR/usr/share/glib-2.0/schemas/" 2>/dev/null || true
glib-compile-schemas "$APPDIR/usr/share/glib-2.0/schemas/"

cp "$INSTALL_PREFIX/share/icons/hicolor/scalable/apps/"*.svg \
   "$APPDIR/usr/share/icons/hicolor/scalable/apps/" 2>/dev/null || true
cp "$INSTALL_PREFIX/share/applications/"*.desktop \
   "$APPDIR/usr/share/applications/" 2>/dev/null || true

cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export GSETTINGS_SCHEMA_DIR="${HERE}/usr/share/glib-2.0/schemas"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec "${HERE}/usr/bin/bloom" "$@"
EOF
chmod +x "$APPDIR/AppRun"

cp "$APPDIR/usr/share/applications/"*.desktop "$APPDIR/" 2>/dev/null || true
cp "$APPDIR/usr/share/icons/hicolor/scalable/apps/"*.svg "$APPDIR/" 2>/dev/null || true

if [ -f "./appimagetool" ]; then
    APPIMAGETOOL="./appimagetool"
elif command -v appimagetool >/dev/null 2>&1; then
    APPIMAGETOOL="appimagetool"
else
    wget -O appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool
    APPIMAGETOOL="./appimagetool"
fi

ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "bloom-x86_64.AppImage"