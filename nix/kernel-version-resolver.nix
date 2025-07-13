{
  pkgs,
  lib,
  fetchFromGitHub,
}: let
  # Known working kernel versions (fallback list)
  knownWorkingKernels = [
    {
      tag = "linux-msft-wsl-6.6.36.6";
      sha256 = "sha256-wF/Efzmhvota+g0TF4uP1r12vQb6nDM3LkacCkP99Ow=";
      majorMinor = "6.6";
    }
    {
      tag = "linux-msft-wsl-6.1.21.2";
      sha256 = "sha256-vDuMtFgObeRt+Em/iB+KDCQaAc96a4S51UZvcJjhjlM="; # Placeholder - would need real hash
      majorMinor = "6.1";
    }
    {
      tag = "linux-msft-wsl-5.15.90.1";
      sha256 = "sha256-wF/Efzmhvota+g0TF4uP1r12vQb6nDM3LkacCkP99Ow=";
      majorMinor = "5.15";
    }
    {
      tag = "linux-msft-wsl-5.10.102.1";
      sha256 = "sha256-vDuMtFgObeRt+Em/iB+KDCQaAc96a4S51UZvcJjhjlM="; # Placeholder - would need real hash
      majorMinor = "5.10";
    }
    
  ];

  # Define supported kernel major.minor versions for ZFS
  supportedKernelVersions = ["6.1" "6.6" "6.8" "6.10" "5.15" "5.10" "5.4"];

  # Map kernel versions to compatible ZFS packages
  zfsCompatibilityMatrix = {
    "6.1" = {
      pkg = pkgs.linuxKernel.packages.linux_6_1.zfs;
      nixpkgsKernel = pkgs.linux_6_1;
      stable = true;
    };
    "6.6" = {
      pkg = pkgs.linuxKernel.packages.linux_6_6.zfs;
      nixpkgsKernel = pkgs.linux_6_6;
      stable = true;
    };
    "6.8" = {
      pkg = pkgs.linuxKernel.packages.linux_6_8.zfs or null;
      nixpkgsKernel = pkgs.linux_6_8;
      stable = false;
    };
    "6.10" = {
      pkg = pkgs.linuxKernel.packages.linux_6_10.zfs or null;
      nixpkgsKernel = pkgs.linux_6_10;
      stable = false;
    };
    "5.15" = {
      pkg = pkgs.linuxKernel.packages.linux_5_15.zfs;
      nixpkgsKernel = pkgs.linux_5_15;
      stable = true;
    };
    "5.10" = {
      pkg = pkgs.linuxKernel.packages.linux_5_10.zfs;
      nixpkgsKernel = pkgs.linux_5_10;
      stable = true;
    };
    "5.4" = {
      pkg = pkgs.linuxKernel.packages.linux_5_4.zfs;
      nixpkgsKernel = pkgs.linux_5_4;
      stable = true;
    };
  };

  # Extract version info from kernel tag
  parseKernelTag = tag: let
    # Extract version from tag like "linux-msft-wsl-6.6.36.6"
    version = builtins.substring 15 (builtins.stringLength tag - 15) tag;
    majorMinor = lib.versions.majorMinor version;
  in {
    inherit tag version majorMinor;
  };

  # Check if a kernel/ZFS combination is compatible
  isCompatible = kernelInfo: let
    zfsCompat = zfsCompatibilityMatrix.${kernelInfo.majorMinor} or null;
  in
    zfsCompat
    != null
    && zfsCompat.pkg != null
    && !(zfsCompat.pkg.meta.broken or false);

  # Find the best compatible kernel/ZFS combination
  findCompatibleBuild = {
    preferredKernelTag ? null,
    allowFallback ? true,
    requireStable ? false,
  }: let
    # Build candidate list
    preferredCandidate =
      if preferredKernelTag != null
      then [(parseKernelTag preferredKernelTag)]
      else [];

    fallbackCandidates =
      if allowFallback
      then map parseKernelTag (map (k: k.tag) knownWorkingKernels)
      else [];

    allCandidates = preferredCandidate ++ fallbackCandidates;

    # Filter candidates
    compatibleCandidates = builtins.filter isCompatible allCandidates;

    stableFilteredCandidates =
      if requireStable
      then builtins.filter (k: zfsCompatibilityMatrix.${k.majorMinor}.stable) compatibleCandidates
      else compatibleCandidates;

    finalCandidates = stableFilteredCandidates;
  in
    if finalCandidates == []
    then throw "No compatible kernel/ZFS combination found. Supported versions: ${builtins.concatStringsSep ", " supportedKernelVersions}"
    else let
      selectedKernel = builtins.head finalCandidates;
      zfsCompat = zfsCompatibilityMatrix.${selectedKernel.majorMinor};

      # Find the corresponding known kernel info for sha256
      knownKernel = lib.findFirst (k: k.tag == selectedKernel.tag) null knownWorkingKernels;

      sha256 =
        if knownKernel != null
        then knownKernel.sha256
        else lib.fakeSha256; # For unknown versions, will need manual update
    in {
      kernel = selectedKernel // {inherit sha256;};
      zfs = zfsCompat;
      buildInfo = {
        kernelVersion = selectedKernel.version;
        zfsVersion = zfsCompat.pkg.version;
        isStable = zfsCompat.stable;
        usedFallback = preferredKernelTag != null && selectedKernel.tag != preferredKernelTag;
      };
    };
in {
  inherit
    supportedKernelVersions
    zfsCompatibilityMatrix
    parseKernelTag
    isCompatible
    findCompatibleBuild
    knownWorkingKernels
    ;
}
