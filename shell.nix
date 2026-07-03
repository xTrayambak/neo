with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    curl
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    curl.dev
    curl
  ];
}
