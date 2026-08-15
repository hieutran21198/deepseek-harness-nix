# deepseek-harness-nix

Nix flake packaging [DeepSeek Harness (`dsh`)](https://github.com/deepseek-ai/deepseek-harness) — an open-source agent harness where "everything is a plugin" — and exposing it as a home-manager service module.

## What's provided

| Output | Description |
| --- | --- |
| `packages.<system>.deepseek-harness` | The `dsh` CLI, built from the published npm tarball via `buildNpmPackage`. |
| `packages.<system>.default` | Alias for the above. |
| `homeManagerModules.default` | Home-manager module defining `services.deepseek-harness`. |
| `homeManagerModules.deepseek-harness` | Same module under an explicit name. |
| `devShells.<system>.default` | Shell with `nodejs`, `prefetch-npm-deps`, and `jq` (for running the updater). |

Supported systems: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`. CI builds and caches `x86_64-linux` only.

## Standalone usage

```bash
nix run github:hieutran21198/deepseek-harness-nix -- web
```

Or add the flake and run the package:

```bash
nix shell github:hieutran21198/deepseek-harness-nix --command dsh web
```

The web UI is served at `http://127.0.0.1:3080` by default.

## Home-manager module

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deepseek-harness.url = "github:hieutran21198/deepseek-harness-nix";
  };

  outputs = { nixpkgs, home-manager, deepseek-harness, ... }: {
    homeConfigurations.cirius = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        deepseek-harness.homeManagerModules.default
        {
          services.deepseek-harness = {
            enable = true;
            # host = "127.0.0.1";
            # port = 3080;
            # dshHome = "/path/to/data";
            # trustedHosts = [ "localhost" ];
            # extraArgs = [ "--patch" "/path/to/overlay.yaml" ];
          };
        }
      ];
    };
  };
}
```

Then:

```bash
home-manager switch
systemctl --user start deepseek-harness   # Linux (systemd)
launchctl start deepseek-harness          # macOS (launchd)
```

The module manages:

- **`enable`** — enable the service (default: `false`).
- **`package`** — the `deepseek-harness` package (defaults to this flake's build).
- **`host`** — bind address (default: `"127.0.0.1"`).
- **`port`** — listen port, `0` lets the OS choose (default: `3080`).
- **`trustedHosts`** — extra authorities accepted by the `/api` browser-trust fence (default: `[]`).
- **`extraArgs`** — extra args passed through to `dsh web` (default: `[]`).
- **`dshHome`** — overrides `DSH_HOME`; `null` uses the harness default `~/.dsh` (default: `null`).

On Linux it creates a `systemd` user service; on macOS a `launchd` agent. Enabling it also adds `dsh` to `home.packages`.

## Binary cache

Builds are pushed to the [Cachix](https://cachix.org) cache `deepseek-harness-flake`, and the flake advertises it via `nixConfig`, so users pull prebuilt binaries transparently.

## Continuous integration

Two GitHub Actions workflows live under `.github/workflows/`:

- **`update.yml`** — runs hourly (and on `workflow_dispatch`). It polls the npm registry for a newer `@deepseek-ai/dsh`, regenerates `package-lock.json`, recomputes both SRI hashes, verifies the build, and commits/pushes to `main` if anything changed.
- **`build.yml`** — runs on push to `main`, pull requests, and daily. It builds `x86_64-linux` and pushes the result to Cachix.

### Required secrets

| Secret | Purpose |
| --- | --- |
| `CACHIX_AUTH_TOKEN` | Push access to the `deepseek-harness-flake` cache. |

## Updating manually

```bash
nix develop --command ./scripts/update.sh
```

The script exits `0` when the package is already up to date, and `1` on failure.

## Notes

- `dsh` boots an HMR service that needs access to Node's internal module loader. The bundled `node-addon-require-builtin` fallback is incompatible with the Nix-packaged Node.js, so the `dsh` wrapper runs with `--expose-internals`.
- `package-lock.json` and the two SRI hashes in `package.nix` are release-specific — they are updated together by `scripts/update.sh` whenever a new `dsh` release is published.

## License

MIT, matching the upstream [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) project.
