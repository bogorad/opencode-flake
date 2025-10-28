# OpenCode Nix Flake/Package

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
This repository provides a Nix flake for installing **[OpenCode](https://github.com/sst/opencode)**, a powerful terminal-based AI coding agent.

The primary goal of this flake is to provide a reliable and **continuously updated** package for the Nix ecosystem.

## Features

- **Fully Automated:** A GitHub Action runs on a schedule to check for new upstream releases.
- **Always Up-to-Date:** When a new version of OpenCode is released, this flake automatically updates the version, fetches the new source code, and corrects all dependency hashes.
- **Reproducible:** Built with Nix for perfect, bit-for-bit reproducibility.

## Installation

To install OpenCode using this flake, ensure you have [Nix with flakes enabled](https://nixos.wiki/wiki/Flakes#Enable_flakes) and run the following command:

```bash
nix profile add github:bogorad/opencode-flake
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

---

## Automation

### High-Level Overview

The repository uses a **two-workflow system** to achieve fully automated, multi-architecture updates for the OpenCode Nix package.

1.  **Detection Workflow (`rss-monitor.yml`):** A lightweight, frequently-run job that polls the official OpenCode release feed. Its only job is to detect a new version.
2.  **Update Workflow (`update-opencode.yml`):** A heavy-duty, resource-intensive job that performs the actual update. It only runs when triggered by the detection workflow, saving significant CI resources.

---

### Detailed Automation Logic

Here is a step-by-step breakdown of the entire process, based directly on the code in your repository.

#### Phase 1: Version Detection (`rss-monitor.yml`)

This workflow runs every 15 minutes to ensure updates are caught quickly.

1.  **Get Local Version:** It first reads the `version` attribute from the `package.nix` file to determine what version the repository currently provides.
2.  **Get Remote Version:** It then fetches the official OpenCode GitHub releases RSS feed (`releases.atom`) and parses it to find the version number of the most recent release.
3.  **Compare and Trigger:**
    - If the local and remote versions match, the workflow prints a success message and exits.
    - If a new version is detected, it does **not** perform the update itself. Instead, it makes an API call to GitHub, triggering a `repository_dispatch` event. This event acts as a signal to start the main update workflow, passing the new version number as part of the event.

#### Phase 2: The Update Process (`update-opencode.yml`)

This is the main workflow, triggered only when a new version is detected. It sequentially corrects each required hash.

1.  **Environment Setup:**
    - The workflow checks out the repository code.
    - It installs Nix, the `nix-update` utility, and **QEMU**, which is essential for emulating the `aarch64` architecture on an `x86_64` runner.

2.  **Step 1: Update Version and Source Hash:**
    - The script first runs `nix-update` to automatically update the `version` attribute in `package.nix`.
    - It then manually prefetches the source code tarball corresponding to the new version using `nix-prefetch-url` to get the correct content hash.
    - Finally, it uses `sed` to replace the old `hash` in `package.nix` with the new, correct one.

3.  **Step 2: Fix Go Vendor Hash:**
    - The `vendorHash` for the Go-based TUI is reset to a known dummy value (e.g., `sha256-AAAA...`).
    - The script attempts to build *only* the TUI component (`.#opencode.tui`). This build is guaranteed to fail due to the hash mismatch.
    - It parses the correct hash from the `got: ...` line in the Nix error output.
    - It uses `sed` to replace the dummy vendor hash with the correct one.

4.  **Step 3: Fix `x86_64` Node.js Modules Hash:**
    - The process is repeated for the `node_modules` dependency for the `x86_64-linux` architecture.
    - The `outputHash` is set to a dummy value (`sha256-BBBB...`).
    - It attempts a full build for `x86_64-linux`, which fails as expected.
    - It parses the correct hash from the error log and writes it to `package.nix`.

5.  **Step 4: Fix `aarch64` Node.js Modules Hash:**
    - The same hash-fixing logic is applied to the `aarch64-linux` architecture, running under QEMU emulation.
    - The `aarch64-linux` `outputHash` is replaced with a dummy value.
    - It runs an emulated build, which fails.
    - It parses the correct hash from the output and updates the file. This "one-shot" approach avoids a second, time-consuming emulated build.

6.  **Step 5: Verification Build:**
    - With all hashes now believed to be correct, the workflow runs a final `nix build .#opencode --system x86_64-linux` command.
    - This build is expected to succeed. Its successful completion serves as **absolute verification** that the package is now correct for the native architecture.

7.  **Step 6: Commit and Push:**
    - The workflow checks if `package.nix` was actually modified. If all hashes were already correct, the file will be unchanged, and the workflow exits.
    - If the file has changed, it configures Git with a bot identity.
    - It commits the updated `package.nix` with a descriptive message (e.g., `Update OpenCode to 0.16.0`).
    - It runs `git pull --rebase` to prevent push conflicts, then pushes the commit and a corresponding version tag back to the repository.

