{
  description = "Nix flake for JetBrains Junie CLI - AI coding agent in your terminal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      overlay = final: prev: {
        junie = final.callPackage ./package.nix { };
      };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
      in
      {
        packages = {
          default = pkgs.junie;
          junie = pkgs.junie;
        };

        apps = {
          default = {
            type = "app";
            program = "${pkgs.junie}/bin/junie";
          };
          junie = {
            type = "app";
            program = "${pkgs.junie}/bin/junie";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixpkgs-fmt
            nix-prefetch-git
            jq
          ];
        };
      }) // {
        overlays.default = overlay;
      };
}
