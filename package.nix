{
  lib,
  stdenv,
  stdenvNoCC,
  buildGoModule,
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
  version = "0.15.18";
  src = fetchFromGitHub {
    owner = "sst";
    repo = "opencode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-yQfOgLJkSeBDTMS7MHuEQVzd8oG8EzQZRFYFHRO/08o=";
  };

  tui = buildGoModule {
    pname = "opencode-tui";
    inherit (finalAttrs) version src;
    nativeBuildInputs = [ writableTmpDirAsHomeHook ];
    modRoot = "packages/tui";

    # Leave this to be overwritten by the workflow to an SRI dummy like sha256-CCCC...=
    vendorHash = "sha256-CLi4wjjlnClvaD8j4SPEdzfEvHWTWTfS9zQnBHcCVZ0=";

    proxyVendor = true;
    subPackages = [ "cmd/opencode" ];
    env.CGO_ENABLED = 0;

    overrideModAttrs = (
      _: {
        GOPROXY = "https://proxy.golang.org,direct";
        # Optional if Go workspaces misbehave: GOWORK = "off";
      }
    );
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
        --filter=opencode \
        --force \
        --ignore-scripts \
        --no-progress
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
        x86_64-linux = "sha256-qvwsGBJmGQhH/zwIQwJlRwWE6n5zddjHfPD4l/O5RZU=";
        aarch64-linux = "sha256-+nW6PpKV4EqauqyOv6zFzg/MFQznYHLhmLdGor8ic2g=";
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
    ./local-models-dev.patch
  ];

  configurePhase = ''
    runHook preConfigure
    cp -R ${finalAttrs.node_modules}/node_modules .
    runHook postConfigure
  '';

  env.MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";

  buildPhase = ''
    runHook preBuild
    bun build \
      --define OPENCODE_TUI_PATH="'${finalAttrs.tui}/bin/opencode'" \
      --define OPENCODE_VERSION="'${finalAttrs.version}'" \
      --compile \
      --compile-exec-argv="--" \
      --target=${bun-target.${stdenvNoCC.hostPlatform.system}} \
      --outfile=opencode \
      ./packages/opencode/src/index.ts
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
        "tui"
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
