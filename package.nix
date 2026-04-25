{ lib
, stdenv
, fetchurl
, unzip
, autoPatchelfHook
, makeWrapper
, alsa-lib
, fontconfig
, freetype
, gtk3
, libGL
, libxcrypt-legacy
, libxkbcommon
, nss
, nspr
, pciutils
, libx11
, libxcb
, libxcomposite
, libxcursor
, libxdamage
, libxext
, libxfixes
, libxi
, libxrandr
, libxrender
, libxtst
, zlib
, e2fsprogs
, channel ? "release"
, binName ? "junie"
}:

let
  version = "1417.47";

  platformMap = {
    "x86_64-linux" = "linux-amd64";
    "aarch64-linux" = "linux-aarch64";
    "x86_64-darwin" = "macos-amd64";
    "aarch64-darwin" = "macos-aarch64";
  };

  platform = platformMap.${stdenv.hostPlatform.system} or null;

  hashes = {
    "linux-amd64" = "1mn153skhh1anslspm5kg3fwvhpi81bl7681h71507773r2xqzj7";
    "linux-aarch64" = "1wkm8a5zqw4m49i7gm573y41f34zpqvjpdilm6pfjyjxbmfv21hw";
    "macos-amd64" = "0r1vqg4x7m9771igjyv64kqwv99p9ghk13whn91hk5hdrkgpvq8q";
    "macos-aarch64" = "095l70s43bby1cd26cnwsg7i41dv47p2nywq2vljqmwhmc4nvhxg";
  };

  downloadUrl =
    "https://github.com/JetBrains/junie/releases/download/${version}/junie-${channel}-${version}-${platform}.zip";

  src = fetchurl {
    url = downloadUrl;
    sha256 = hashes.${platform};
  };

  jbrLibs = [
    alsa-lib
    fontconfig
    freetype
    gtk3
    libGL
    libxcrypt-legacy
    libxkbcommon
    nss
    nspr
    pciutils
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxtst
    zlib
    e2fsprogs
  ];

  linuxRpath = lib.makeLibraryPath jbrLibs;
in
assert platform != null ||
  throw "Junie CLI not supported on ${stdenv.hostPlatform.system}. Supported: ${lib.concatStringsSep ", " (lib.attrNames platformMap)}";

stdenv.mkDerivation {
  pname = "junie";
  inherit version src;

  nativeBuildInputs = [ unzip makeWrapper ]
    ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux (jbrLibs ++ [ stdenv.cc.cc.lib ]);

  # JBR ships native libs that reference each other via $ORIGIN — let
  # autoPatchelf do its job, and don't strip (binaries are already release-mode).
  dontStrip = true;
  # Don't fail on optional libs JBR ships for features we won't use (jcef/jbrowser).
  autoPatchelfIgnoreMissingDeps = true;

  installPhase =
    if stdenv.isLinux then ''
      runHook preInstall

      mkdir -p $out/share/junie $out/bin
      cp -r . $out/share/junie/

      makeWrapper $out/share/junie/bin/junie $out/bin/${binName} \
        --set DISABLE_AUTOUPDATER 1 \
        --prefix LD_LIBRARY_PATH : "${linuxRpath}"

      runHook postInstall
    '' else ''
      runHook preInstall

      mkdir -p $out/share/junie $out/bin
      cp -R junie.app $out/share/junie/

      makeWrapper "$out/share/junie/junie.app/Contents/MacOS/junie" "$out/bin/${binName}" \
        --set DISABLE_AUTOUPDATER 1

      runHook postInstall
    '';

  meta = with lib; {
    description = "JetBrains Junie CLI - AI coding agent in your terminal";
    homepage = "https://www.jetbrains.com/junie/";
    # Junie is distributed under JetBrains' EAP Terms of Service (proprietary).
    license = licenses.unfree;
    platforms = lib.attrNames platformMap;
    mainProgram = binName;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
