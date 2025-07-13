{pkgs, ...}: {
  package = pkgs.treefmt;
  projectRootFile = "flake.nix";

  settings = {
    shellcheck.includes = [
      "*"
      ".envrc"
    ];
  };
  programs = {
    deadnix.enable = true;
    statix.enable = true;
    nixpkgs-fmt.enable = true;
    prettier.enable = true;
    yamlfmt.enable = true;
    jsonfmt.enable = true;
    mdformat.enable = true;
    actionlint.enable = true;
  };
}
