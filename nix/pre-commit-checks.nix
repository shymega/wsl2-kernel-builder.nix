{
  system,
  inputs,
  lib,
  ...
}:
inputs.git-hooks.lib.${system}.run {
  src = lib.cleanSource ./.;
  hooks = {
    nixpkgs-fmt.enable = true;
    editorconfig-checker.enable = true;
    markdownlint.enable = true;
    deadnix.enable = true;
    statix.enable = true;
    prettier.enable = true;
    yamlfmt.enable = true;
    actionlint.enable = true;
  };
}
