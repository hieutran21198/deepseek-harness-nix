{
  lib,
  stdenv,
  rustPlatform,
  deepseek-harness,
  pkg-config,
  makeWrapper,
  librsvg,
  # Linux deps (absent on macOS; `? null` lets callPackage skip them there)
  webkitgtk_4_1 ? null,
  gtk3 ? null,
  libsoup_3 ? null,
  libayatana-appindicator ? null,
  openssl ? null,
  glib-networking ? null,
  # macOS deps
  libicns ? null,
}:

let
  isDarwin = stdenv.hostPlatform.isDarwin;

  icon = ../../assets/deepseek-harness.svg;
in
rustPlatform.buildRustPackage {
  pname = "deepseek-harness-desktop";
  version = "0.1.0";

  src = ./src-tauri;

  cargoHash = "sha256-dcDNztCLSpDnOd1L1zFtwdXPxYJT71ocVioNXB1KOqo=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    librsvg
  ]
  ++ lib.optionals isDarwin [ libicns ];

  # On macOS the Apple SDK (and its frameworks) come from the Darwin stdenv, so
  # no extra build inputs are required; the `-framework` flags emitted by the
  # Tauri/webview crates resolve via SDKROOT automatically.
  buildInputs = lib.optionals (!isDarwin) [
    webkitgtk_4_1
    gtk3
    libsoup_3
    libayatana-appindicator
    openssl
    glib-networking
  ];
  # tauri-build validates that every icon listed in tauri.conf.json exists, so
  # render them from the vendored SVG before `cargo build` runs build.rs.
  preBuild = ''
    mkdir -p icons
    rsvg-convert -w 32 -h 32 ${icon} -o icons/32x32.png
    rsvg-convert -w 128 -h 128 ${icon} -o icons/128x128.png
    rsvg-convert -w 256 -h 256 ${icon} -o icons/128x128@2x.png
    rsvg-convert -w 256 -h 256 ${icon} -o icons/icon.png
    ${lib.optionalString isDarwin ''
      rsvg-convert -w 512 -h 512 ${icon} -o icons/512x512.png
      png2icns icons/icon.icns icons/512x512.png icons/128x128@2x.png icons/128x128.png icons/32x32.png
    ''}
  '';

  postInstall = ''
    wrapProgram "$out/bin/deepseek-harness-desktop" \
      --set DSH_BIN "${deepseek-harness}/bin/dsh" \
      ${lib.optionalString (!isDarwin) "--set WEBKIT_DISABLE_DMABUF_RENDERER 1"}

    ${lib.optionalString isDarwin ''
        app="$out/Applications/DeepSeek Harness.app"
        mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
        ln -s "$out/bin/deepseek-harness-desktop" "$app/Contents/MacOS/deepseek-harness-desktop"
        cp icons/icon.icns "$app/Contents/Resources/icon.icns"
        cat > "$app/Contents/Info.plist" <<EOF
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleName</key><string>DeepSeek Harness</string>
        <key>CFBundleDisplayName</key><string>DeepSeek Harness</string>
        <key>CFBundleIdentifier</key><string>org.deepseek.harness</string>
        <key>CFBundleExecutable</key><string>deepseek-harness-desktop</string>
        <key>CFBundleIconFile</key><string>icon.icns</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleVersion</key><string>0.1.0</string>
        <key>CFBundleShortVersionString</key><string>0.1.0</string>
        <key>LSMinimumSystemVersion</key><string>10.13</string>
        <key>NSHighResolutionCapable</key><true/>
      </dict>
      </plist>
      EOF
    ''}
  '';

  meta = with lib; {
    description = "DeepSeek Harness native desktop window (Tauri)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    mainProgram = "deepseek-harness-desktop";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
