{
  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      argsFor = system: {
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

      formatter = forAllSystems (
        { pkgs, ... }:
        pkgs.treefmt.withConfig {
          settings = {
            on-unmatched = "info";
            formatter.nixfmt = {
              command = lib.getExe pkgs.nixfmt-rfc-style;
              includes = [ "*.nix" ];
            };
            formatter.gofmt = {
              command = "${pkgs.go}/bin/gofmt";
              options = [ "-w" ];
              includes = [ "*.go" ];
            };
          };
        }
      );
    };
}
