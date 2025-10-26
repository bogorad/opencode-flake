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

This is the main workflow, triggered only when a new version is detected.

1.  **Environment Setup:**

    - The workflow checks out the repository code.
    - It installs Nix, the `nix-update` utility, and **QEMU**, which is essential for emulating the `aarch64` architecture on an `x86_64` runner.

2.  **Version Update (`Step 1`):**

    - It runs `nix-update --flake opencode`. This command automatically updates the `version` and source code `hash` in `package.nix` to match the latest upstream release.

3.  **Unconditional Hash Reset (`Step 2`):**

    - This is a critical step for predictability. The script **unconditionally erases all dependency hashes** (`vendorHash` for Go, and `outputHash` for both `x86_64` and `aarch64`) and replaces them with known dummy values (`AAAA...`, `BBBB...`, `CCCC...`).
    - This "clean slate" approach ensures the subsequent steps run in a predictable, deterministic order, regardless of what state the file was in previously.

4.  **Native Build & Verification Loop for `x86_64` (`Step 3`):**

    - The workflow now enters the intelligent hash-fixing loop we refined earlier. It attempts to build the package for the native `x86_64` architecture.
    - The build is expected to fail. The script correctly identifies _repairable_ failures (a hash mismatch, or a "No such file" error caused by a bad vendor hash).
    - It extracts the correct hash from the `got: ...` line in the error log.
    - It replaces the _first_ dummy hash it finds in `package.nix` (in the strict order of source, then vendor, then `x86_64` output hash).
    - This loop repeats until `nix build` completes successfully. A successful build serves as **absolute verification** that all hashes for the `x86_64` architecture are correct.

5.  **Emulated Hash Discovery for `aarch64` (`Step 4`):**

    - Building under QEMU is extremely slow, so the workflow uses a more efficient "one-shot" strategy instead of a full verification loop.
    - It runs `nix build --system aarch64-linux` just **once**. This build is expected to fail because the `aarch64` `outputHash` is still a dummy value.
    - It parses the error log from this single failed run to extract the correct `aarch64` hash.
    - It replaces the final dummy hash in `package.nix`.
    - Crucially, it **does not** run a second, slow emulated build to verify. It trusts the hash provided by Nix's failure output, which is a safe and highly pragmatic optimization that saves enormous amounts of CI time.

6.  **Commit and Push (`Step 5`):**
    - The workflow first checks if `package.nix` was actually modified. If no new version was found and all hashes were already correct, the file will be unchanged, and the workflow exits peacefully.
    - If the file has changed, it configures Git with a bot identity.
    - It commits the updated `package.nix` with a descriptive message (e.g., `Update OpenCode to 0.16.0`).
    - It runs `git pull --rebase` to prevent push conflicts if the remote `master` branch was changed during the long run of this workflow.
    - Finally, it pushes the commit and a corresponding version tag back to the repository, making the new, fully-verified package available to all users.
