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
  version = "1.0.12";
  src = fetchFromGitHub {
    owner = "sst";
    repo = "opencode";
    rev = "v${finalAttrs.version}";
    hash = "sha256-nsb18HozRGQlaoQVDQQo3FadYs5OHxIjmUQi09iLHIw=";
  };

  tui = buildGoModule {
    pname = "opencode-tui";
    inherit (finalAttrs) version src;
    nativeBuildInputs = [ writableTmpDirAsHomeHook ];
    modRoot = "packages/tui";
    vendorHash = "sha256-muwry7B0GlgueV8+9pevAjz3Cg3MX9AMr+rBwUcQ9CM=";
    subPackages = [ "cmd/opencode" ];
    env.CGO_ENABLED = 0;
    ldflags = [
      "-s"
      "-w"
      "-X=main.Version=${finalAttrs.version}"
    ];
    overrideModAttrs = (
      _: {
        GOPROXY = "https://proxy.golang.org,direct";
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
        x86_64-linux = "sha256-b0LeltFa6W3ABL3q+7KmdDd+9AurwEB0kJr6Zbgng7c=";
        aarch64-linux = "sha256-mlRvX6ki8z9cefApZpx2gIEDRneIBoImC/WzKcsqh8o=";
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
    ./local-tui-spawn.patch
  ];

  configurePhase = ''
    runHook preConfigure
    cp -R ${finalAttrs.node_modules}/. .
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

    bun build \
      --define OPENCODE_TUI_PATH='"${finalAttrs.tui}/bin/opencode"' \
      --define OPENCODE_VERSION='"${finalAttrs.version}"' \
      --compile \
      --compile-exec-argv="--" \
      --target=${bun-target.${stdenvNoCC.hostPlatform.system}} \
      --outfile=opencode \
      --tsconfig-override tsconfig.build.json \
      ./packages/opencode/src/index.ts \
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
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}" \
      --set OPENCODE_TUI_PATH "${finalAttrs.tui}/bin/opencode"
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
