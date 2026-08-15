{
  description = "Nix flake providing the deepseek-harness (dsh) package and a home-manager service module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
