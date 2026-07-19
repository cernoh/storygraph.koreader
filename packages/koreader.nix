{ lib, stdenv
, fetchurl
, makeWrapper
, fetchFromGitHub
, dpkg
, glib
, gnutar
, gtk3-x11
, openssl_1_1
, luajit
, sdcv
, SDL2
, plugins ? [] }:
let
  srcUrl = version: if stdenv.isAarch64 then
    "https://github.com/koreader/koreader/releases/download/v${version}/koreader-${version}-arm64.deb"
  else
    "https://github.com/koreader/koreader/releases/download/v${version}/koreader-${version}-amd64.deb";

  srcHash = if stdenv.isAarch64 then
    "sha256-KrkY1lTwq8mIomUUCQ9KvfZqinJ74Y86fkPexsFiOPg="
  else
    "sha256-ibehFrOcJqhM+CMAcHDn3Xwy6CueB8kdnoYMMDe/2Js=";

  luajit_lua52 = luajit.override { enable52Compat = true; };
in
stdenv.mkDerivation rec {
  pname = "koreader";
  version = "2024.11";

  src = fetchurl {
    url = srcUrl version;
    hash = srcHash;
  };

  src_repo = fetchFromGitHub {
    repo = "koreader";
    owner = "koreader";
    rev = "v${version}";
    fetchSubmodules = true;
    sha256 = "sha256-gHn1xqBc7M9wkek1Ja1gry8TKIuUxQP8T45x3z2S4uc=";
  };

  sourceRoot = ".";
  nativeBuildInputs = [ makeWrapper dpkg ];

  buildInputs = [
    glib
    gnutar
    gtk3-x11
    luajit_lua52
    openssl_1_1
    sdcv
    SDL2
  ];

  unpackCmd = "dpkg-deb -x ${src} .";

  dontConfigure = true;
  dontBuild = true;

  patches = [ ./patches/datastorage-isolate-storage.patch ];

  installPhase = let
    koreaderFolder = "$out/lib/koreader";

    installPlugins = lib.strings.concatMapStringsSep
      "\n"
      (plugin: "cp -R ${plugin} ${koreaderFolder}/plugins/${plugin.name}.koplugin")
      plugins;
  in ''
    set -v
    runHook preInstall
    mkdir -p $out
    cp -R usr/* $out/
    ln -sf ${luajit_lua52}/bin/luajit ${koreaderFolder}/luajit
    ln -sf ${sdcv}/bin/sdcv ${koreaderFolder}/sdcv
    ln -sf ${gnutar}/bin/tar ${koreaderFolder}/tar
    find ${src_repo}/resources/fonts -type d -execdir cp -r '{}' ${koreaderFolder}/fonts \;
    find $out -xtype l -print -delete
    wrapProgram $out/bin/koreader --prefix LD_LIBRARY_PATH : ${
      lib.makeLibraryPath [ gtk3-x11 SDL2 glib openssl_1_1 stdenv.cc.cc ]
    }
    ${installPlugins}
    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://github.com/koreader/koreader";
    description =
      "An ebook reader application supporting PDF, DjVu, EPUB, FB2 and many more formats, running on Cervantes, Kindle, Kobo, PocketBook and Android devices";
    mainProgram = "koreader";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = [ "aarch64-linux" "x86_64-linux" ];
    license = licenses.agpl3Only;
    maintainers = with maintainers; [ contrun neonfuz ];
  };
}
