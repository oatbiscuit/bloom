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
mkdir -p "$APPDIR/usr/share/icons/hicolor/symbolic/apps"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/metainfo"

cp "$BINARY" "$APPDIR/usr/bin/"
chmod +x "$APPDIR/usr/bin/$APP_NAME"

ldd "$BINARY" | grep "=> /" | awk '{print $3}' | while read -r lib; do
    libname=$(basename "$lib")
    case "$libname" in
        libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|ld-linux*)
            continue
            ;;
    esac
    cp -L "$lib" "$APPDIR/usr/lib/" 2>/dev/null || true
done

if [ -d "$INSTALL_PREFIX/share/glib-2.0/schemas" ]; then
    cp "$INSTALL_PREFIX/share/glib-2.0/schemas/"*.xml "$APPDIR/usr/share/glib-2.0/schemas/" 2>/dev/null || true
fi
cp /usr/share/glib-2.0/schemas/*.xml "$APPDIR/usr/share/glib-2.0/schemas/" 2>/dev/null || true
glib-compile-schemas "$APPDIR/usr/share/glib-2.0/schemas/"

cp "$INSTALL_PREFIX/share/icons/hicolor/scalable/apps/"*.svg \
   "$APPDIR/usr/share/icons/hicolor/scalable/apps/" 2>/dev/null || true
cp "$INSTALL_PREFIX/share/icons/hicolor/symbolic/apps/"*.svg \
   "$APPDIR/usr/share/icons/hicolor/symbolic/apps/" 2>/dev/null || true

PIXBUF_MODULE_DIR="/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders"
PIXBUF_TARGET_DIR="$APPDIR/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"

mkdir -p "$PIXBUF_TARGET_DIR"

HOST_LOADERS="/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders"
if [ ! -d "$HOST_LOADERS" ]; then
    HOST_LOADERS=$(find /usr/lib -type d -name "loaders" -path "*gdk-pixbuf*" | head -n 1)
fi

if [ -n "$HOST_LOADERS" ] && [ -d "$HOST_LOADERS" ]; then
    cp "$HOST_LOADERS"/*.so "$PIXBUF_TARGET_DIR/" 2>/dev/null || true
else
    echo "Warning: Could not find gdk-pixbuf loaders on host."
fi

PIXBUF_QUERY=$(pkg-config --variable=gdk_pixbuf_query_loaders gdk-pixbuf-2.0 2>/dev/null || true)

if [ -z "$PIXBUF_QUERY" ] || [ ! -x "$PIXBUF_QUERY" ]; then
    PIXBUF_QUERY="/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders"
fi

if [ ! -x "$PIXBUF_QUERY" ]; then
    echo "Error: gdk-pixbuf-query-loaders not found."
    exit 1
fi

( cd "$PIXBUF_TARGET_DIR" && "$PIXBUF_QUERY" *.so > loaders.cache )
sed -i -E 's|"[^"]*/([^"/]+\.so)"|"\1"|g' "$PIXBUF_TARGET_DIR/loaders.cache"
echo "--- loaders.cache content ---"
head -5 "$PIXBUF_TARGET_DIR/loaders.cache"

if [ ! -s "$PIXBUF_TARGET_DIR/loaders.cache" ]; then
    echo "Error: loaders.cache is empty or missing!"
    exit 1
fi
echo "Successfully generated loaders.cache"

mkdir -p "$APPDIR/usr/share/icons"
cp -r /usr/share/icons/Adwaita "$APPDIR/usr/share/icons/" 2>/dev/null || true
if [ -d "$APPDIR/usr/share/icons/Adwaita" ]; then
    gtk4-update-icon-cache -q -t -f "$APPDIR/usr/share/icons/Adwaita" 2>/dev/null || true
fi

cp "$INSTALL_PREFIX/share/applications/"*.desktop \
   "$APPDIR/usr/share/applications/" 2>/dev/null || true
if [ -f "$INSTALL_PREFIX/share/metainfo/io.github.oatbiscuit.bloom.metainfo.xml" ]; then
    cp "$INSTALL_PREFIX/share/metainfo/io.github.oatbiscuit.bloom.metainfo.xml" \
       "$APPDIR/usr/share/metainfo/"
    cp "$APPDIR/usr/share/metainfo/io.github.oatbiscuit.bloom.metainfo.xml" \
       "$APPDIR/usr/share/metainfo/io.github.oatbiscuit.bloom.appdata.xml"
fi

cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export GSETTINGS_SCHEMA_DIR="${HERE}/usr/share/glib-2.0/schemas"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GDK_PIXBUF_MODULEDIR="${HERE}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"
export GDK_PIXBUF_MODULE_FILE="${HERE}/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/loaders.cache"
exec "${HERE}/usr/bin/bloom" "$@"
EOF

chmod +x "$APPDIR/AppRun"

cp "$APPDIR/usr/share/applications/"*.desktop "$APPDIR/" 2>/dev/null || true
if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 256 -h 256 \
        "$APPDIR/usr/share/icons/hicolor/scalable/apps/io.github.oatbiscuit.bloom.svg" \
        -o "$APPDIR/io.github.oatbiscuit.bloom.png"
elif command -v convert >/dev/null 2>&1; then
    convert -background none \
        "$APPDIR/usr/share/icons/hicolor/scalable/apps/io.github.oatbiscuit.bloom.svg" \
        -resize 256x256 "$APPDIR/io.github.oatbiscuit.bloom.png"
fi

if [ -f "$APPDIR/io.github.oatbiscuit.bloom.png" ]; then
    mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
    cp "$APPDIR/io.github.oatbiscuit.bloom.png" \
       "$APPDIR/usr/share/icons/hicolor/256x256/apps/"
    gtk4-update-icon-cache -q -t -f "$APPDIR/usr/share/icons/hicolor" 2>/dev/null || true
fi

rm -f "$APPDIR/usr/lib/libc.so.6" \
      "$APPDIR/usr/lib/libc.so" \
      "$APPDIR/usr/lib/libm.so.6" \
      "$APPDIR/usr/lib/libdl.so.2" \
      "$APPDIR/usr/lib/libpthread.so.0" \
      "$APPDIR/usr/lib/librt.so.1"

if [ -f "./appimagetool" ]; then
    APPIMAGETOOL="./appimagetool"
elif command -v appimagetool >/dev/null 2>&1; then
    APPIMAGETOOL="appimagetool"
else
    wget -O appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool
    APPIMAGETOOL="./appimagetool"
fi

ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "bloom-x86_64.AppImage"
