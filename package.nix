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
  wiggle,
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
  version = "1.0.16";
  src = fetchFromGitHub {
    owner = "sst";
    repo = "opencode";
    rev = "v${finalAttrs.version}";
    hash = "sha256-brfAz8IT8RNkKTDvyd0zaeb2FJqtjnrvOqkqHzm/j0w=";
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

      # NOTE: Disabling post-install scripts with `--ignore-scripts` to avoid
      # shebang issues
      # NOTE: `--linker=hoisted` temporarily disables Bun's isolated installs,
      # which became the default in Bun 1.3.0.
      # See: https://bun.com/blog/bun-v1.3#isolated-installs-are-now-the-default-for-workspaces
      # This workaround is required because the 'yargs' dependency is currently
      # missing when building opencode. Remove this flag once upstream is
      # compatible with Bun 1.3.0.
      # which became the default in Bun 1.3.0.
      echo " `--linker=hoisted` temporarily disables Bun's isolated installs,"
      bun install \
        --filter=opencode \
        --force \
        --frozen-lockfile \
        --ignore-scripts \
        --linker=hoisted \
        --no-progress \
        --production

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/node_modules
      cp -R ./node_modules $out
      runHook postInstall
    '';
    dontFixup = true;
    outputHash =
      {
        x86_64-linux = "sha256-bLbDRdhU5O7emmb3OMo/LPJQtbwyk6xrTryt07ihm34=";
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
    wiggle
  ];

  patches = [
    ./patches/local-models-dev.patch
    ./patches/thread-rename.patch
    ./patches/spawn-default.patch
    ./patches/spawn-params.patch
    ./patches/attach-params.patch
  ];

  patchPhase = ''
    runHook prePatch
    
    echo "applying patch ./patches/local-models-dev.patch using wiggle"
    wiggle --replace packages/opencode/src/provider/models-macro.ts ${./patches/local-models-dev.patch}
    
    echo "applying patch ./patches/thread-rename.patch using wiggle"
    wiggle --replace packages/opencode/src/cli/cmd/tui/thread.ts ${./patches/thread-rename.patch}
    
    echo "applying patch ./patches/spawn-default.patch using wiggle"
    wiggle --replace packages/opencode/src/cli/cmd/tui/spawn.ts ${./patches/spawn-default.patch}
    rm -f packages/opencode/src/cli/cmd/tui/spawn.ts.porig
    
    echo "applying patch ./patches/spawn-params.patch using wiggle"
    wiggle --replace packages/opencode/src/cli/cmd/tui/spawn.ts ${./patches/spawn-params.patch}
    
    echo "applying patch ./patches/attach-params.patch using wiggle"
    wiggle --replace packages/opencode/src/cli/cmd/tui/attach.ts ${./patches/attach-params.patch}
    
    runHook postPatch
  '';

  configurePhase = ''
    runHook preConfigure
    cp -R ${finalAttrs.node_modules}/node_modules .
    runHook postConfigure
  '';

  env.MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";

  buildPhase = ''
    runHook preBuild

    cat > tsconfig.build.json <<EOF
    {
      "compilerOptions": {
        "jsx": "preserve",
        "jsxImportSource": "solid-js",
        "allowImportingTsExtensions": true,
        "baseUrl": ".",
        "paths": {
          "@/*": ["./packages/opencode/src/*"],
          "@tui/*": ["./packages/opencode/src/cli/cmd/tui/*"]
        }
      }
    }
    EOF

    # Build with all entry points like official build.ts does
    bun build \
      --define OPENCODE_VERSION='"${finalAttrs.version}"' \
      --define OPENCODE_CHANNEL='"latest"' \
      --compile \
      --compile-exec-argv="--" \
      --target=${bun-target.${stdenvNoCC.hostPlatform.system}} \
      --outfile=opencode \
      --tsconfig-override tsconfig.build.json \
      --loader=.json:json \
      ./packages/opencode/src/index.ts \
      ./node_modules/@opentui/core/parser.worker.js \
      ./packages/opencode/src/cli/cmd/tui/worker.ts

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
    description = "AI coding agent built for the terminal (CLI-only)";
    longDescription = ''
      OpenCode is an AI coding agent.
      
      Note: This build provides CLI functionality only (run, serve, auth, etc.).
      The interactive TUI is not functional in version 1.0.16 due to
      incompatibilities with the @opentui-based architecture.
    '';
    homepage = "https://github.com/sst/opencode";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    maintainers = [
      {
        email = "aodhan.hayter@gmail.com";
        github = "AodhanHayter";
        name = "Aodhan Hayter";
      }
    ];
    mainProgram = "opencode";
  };
})
