# OpenCode Nix Flake/Package

This repository provides a Nix flake for installing **[OpenCode](https://github.com/sst/opencode)**, a powerful terminal-based AI coding agent.

The primary goal of this flake is to provide a reliable and **continuously updated** package for the Nix ecosystem.

## Note on TUI Functionality

As of `v1.0.16`, this package provides the core **CLI functionality only** (`run`, `serve`, `auth`, etc.). The interactive terminal user interface (TUI) is not functional due to upstream architectural changes. The build focuses on providing a stable and up-to-date command-line agent.

## Features

- **Fully Automated:** A GitHub Action runs on a schedule to check for new upstream releases.
- **Always Up-to-Date:** When a new version of OpenCode is released, this flake automatically updates the version, fetches the new source code, and corrects all dependency hashes.
- **Reproducible:** Built with Nix for perfect, bit-for-bit reproducibility.
- **CLI Enhancements:** Applies several patches to add useful command-line arguments (`--session`, `--model`, `--prompt`, `--agent`) that are not available in the upstream version, allowing for more flexible scripting and control.
- **Robust Build Process:** The Nix build includes critical overrides to handle complex TypeScript and JSX configurations, ensuring reliable builds across updates.

## Installation

To install OpenCode using this flake, ensure you have [Nix with flakes enabled](https://nixos.wiki/wiki/Flakes#Enable_flakes) and run the following command:

```bash
nix profile install github:bogorad/opencode-flake
```

The `opencode` command will then be available in your shell.

## Usage

### Run without Installing

To run the latest version of OpenCode directly without adding it to your system profile, use:

```bash
nix run github:bogorad/opencode-flake
```

### Run after Installing

If you have installed it using `nix profile install`, simply run the command:

```bash
opencode
```

### Use with Flakes

To include this package in your own NixOS or home-manager configuration:

```nix
{
  inputs.opencode-flake.url = "github:bogorad/opencode-flake";

  outputs = { self, nixpkgs, opencode-flake }: {
    # In your NixOS configuration
    environment.systemPackages = [
      opencode-flake.packages.${pkgs.system}.default
    ];
  };
}
```

---

## Automation

### High-Level Overview

The repository uses a **two-workflow system** to achieve fully automated, multi-architecture updates for the OpenCode Nix package.

1.  **Detection Workflow (`rss-monitor.yml`):** A lightweight, frequently-run job that polls the official OpenCode release feed. Its only job is to detect a new version.
2.  **Update Workflow (`update-opencode.yml`):** A heavy-duty, resource-intensive job that performs the actual update. It only runs when triggered by the detection workflow, saving significant CI resources.

---

### Detailed Automation Logic

Here is a step-by-step breakdown of the entire process, based on the code in the repository.

#### Phase 1: Version Detection (`rss-monitor.yml`)

This workflow runs every 15 minutes to ensure updates are caught quickly.

1.  **Get Local Version:** It first reads the `version` attribute from the `package.nix` file to determine what version the repository currently provides.
2.  **Get Remote Version:** It then fetches the official OpenCode GitHub releases RSS feed (`releases.atom`) and parses it to find the version number of the most recent release.
3.  **Compare and Trigger:**
    - If the local and remote versions match, the workflow prints a success message and exits.
    - If a new version is detected, it makes an API call to GitHub, triggering a `repository_dispatch` event. This event signals the main update workflow to start, passing the new version number as part of the event.

#### Phase 2: The Update Process (`update-opencode.yml`)

This is the main workflow, triggered only when a new version is detected. It sequentially corrects each required hash for the new version.

1.  **Environment Setup:**

    - The workflow checks out the repository code.
    - It installs Nix, the `nix-update` utility, and **QEMU** (for emulating the `aarch64` architecture on an `x86_64` runner).

2.  **Step 1: Update Version and Source Hash:**

    - The script runs `nix-update` to automatically update the `version` attribute in `package.nix`.
    - It then manually prefetches the source code tarball for the new version using `nix-prefetch-url` to get the correct content hash.
    - It uses `sed` to replace the old `hash` in `package.nix` with the new one.

3.  **Step 2 & 3: Fix Node.js Modules Hashes (for `x86_64` and `aarch64`):**

    - The same process is repeated for the `node_modules` dependency for both `x86_64-linux` and `aarch64-linux` architectures.
    - The `outputHash` for each architecture is set to a dummy value (`sha256-BBBB...`).
    - An architecture-specific build is attempted, which fails as expected.
    - The correct hash is parsed from the error log and written to `package.nix`.

4.  **Step 4: Verification Build with Overrides:**

    - With all hashes now correct, the workflow runs a final `nix build` command.
    - **Crucially**, this build step uses a dynamically generated `tsconfig.build.json` inside the Nix derivation. This override file forces the correct SolidJS JSX transform and configures all necessary path aliases (`@/*` and `@tui/*`), ensuring the `bun` build tool can correctly compile the project regardless of any conflicting configurations in the upstream source code.
    - The build's success serves as **absolute verification** that all hashes and build configurations are correct.

5.  **Step 5: Commit and Push:**
    - If `package.nix` has been modified, the workflow commits the changes with a descriptive message (e.g., `Update OpenCode to 1.0.8`).
    - It runs `git pull --rebase` to prevent push conflicts, then pushes the commit and a corresponding version tag back to the repository.
