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
