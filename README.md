# junie-cli-nix

Nix flake for [JetBrains Junie CLI](https://www.jetbrains.com/junie/) — an AI coding agent that runs in your terminal, IDE, or CI/CD.

This flake fetches the official binary release zips from
[`github.com/JetBrains/junie/releases`](https://github.com/JetBrains/junie/releases),
patches the bundled JBR runtime libraries for NixOS, and exposes `junie` as a
package, app, and overlay.

The latest version is tracked automatically via a scheduled GitHub Actions
workflow that watches
[`update-info.jsonl`](https://raw.githubusercontent.com/JetBrains/junie/main/update-info.jsonl)
and opens an auto-merging PR every hour when a new release ships.

## Supported platforms

- `x86_64-linux`
- `aarch64-linux`
- `x86_64-darwin`
- `aarch64-darwin`

## License

This flake itself is MIT-licensed.

The Junie CLI binary it downloads is distributed by JetBrains under their EAP
Terms of Service (see <https://jb.gg/junie-tos-eap>), so the package is marked
as `unfree` — set `nixpkgs.config.allowUnfree = true;` (or
`NIXPKGS_ALLOW_UNFREE=1`) to install it.

## Usage

### Run without installing

```bash
nix run github:solcik/junie-cli-nix
nix run github:solcik/junie-cli-nix -- --version
```

### Add to a flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    junie-cli.url = "github:solcik/junie-cli-nix";
  };

  outputs = { self, nixpkgs, junie-cli, ... }: {
    # As an overlay:
    nixosConfigurations.example = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ junie-cli.overlays.default ];
          nixpkgs.config.allowUnfree = true;
          environment.systemPackages = [ pkgs.junie ];
        })
      ];
    };
  };
}
```

Or as a Home Manager package:

```nix
home.packages = [ junie-cli.packages.${pkgs.system}.junie ];
```

### Build locally

```bash
git clone https://github.com/solcik/junie-cli-nix
cd junie-cli-nix
nix build .#junie
./result/bin/junie --version
```

## Updating

The hourly workflow at `.github/workflows/update.yml` handles version bumps
automatically. To update manually:

```bash
./scripts/update.sh                   # latest
./scripts/update.sh --version 1417.47 # specific version
./scripts/update.sh --check           # check only
```

## How it works

`package.nix` calls `fetchurl` on the platform-appropriate
`junie-release-${version}-${platform}.zip` from
`github.com/JetBrains/junie/releases`. On Linux it runs `autoPatchelfHook`
across the bundled JetBrains Runtime so the dynamic linker resolves against
NixOS-friendly libraries. The launcher at `junie-app/bin/junie` is wrapped via
`makeWrapper` to set `LD_LIBRARY_PATH` and disable the in-product autoupdater.
