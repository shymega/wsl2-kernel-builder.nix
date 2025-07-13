{
  description = "[WIP] Nix Flake for building WSL2 kernels (arm64/x86_64)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs: let
    supportedSystems = [
      # "aarch64-linux" # TODO: Test on ARM64 Windows?
      "x86_64-linux"
    ];
  in
    flake-utils.lib.eachSystem supportedSystems
    (system: let
      pkgs = import nixpkgs {
        inherit system;
      };

      kernelResolver = import ./nix/kernel-version-resolver.nix {
        inherit pkgs;
        lib = nixpkgs.lib;
        fetchFromGitHub = pkgs.fetchFromGitHub;
      };

      devShell = pkgs.mkShell {
        name = "devShell";
        inherit (self.checks.${system}.pre-commit-checks) shellHook;
        buildInputs = with pkgs;
          [
            zlib
          ]
          ++ self.checks.${system}.pre-commit-checks.enabledPackages;
      };
    in {
      devShells = {
        default = devShell;
      };

      packages = builtins.listToAttrs (
        builtins.concatMap (kernelInfo: [
          # Base kernel package
          {
            name = "wsl2-linux-kernel-${nixpkgs.lib.strings.replaceStrings ["linux-msft-wsl-"] [""] kernelInfo.tag}-base";
            value = (pkgs.callPackage ./packages/wsl2-linux-kernel-base {}).mkBaseKernel {
              src = pkgs.fetchFromGitHub {
                owner = "Microsoft";
                repo = "WSL2-Linux-Kernel";
                rev = kernelInfo.tag;
                sha256 = kernelInfo.sha256;
              };
              version = nixpkgs.lib.strings.replaceStrings ["linux-msft-wsl-"] [""] kernelInfo.tag;
              baseKernel = kernelResolver.zfsCompatibilityMatrix.${kernelInfo.majorMinor}.nixpkgsKernel or null;
            };
          }
          # ZFS kernel package
          {
            name = "wsl2-linux-kernel-${nixpkgs.lib.strings.replaceStrings ["linux-msft-wsl-"] [""] kernelInfo.tag}-with-zfs";
            value = pkgs.callPackage ./packages/wsl2-linux-kernel-with-zfs {
              preferredKernelTag = kernelInfo.tag;
              allowFallback = false; # We are explicitly building for this tag
            };
          }
        ]) kernelResolver.knownWorkingKernels
      );
      # for `nix fmt`
      formatter = (inputs.treefmt-nix.lib.evalModule pkgs ./nix/formatter.nix).config.build.wrapper;
      # for `nix flake check`
      checks =
        {
          formatting = (inputs.treefmt-nix.lib.evalModule pkgs ./nix/formatter.nix).config.build.wrapper;
        }
        // {
          pre-commit-checks = import ./nix/pre-commit-checks.nix {
            inherit
              self
              system
              inputs
              ;
            inherit (nixpkgs) lib;
          };
        };
    });
}
