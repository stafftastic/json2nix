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
              golangci-lint
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
            doCheck = false;
          };
        }
      );

      checks = forAllSystems (
        { pkgs, system, ... }:
        {
          formatting = self.formatter.${system}.check self;
          package = self.packages.${system}.default;
          test = self.packages.${system}.default.overrideAttrs (previousAttrs: {
            pname = "${previousAttrs.pname}-test";
            doCheck = true;
          });
          typecheck = self.packages.${system}.default.overrideAttrs (previousAttrs: {
            pname = "${previousAttrs.pname}-typecheck";
            buildPhase = ''
              go build ./...
              go test -run '^$' ./...
            '';
            doCheck = false;
            installPhase = "touch $out";
          });
          nix-lint =
            pkgs.runCommandLocal "nix-lint"
              {
                nativeBuildInputs = with pkgs; [
                  deadnix
                  statix
                ];
              }
              ''
                cd ${self}
                statix check .
                deadnix --fail .
                touch $out
              '';
          actionlint =
            pkgs.runCommandLocal "actionlint"
              {
                nativeBuildInputs = with pkgs; [
                  actionlint
                  shellcheck
                ];
              }
              ''
                actionlint ${./.github/workflows}/*.yaml
                touch $out
              '';
          ci-coverage =
            pkgs.runCommandLocal "ci-coverage"
              {
                checks = lib.concatLines (lib.attrNames self.checks.x86_64-linux);
                passAsFile = [ "checks" ];
              }
              ''
                grep -ohE '\.#checks\.x86_64-linux\.[A-Za-z0-9_-]+' ${./.github/workflows/pull-request.yaml} \
                  | sed 's/^\.#checks\.x86_64-linux\.//' | sort -u > built
                sort -u "$checksPath" > declared
                missing=$(comm -23 declared built)
                if [ -n "$missing" ]; then
                  echo "checks not built by any pull request job:" $missing
                  exit 1
                fi
                touch $out
              '';
          roundtrip =
            pkgs.runCommandLocal "roundtrip"
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
          vet = self.packages.${system}.default.overrideAttrs (previousAttrs: {
            pname = "${previousAttrs.pname}-vet";
            buildPhase = "go vet ./...";
            doCheck = false;
            installPhase = "touch $out";
          });
          golangci-lint = self.packages.${system}.default.overrideAttrs (previousAttrs: {
            pname = "${previousAttrs.pname}-golangci-lint";
            nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [ pkgs.golangci-lint ];
            buildPhase = ''
              export HOME=$TMPDIR
              golangci-lint run ./...
            '';
            doCheck = false;
            installPhase = "touch $out";
          });
        }
      );

      formatter = forAllSystems (
        { pkgs, ... }:
        pkgs.treefmt.withConfig {
          settings = {
            on-unmatched = "info";
            formatter = {
              nixfmt = {
                command = lib.getExe pkgs.nixfmt;
                includes = [ "*.nix" ];
                excludes = [ "testdata/*.nix" ];
              };
              oxfmt = {
                command = lib.getExe pkgs.oxfmt;
                includes = [
                  "*.yaml"
                  "*.yml"
                ];
              };
              gofmt = {
                command = lib.getExe' pkgs.go "gofmt";
                options = [ "-w" ];
                includes = [ "*.go" ];
              };
            };
          };
        }
      );
    };
}
