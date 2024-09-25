{
  description = "Nix flake CI template for GitHub Actions";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    flake-utils.url = "github:numtide/flake-utils";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , pre-commit-hooks
    , flake-utils
    , ...
    }:
    let
      supportedSystems = [
        # "aarch64-linux" # TODO: Test on ARM64 Windows?
        "x86_64-linux"
      ];
    in
    flake-utils.lib.eachSystem supportedSystems
      (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = self;
          hooks = {
            nixpkgs-fmt.enable = true;
            editorconfig-checker.enable = true;
            markdownlint.enable = true;
          };
        };

        devShell = pkgs.mkShell {
          name = "devShell";
          inherit (pre-commit-check) shellHook;
          buildInputs = with pkgs;
            [
              zlib
            ]
            ++ self.checks.${system}.formatting.enabledPackages;
        };
      in
      {
        devShells = {
          default = devShell;
        };

        packages = rec {
          wsl-linux-kernel = pkgs.callPackage ./wsl2-linux-kernel.nix { };
          default = wsl-linux-kernel;
        };

        checks = {
          formatting = pre-commit-check;
        };
      }) // {
      overlays.default = final: prev: {
        inherit (nixpkgs.legacyPackages.${final.system}) hello; # Dummy for now.
      };
    };
}
