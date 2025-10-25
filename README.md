# OpenCode Nix Flake

This repository provides a Nix flake for the [OpenCode](https://github.com/sst/opencode) terminal AI assistant. The primary feature is a GitHub Actions workflow that automates version updates and cryptographic hash verification for all package dependencies across multiple architectures.

## Abstract

This project provides a Nix package for OpenCode that is maintained through an automated CI/CD system. A GitHub Actions workflow monitors for upstream releases, updates the package definition, and calculates the necessary source, Go vendor, and Node.js dependency hashes for both `x86_64` and `aarch64` architectures. The process uses native compilation for `x86_64` and QEMU-based emulation to determine the `aarch64` hashes, committing the updated and verified package definition back to the repository.

## Quick Start

```bash
# Run directly
nix run github:bogorad/opencode-flake

# Install to user profile
nix profile install github:bogorad/opencode-flake
```

## Installation

Add the flake to a NixOS or Home Manager configuration.

```nix
{
  inputs.opencode-flake.url = "github:bogorad/opencode-flake";

  # Example for configuration.nix or home.nix
  environment.systemPackages = [ inputs.opencode-flake.packages.${pkgs.system}.default ];
}
```

## Automation Logic

The repository uses a GitHub Actions workflow to keep the package current. The process is as follows:

#### 1. Version Detection

An RSS monitor workflow checks the upstream OpenCode GitHub releases feed. If a new version is found, it triggers the main update workflow via a `repository_dispatch` event.

#### 2. Environment Setup

The workflow runner prepares a build environment by installing Nix, the `nix-update` utility, and QEMU for cross-architecture emulation.

#### 3. Version Update

The `nix-update` command is executed to check the latest upstream version. If the upstream version is newer than the one defined in `package.nix`, the `version` attribute in the file is updated. The workflow proceeds regardless of whether a new version was found.

#### 4. Hash Reset

To ensure all hashes are recalculated, the workflow finds and replaces all hash values in `package.nix` with predefined dummy values. This applies to the following:

- `src` hash (`fetchFromGitHub`)
- `vendorHash` (`buildGoModule`)
- `outputHash` for both `x86_64-linux` and `aarch64-linux` (`node_modules` derivation)

#### 5. Native Build and Verification (`x86_64`)

The workflow enters a loop to resolve hashes for the native `x86_64` architecture:

1.  It attempts to build the package using `nix build`. This command is expected to fail due to one of the dummy hashes.
2.  The error output is parsed to extract the correct hash from the `got: ...` line.
3.  The corresponding dummy hash in `package.nix` is replaced with the correct value.
4.  This loop repeats, fixing one hash per iteration, until `nix build` completes successfully. A successful build serves as verification that all `x86_64`-related hashes are correct.

#### 6. Emulated Build and Hash Discovery (`aarch64`)

To determine the `aarch64` `outputHash`, a separate strategy is used to accommodate the slow performance of emulation:

1.  The workflow executes `nix build --system aarch64-linux` a single time.
2.  This command is expected to fail due to the remaining dummy hash for the `aarch64` architecture.
3.  The error output is parsed to extract the correct hash from the `got: ...` line.
4.  The `aarch64-linux` dummy hash in `package.nix` is replaced with this correct value. The step then concludes without a second, slow verification build.

#### 7. Commit and Push

Finally, the workflow saves the changes:

1.  It runs `git diff` to check if `package.nix` has been modified. If not, the job finishes.
2.  If the file has changed, it creates a new Git commit.
3.  It executes `git pull --rebase` to synchronize its local state with the remote branch, preventing push conflicts that could arise from long run times.
4.  It pushes the new commit and the corresponding version tag to the `master` branch of the repository.

## Supported Systems

- `aarch64-linux`
- `x86_64-linux`

## License

MIT
