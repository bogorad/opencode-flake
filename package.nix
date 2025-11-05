{
  lib,
  stdenv,
  stdenvNoCC,
  bun,
  fetchFromGitHub,
  makeBinaryWrapper,
  models-dev,
  nix-update-script,
  testers,
  writableTmpDirAsHomeHook,
}:

let
  bun-target = {
    "aarch64-darwin" = "bun-darwin-arm64";
    "aarch64-linux" = "bun-linux-arm64";
    "x86_64-darwin" = "bun-darwin-x64";
    "x86_64-linux" = "bun-linux-x64";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = "1.0.29";
  src = fetchFromGitHub {
    owner = "sst";
    repo = "opencode";
    rev = "v${finalAttrs.version}";
    hash = "sha256-5Nk6NjCHcb7x0pX3WFAAxaaA/H1P+oQaVPOCgzDa6WM=";
  };

  node_modules = stdenvNoCC.mkDerivation {
    pname = "opencode-node_modules";
    inherit (finalAttrs) version src;
    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];
    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      while IFS= read -r dir; do
        rel="''${dir#./}"
        dest="$out/$rel"
        mkdir -p "$(dirname "$dest")"
        cp -R "$dir" "$dest"
      done < <(find . -type d -name node_modules -prune)
      runHook postInstall
    '';
    dontFixup = true;
    outputHash =
      {
        x86_64-linux = "sha256-+keJXWN9U6XJboBaFTlIYmnu4Us3SAMD2OyIIJmxYNs=";
        aarch64-linux = "";
      }
      .${stdenv.hostPlatform.system};
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

  nativeBuildInputs = [
    bun
    makeBinaryWrapper
    models-dev
  ];

  patches = [
    ./patches/local-models-dev.patch
    ./patches/local-tui-spawn-imports.patch
    ./patches/local-tui-spawn-worker.patch
    ./patches/local-sdk-baseurl.patch
  ];

  configurePhase = ''
    runHook preConfigure
    cp -R ${finalAttrs.node_modules}/. .
    runHook postConfigure
  '';

  env.MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";

  buildPhase = ''
    runHook preBuild

    cat > tsconfig.build.json <<'EOF'
    {
      "compilerOptions": {
        "jsx": "preserve",
        "jsxImportSource": "@opentui/solid",
        "allowImportingTsExtensions": true,
        "baseUrl": ".",
        "paths": {
          "@/*": ["./packages/opencode/src/*"],
          "@tui/*": ["./packages/opencode/src/cli/cmd/tui/*"]
        }
      }
    }
    EOF

    cat > bun-build.ts <<'EOF'
    import solidPlugin from "./packages/opencode/node_modules/@opentui/solid/scripts/solid-plugin"
    import path from "path"
    import fs from "fs"

    const version = "1.0.17"
    const channel = "@CHANNEL@"
    const repoRoot = process.cwd()
    const packageDir = path.join(repoRoot, "packages/opencode")
    const parserWorker = fs.realpathSync(
      path.join(packageDir, "node_modules/@opentui/core/parser.worker.js"),
    )
    const relativeWorker = path.relative(packageDir, parserWorker)
    const target = process.env["BUN_COMPILE_TARGET"]

    if (!target) {
      throw new Error("BUN_COMPILE_TARGET not set")
    }

    await Bun.build({
      conditions: ["browser"],
      tsconfig: "./tsconfig.build.json",
      plugins: [solidPlugin],
      sourcemap: "external",
      entrypoints: [
        path.join(packageDir, "src/index.ts"),
        parserWorker,
        path.join(packageDir, "src/cli/cmd/tui/worker.ts"),
      ],
      define: {
        OPENCODE_VERSION: `'@VERSION@'`,
        OTUI_TREE_SITTER_WORKER_PATH: "/$bunfs/root/" + relativeWorker.replace(/\\/g, "/"),
        OPENCODE_CHANNEL: `'@CHANNEL@'`,
      },
      compile: {
        target,
        outfile: "opencode",
        execArgv: ["--user-agent=opencode/" + version, "--env-file=\"\"", "--"],
        windows: {},
      },
    })
    EOF

    substituteInPlace bun-build.ts \
      --replace '@VERSION@' "${finalAttrs.version}" \
      --replace '@CHANNEL@' "latest"

    export BUN_COMPILE_TARGET=${bun-target.${stdenvNoCC.hostPlatform.system}}
    bun --bun bun-build.ts

    runHook postBuild
  '';

  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode $out/bin/opencode
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/opencode \
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"
  '';

  passthru = {
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
      command = "HOME=$(mktemp -d) opencode --version";
      inherit (finalAttrs) version;
    };
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage"
        "node_modules"
      ];
    };
  };

  meta = {
    description = "AI coding agent built for the terminal";
    longDescription = ''
      OpenCode is a terminal-based agent that can build anything.
      It combines a TypeScript/JavaScript core with a Go-based TUI
      to provide an interactive AI coding experience.
    '';
    homepage = "https://github.com/bogorad/opencode-flake";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    maintainers = [
      {
        email = "bogorad@gmail.com";
        github = "bogorad";
        name = "Eugene Bogorad";
      }
    ];
    mainProgram = "opencode";
  };
})
