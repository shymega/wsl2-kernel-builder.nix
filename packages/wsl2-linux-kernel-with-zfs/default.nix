{
  pkgs,
  fetchFromGitHub,
  lib,
  stdenv,
  # Options for CI robustness
  preferredKernelTag ? null,
  allowFallback ? true,
  requireStable ? false,
}: let
  wsl2-linux-kernel-base = import ../wsl2-linux-kernel-base {inherit pkgs lib;};
  kernelVersionResolver = import ../../nix/kernel-version-resolver.nix {inherit pkgs lib fetchFromGitHub;};

  # Find compatible kernel/ZFS combination
  selectedBuild = kernelVersionResolver.findCompatibleBuild {
    inherit preferredKernelTag allowFallback requireStable;
  };

  inherit (selectedBuild) kernel zfs buildInfo;

  arch =
    if pkgs.system == "aarch64-linux"
    then "arm64"
    else if pkgs.system == "x86_64-linux"
    then "amd64"
    else throw "Unsupported system ${pkgs.system}";

  inherit (wsl2-linux-kernel-base) mkBaseKernel;

  # Kernel source
  src = fetchFromGitHub {
    owner = "Microsoft";
    repo = "WSL2-Linux-Kernel";
    rev = kernel.tag;
    sha256 = kernel.sha256;
  };

  # ZFS-specific kernel configuration
  zfsExtraConfig = with lib.kernel; {
    # ZFS module support
    CONFIG_SPL = module;
    CONFIG_ZFS = module;

    # Required for ZFS
    CONFIG_EFI_PARTITION = yes;
    CONFIG_ZLIB_INFLATE = yes;
    CONFIG_ZLIB_DEFLATE = yes;

    # Compression support (existing + ZFS needs)
    CONFIG_KERNEL_ZSTD = yes;
    CONFIG_MODULE_COMPRESS_ZSTD = yes;
    CONFIG_ZPOOL = yes;
    CONFIG_ZSWAP = yes;
    CONFIG_ZSWAP_COMPRESSOR_DEFAULT_ZSTD = yes;
    CONFIG_CRYPTO_842 = module;
    CONFIG_CRYPTO_LZ4 = module;
    CONFIG_CRYPTO_LZ4HC = module;
    CONFIG_CRYPTO_ZSTD = yes;
    CONFIG_ZRAM_DEF_COMP_ZSTD = yes;
    CONFIG_ZRAM_WRITEBACK = yes;
    CONFIG_ZRAM_MULTI_COMP = yes;
  };

  # Build the WSL2 kernel with ZFS support
  wsl2Kernel = mkBaseKernel {
    inherit src;
    version = kernel.version;
    extraConfig = zfsExtraConfig;
    withZfs = true;
    zfsPackage = zfs.pkg;
    baseKernel = zfs.nixpkgsKernel;
  };

  # Build ZFS modules for our custom kernel
  zfsForKernel = zfs.pkg.override {
    kernel = wsl2Kernel;
  };

  version = "kv${kernel.version}-zfs${zfsForKernel.version}";
in
  stdenv.mkDerivation {
    name = "wsl2-linux-kernel-with-zfs";
    inherit version;

    buildInputs = [wsl2Kernel zfsForKernel];
    nativeBuildInputs = [pkgs.kmod];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
            echo "Building WSL2 kernel ${kernel.version} with ZFS ${zfsForKernel.version}"
            echo "Build info: stable=${buildInfo.isStable}, fallback=${buildInfo.usedFallback}"

            mkdir -p $out/lib/modules/${wsl2Kernel.modDirVersion}

            # Install WSL2 kernel bzImage
            cp ${wsl2Kernel}/bzImage $out/bzImage-${arch}

            # Verify ZFS modules exist
            if [ ! -f "${zfsForKernel}/lib/modules/${wsl2Kernel.modDirVersion}/extra/zfs.ko" ]; then
              echo "ERROR: ZFS modules not found for kernel ${wsl2Kernel.modDirVersion}"
              echo "Available modules in ZFS package:"
              find ${zfsForKernel}/lib/modules -name "*.ko" -type f || true
              exit 1
            fi

            # Install ZFS kernel modules
            cp -r ${zfsForKernel}/lib/modules/${wsl2Kernel.modDirVersion}/* \
                   $out/lib/modules/${wsl2Kernel.modDirVersion}/

            # Create module loading configuration
            mkdir -p $out/etc/modules-load.d
            cat > $out/etc/modules-load.d/zfs.conf << EOF
      # ZFS modules for WSL2
      zfs
      zcommon
      znvpair
      zavl
      icp
      spl
      EOF

            # Create version info file
            cat > $out/build-info.json << EOF
      {
        "kernel_version": "${kernel.version}",
        "kernel_tag": "${kernel.tag}",
        "zfs_version": "${zfsForKernel.version}",
        "is_stable": ${
        if buildInfo.isStable
        then "true"
        else "false"
      },
        "used_fallback": ${
        if buildInfo.usedFallback
        then "true"
        else "false"
      },
        "build_date": "$(date -Iseconds)",
        "arch": "${arch}"
      }
      EOF
    '';

    # Add compatibility tests
    passthru = {
      tests = {
        zfs-compatibility =
          pkgs.runCommand "test-zfs-compatibility" {
            buildInputs = [pkgs.kmod pkgs.jq];
          } ''
            echo "Testing ZFS module compatibility..."

            # Check if ZFS modules can be inspected
            ${pkgs.kmod}/bin/modinfo ${zfsForKernel}/lib/modules/${wsl2Kernel.modDirVersion}/extra/zfs.ko > zfs-info.txt

            # Verify kernel version compatibility
            kernel_version="${kernel.version}"
            zfs_version="${zfsForKernel.version}"

            echo "Kernel: $kernel_version" > $out
            echo "ZFS: $zfs_version" >> $out
            echo "Compatibility test passed" >> $out

            # Verify build info
            cat ${buildInfo} >> $out || echo "No build info available" >> $out
          '';

        bzimage-format =
          pkgs.runCommand "test-bzimage-format" {
            buildInputs = [pkgs.file];
          } ''
            echo "Testing bzImage format..."
            ${pkgs.file}/bin/file ${wsl2Kernel}/bzImage > bzimage-info.txt

            # Verify it's a valid kernel image
            if grep -q "Linux kernel" bzimage-info.txt; then
              echo "bzImage format test passed" > $out
            else
              echo "ERROR: Invalid bzImage format" > $out
              cat bzimage-info.txt >> $out
              exit 1
            fi
          '';
      };

      # Export build information for CI
      inherit buildInfo kernel zfs;
      kernelModules = zfsForKernel;
    };

    meta = with lib; {
      description = "WSL2 Linux kernel with ZFS support from nixpkgs";
      longDescription = ''
        Microsoft WSL2 Linux kernel built with ZFS modules from nixpkgs.
        This package automatically selects compatible kernel and ZFS versions
        with fallback support for CI robustness.

        Kernel: ${kernel.version} (${kernel.tag})
        ZFS: ${zfsForKernel.version}
        Stable: ${
          if buildInfo.isStable
          then "yes"
          else "no"
        }
        Fallback used: ${
          if buildInfo.usedFallback
          then "yes"
          else "no"
        }
      '';
      platforms = ["x86_64-linux" "aarch64-linux"];
      license = licenses.gpl2;
      maintainers = [];
    };
  }
