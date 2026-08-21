{
  lib,
  stdenv,
  fetchurl,
  buildNpmPackage,
  python3,
}:

let
  version = "0.1.1-rc.1";
  srcHash = "sha256-xYweNYQZyJB8u2rbQwZcPB6CQEJImrCtkX6V4KBBgFY=";
  npmDepsHash = "sha256-Msnyw7AstXPh8NSKfPMGfEpBZVydSqnnAbS3duEDi0A=";
in
buildNpmPackage {
  pname = "deepseek-harness";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
    hash = srcHash;
  };

  # The npm tarball unpacks to a single `package/` directory.
  sourceRoot = "package";

  # The published tarball ships no lockfile; vendor one so `npm ci` can
  # resolve the full dependency closure offline.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  inherit npmDepsHash;

  # The npm package ships prebuilt JS (`lib/*.js`); nothing to compile.
  dontNpmBuild = true;

  # `npm rebuild` compiles native addons (node-pty). node-gyp needs a Python
  # interpreter and a C++ toolchain; buildNpmPackage already provides nodejs,
  # nodejs.python and the stdenv toolchain, this makes the interpreter
  # available explicitly.
  nativeBuildInputs = [ python3 ];

  # `dsh` boots the HMR service on every profile run, which needs access to
  # Node's internal module loader. It normally obtains that through the
  # `node-addon-require-builtin` native addon, but that addon is incompatible
  # with the Nix-packaged Node.js binary, so pass `--expose-internals` instead.
  postInstall = ''
    for bin in "$out"/bin/*; do
      [ -f "$bin" ] || continue
      sed -i 's|exec "\([^"]*node[^"]*\)"|exec "\1" --expose-internals|' "$bin"
    done
  '';

  meta = with lib; {
    description = "DeepSeek Harness (dsh): Everything is a Plugin";
    longDescription = ''
      DeepSeek Harness is an open-source agent harness with a plugin-based
      architecture. This package provides the `dsh` CLI, which can serve the
      browser UI via `dsh web`.
    '';
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = licenses.mit;
    mainProgram = "dsh";
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
  };
}
