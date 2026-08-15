{
  description = "Nix flake providing the deepseek-harness (dsh) package and a home-manager service module";

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
      # the module (including declarative `settings`) evaluates and builds.
      exampleHomeConfig =
        system:
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
    in
    {
      packages = forAllSystems (
        system:
        let
          deepseek-harness = mkPackage system;
        in
        {
          default = deepseek-harness;
          deepseek-harness = deepseek-harness;
        }
      );

      checks = forAllSystems (system: {
        home-config = (exampleHomeConfig system).activationPackage;
      });

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
          };
        deepseek-harness =
          { pkgs, lib, ... }:
          {
            imports = [ (import ./modules/deepseek-harness.nix) ];
            services.deepseek-harness.package = lib.mkDefault (
              self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness
            );
          };
      };
    };
}
