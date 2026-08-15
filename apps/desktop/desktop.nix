{
  lib,
  stdenv,
  rustPlatform,
  deepseek-harness,
  pkg-config,
  makeWrapper,
  librsvg,
  webkitgtk_4_1,
  gtk3,
  libsoup_3,
  libayatana-appindicator,
  openssl,
  glib-networking,
}:

rustPlatform.buildRustPackage {
  pname = "deepseek-harness-desktop";
  version = "0.1.0";

  src = ./src-tauri;

  # Placeholder; the real hash is filled in from the build error.
  cargoHash = "sha256-dcDNztCLSpDnOd1L1zFtwdXPxYJT71ocVioNXB1KOqo=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    librsvg
  ];

  buildInputs = [
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
    rsvg-convert -w 32 -h 32 ${../../assets/deepseek-harness.svg} -o icons/32x32.png
    rsvg-convert -w 128 -h 128 ${../../assets/deepseek-harness.svg} -o icons/128x128.png
    rsvg-convert -w 256 -h 256 ${../../assets/deepseek-harness.svg} -o icons/128x128@2x.png
    rsvg-convert -w 256 -h 256 ${../../assets/deepseek-harness.svg} -o icons/icon.png
  '';

  postInstall = ''
    wrapProgram "$out/bin/deepseek-harness-desktop" \
      --set DSH_BIN "${deepseek-harness}/bin/dsh" \
      --set WEBKIT_DISABLE_DMABUF_RENDERER 1
  '';

  meta = with lib; {
    description = "DeepSeek Harness native desktop window (Tauri)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    mainProgram = "deepseek-harness-desktop";
    platforms = platforms.linux;
  };
}
