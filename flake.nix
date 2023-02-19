{
  inputs = {
    opam-nix.url = "github:tweag/opam-nix";
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    dice.url = "github:SHoltzen/dice/800cd7bfc4fa1311c51e460b95e9c0dc7b30edf3"; # 2023-12-07
    dice.flake = false;
    rsdd.url = "github:pmall-neu/rsdd/4363f659b33d21575eebfe0e96c773afe4bcc6a5"; # pinned
    rsdd.flake = false;
    nixpkgs.follows = "opam-nix/nixpkgs";
  };
  outputs = {
    self,
    opam-nix,
    nixpkgs,
    ...
  } @ inputs:
  # Don't forget to put the package name instead of `throw':
  let
    package = "dice";
  in
    inputs.flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      naersk' = pkgs.callPackage inputs.naersk {};
      rsdd-src = pkgs.stdenv.mkDerivation {
        name = "rsdd-src";
        src = inputs.rsdd;
        phases = ["unpackPhase" "patchPhase" "buildPhase"];
        patches = [
          ./0001-4363f659-Cargo.lock.patch
        ];
        buildPhase = ''
          mkdir -p $out
          cp ./* -r $out
        '';
      };
      rsdd =
        (naersk'.buildPackage {
          src = rsdd-src.out;
        })
        .overrideAttrs (prev: {
          fixupPhase =
            ''
              # FIXME move to the .lib output
              mkdir $out/lib
              mv target/release/librsdd.a $out/lib/
            ''
            + (
              if system == "x86_64-darwin"
              then "mv target/release/librsdd.dylib $out/lib/" # untested
              else "mv target/release/librsdd.so $out/lib/"
            );
        });

      on = opam-nix.lib.${system};
      devPackagesQuery = {
        # You can add "development" packages here. They will get added to the devShell automatically.
        ocaml-lsp-server = "*";
        ocamlformat = "*";
      };
      query =
        devPackagesQuery
        // {
          ## You can force versions of certain packages here, e.g:
          ## - force the ocaml compiler to be taken from opam-repository:
          ocaml-base-compiler = "4.09.0";
          ## - or force the compiler to be taken from nixpkgs and be a certain version:
          # ocaml-system = "4.14.0";
          ## - or force ocamlfind to be a certain version:
          # ocamlfind = "1.9.2";
        };
      scope = on.buildOpamProject' {} inputs.dice query;
      overlay = final: prev: {
        # You can add overrides here
        ${package} = prev.${package}.overrideAttrs (old: {
          patches = [./0001-rsdd_nix_lib-instead-of-submodule.patch];
          buildInputs = old.buildInputs ++ [rsdd pkgs.gmp];
          buildPhase =
            ''
              substituteInPlace lib/dune --replace 'rsdd_nix_lib' '${rsdd.out}/lib'
            ''
            + old.buildPhase;
          # Prevent the ocaml dependencies from leaking into dependent environments
          doNixSupport = false;
        });
      };
      scope' = scope.overrideScope' overlay;
      # The main package containing the executable
      main = scope'.${package};
      # Packages from devPackagesQuery
      devPackages =
        builtins.attrValues
        (pkgs.lib.getAttrs (builtins.attrNames devPackagesQuery) scope');
    in {
      legacyPackages = scope';

      packages.default = main;
      apps = rec {
        dice = {
          type = "app";
          program = "${main}/bin/dice";
        };
        dicebench = {
          type = "app";
          program = "${main}/bin/dicebench";
        };
        default = dice;
      };

      devShells.default = pkgs.mkShell {
        inputsFrom = [main];
        buildInputs =
          devPackages
          ++ (with pkgs; [
            cargo
            rustc
            alejandra
          ]);
      };
    });
}
