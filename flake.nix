{
  description = "Nix flake providing the deepseek-harness (dsh) package plus NixOS and home-manager service modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://deepseek-harness-flake.cachix.org" ];
    extra-trusted-public-keys = [
      "deepseek-harness-flake.cachix.org-1:X/nyJkoKMvswHStf5hwikOPJRmD9aobzJDqQCLpqqMA="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPackage = system: (import nixpkgs { inherit system; }).callPackage ./package.nix { };

      # A sample home-manager configuration used by `checks` to validate that
      # the module (including declarative `settings` and, on Linux, the
      # desktop app) evaluates and builds.
      exampleHomeConfig =
        system: enableDesktop:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit system; };
          modules = [
            self.homeManagerModules.default
            {
              home.username = "dsh-test";
              home.homeDirectory = "/home/dsh-test";
              home.stateVersion = "25.05";
              services.deepseek-harness = {
                enable = true;
                desktop.enable = enableDesktop;
                settings = {
                  models = {
                    provider = "deepseek";
                    apiKey = "DEEPSEEK_API_KEY";
                  };
                  telemetry = {
                    mode = "off";
                  };
                };
              };
            }
          ];
        };

      # A minimal NixOS evaluation used by `checks` to validate the
      # nixosModules entry. Only a lightweight attribute is forced so the
      # check stays cheap (forcing the whole `toplevel` closure is slow).
      exampleNixosConfig =
        system:
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.default
            {
              boot.isContainer = true;
              system.stateVersion = "25.05";
              services.deepseek-harness = {
                enable = true;
                settings = {
                  models = {
                    provider = "deepseek";
                    apiKey = "DEEPSEEK_API_KEY";
                  };
                };
              };
            }
          ];
        }).config.systemd.services.deepseek-harness.serviceConfig.ExecStart;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          deepseek-harness = mkPackage system;
        in
        {
          default = deepseek-harness;
          deepseek-harness = deepseek-harness;
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-linux" system) {
          deepseek-harness-desktop = pkgs.callPackage ./apps/desktop/desktop.nix {
            inherit deepseek-harness;
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          home-config = (exampleHomeConfig system false).activationPackage;
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-linux" system) {
          home-config-desktop = (exampleHomeConfig system true).activationPackage;
          nixos-config = pkgs.runCommand "deepseek-harness-nixos-module-check" { } ''
            # Forces the NixOS module to evaluate (without building a full system).
            printf '%s\n' ${nixpkgs.lib.escapeShellArg (toString (exampleNixosConfig system))} > "$out"
          '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.nodejs_24
              pkgs.prefetch-npm-deps
              pkgs.jq
            ];
          };
        }
      );

      homeManagerModules = {
        default =
          { pkgs, lib, ... }:
          {
            imports = [ (import ./modules/deepseek-harness.nix) ];
            services.deepseek-harness.package = lib.mkDefault (
              self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness
            );
            services.deepseek-harness.desktop.package =
              lib.mkIf (lib.hasSuffix "-linux" pkgs.stdenv.hostPlatform.system)
                (lib.mkDefault (self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness-desktop));
          };
        deepseek-harness =
          { pkgs, lib, ... }:
          {
            imports = [ (import ./modules/deepseek-harness.nix) ];
            services.deepseek-harness.package = lib.mkDefault (
              self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness
            );
            services.deepseek-harness.desktop.package =
              lib.mkIf (lib.hasSuffix "-linux" pkgs.stdenv.hostPlatform.system)
                (lib.mkDefault (self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness-desktop));
          };
      };

      nixosModules = {
        default =
          { pkgs, lib, ... }:
          {
            imports = [ (import ./modules/nixos/deepseek-harness.nix) ];
            services.deepseek-harness.package = lib.mkDefault (
              self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness
            );
          };
        deepseek-harness =
          { pkgs, lib, ... }:
          {
            imports = [ (import ./modules/nixos/deepseek-harness.nix) ];
            services.deepseek-harness.package = lib.mkDefault (
              self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness
            );
          };
      };
    };
}
