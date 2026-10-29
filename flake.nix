{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      argsFor = system: {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      };
      forAllSystems = f: lib.genAttrs systems (system: f (argsFor system));
    in
    {
      devShells = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              go
            ];
          };
        }
      );

      packages = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.buildGoModule {
            pname = "json2nix";
            version = "1.0.0";
            src = ./.;
            vendorHash = null;
            env.CGO_ENABLED = "0";
          };
        }
      );

      checks = forAllSystems (
        { system, pkgs }:
        {
          formatting = self.formatter.${system}.check self;
          package = self.packages.${system}.default;
          vet = self.packages.${system}.default.overrideAttrs {
            pname = "json2nix-vet";
            buildPhase = "go vet ./...";
            doCheck = false;
            installPhase = "touch $out";
          };
          roundtrip =
            pkgs.runCommand "json2nix-roundtrip"
              {
                nativeBuildInputs = [
                  self.packages.${system}.default
                  pkgs.jq
                  pkgs.nix
                ];
              }
              ''
                export NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log
                for input in ${./testdata}/*.json; do
                  json2nix < "$input" > output.nix
                  nix-instantiate --parse output.nix > /dev/null
                  diff \
                    <(jq --sort-keys 'walk(if type == "number" then . + 0 else . end)' "$input") \
                    <(nix-instantiate --eval --strict --json output.nix \
                      | jq --sort-keys 'walk(if type == "number" then . + 0 else . end)')
                done
                touch $out
              '';
        }
      );

      formatter = forAllSystems (
        { pkgs, ... }:
        pkgs.treefmt.withConfig {
          settings = {
            on-unmatched = "info";
            formatter.nixfmt = {
              command = lib.getExe pkgs.nixfmt;
              includes = [ "*.nix" ];
              excludes = [ "testdata/*.nix" ];
            };
            formatter.gofmt = {
              command = lib.getExe' pkgs.go "gofmt";
              options = [ "-w" ];
              includes = [ "*.go" ];
            };
          };
        }
      );
    };
}
