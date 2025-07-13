{
  pkgs,
  lib,
  ...
}: {
  mkBaseKernel = {
    src,
    baseKernel ? pkgs.linux_6_6,
    version ? "6.6.36.3",
    extraConfig ? {},
    withZfs ? false,
    zfsPackage ? null,
  }: let
    configfile = let
      # Adapted from https://github.com/tpwrules/nixos-apple-silicon/blob/main/apple-silicon-support/packages/linux-asahi/default.nix
      # Parse CONFIG_<OPT>=[ymn]|"foo" style configuration as found in a config file
      parseLine = builtins.match ''(CONFIG_[[:upper:][:digit:]_]+)=(([ymn])|"([^"]*)")'';
      tristateMap = with lib.kernel; {
        "y" = yes;
        "m" = module;
        "n" = no;
      };
      # Get either the tristate ([ymn]) option or the freeform ("foo") option
      makeNameValuePair = match: let
        name = builtins.elemAt match 0;
        tristateValue = builtins.elemAt match 2;
        freeformValue = builtins.elemAt match 3;
        value =
          if tristateValue != null
          then tristateMap.${tristateValue}
          else lib.kernel.freeform freeformValue;
      in
        lib.nameValuePair name value;
      parseConfig = config: let
        lines = lib.strings.splitString "\n" config;
        matches = builtins.filter (match: match != null) (map parseLine lines);
      in
        map makeNameValuePair matches;

      baseConfigfile = "${src}/Microsoft/config-wsl";
      baseConfig = builtins.listToAttrs (parseConfig (builtins.readFile baseConfigfile));
      # Update with extraConfig
      config = baseConfig // extraConfig;
      configAttrToText = name: value: let
        string_value =
          if (builtins.hasAttr "freeform" value)
          then "\"${value.freeform}\""
          else value.tristate;
      in "${name}=${string_value}";
    in
      pkgs.writeText "config" ''
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList configAttrToText config)}
      '';

    kernel = pkgs.linuxManualConfig {
      inherit configfile src version;
      modDirVersion = baseKernel.version;

      allowImportFromDerivation = true;
    };

    # Validate ZFS compatibility if ZFS is requested
    zfsValidation =
      if withZfs
      then
        assert lib.assertMsg (zfsPackage != null) "zfsPackage must be provided when withZfs is true";
        assert lib.assertMsg (!(zfsPackage.meta.broken or false)) "ZFS package is marked as broken for this kernel version"; true
      else true;
  in
    assert zfsValidation;
      kernel
      // {
        passthru =
          kernel.passthru
          // {
            inherit withZfs zfsPackage;
            zfsCompatible = withZfs && zfsValidation;
          };
      };
}
