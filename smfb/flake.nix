{
  description = "smfb — Shannon Mouse Fly Brain: a fly connectome (C + arm64 NEON) steering a mouse (SwiftUI + CoreGraphics)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        # The C core, the headless CLI and the kernel tests, built with the
        # host compiler. On aarch64 hosts (Apple silicon, aarch64-linux) the
        # NEON kernels are compiled in and checked against the portable path.
        mkCore = stdenv: stdenv.mkDerivation {
          pname = "smfb-core";
          version = "0.1.0";
          src = ./.;
          makeFlags = [ "BUILD=build" "CC=${stdenv.cc.targetPrefix}cc" ];
          buildPhase = "make $makeFlags";
          doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
          checkPhase = "make $makeFlags test";
          installPhase = ''
            install -Dm755 build/smfb-cli $out/bin/smfb-cli
            install -Dm755 build/kernel_test $out/bin/smfb-kernel-test
          '';
        };

        core = mkCore pkgs.stdenv;

        # Cross-built arm64 binaries, run under qemu-user, so the assembly is
        # tested even from an x86_64 machine.
        canCross = system == "x86_64-linux";
        coreArm64 = mkCore pkgs.pkgsCross.aarch64-multiplatform.stdenv;
        neonCheck = pkgs.runCommand "smfb-neon-under-qemu" { nativeBuildInputs = [ pkgs.qemu ]; } ''
          qemu-aarch64 ${coreArm64}/bin/smfb-kernel-test | tee $out
          grep -q "neon available" $out
        '';

        xcodeproj = pkgs.writeShellScriptBin "smfb-xcodeproj" ''
          set -e
          if [ ! -f project.yml ]; then echo "run from the smfb/ directory"; exit 1; fi
          exec ${pkgs.xcodegen}/bin/xcodegen generate "$@"
        '';
      in {
        packages = {
          default = core;
          smfb-core = core;
        } // lib.optionalAttrs canCross { smfb-core-arm64 = coreArm64; };

        checks = {
          kernels = core;
        } // lib.optionalAttrs canCross { neon-under-qemu = neonCheck; };

        apps = {
          default = { type = "app"; program = "${core}/bin/smfb-cli"; };
          smfb-cli = { type = "app"; program = "${core}/bin/smfb-cli"; };
        } // lib.optionalAttrs pkgs.stdenv.isDarwin {
          xcodeproj = { type = "app"; program = "${xcodeproj}/bin/smfb-xcodeproj"; };
        };

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.gnumake pkgs.clang ]
            ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.xcodegen ]
            ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.qemu ]
            ++ lib.optionals canCross [ pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc ];
          shellHook = ''
            echo "smfb: make test | make run | xcodegen generate (macOS) | nix flake check"
          '';
        };
      });
}
