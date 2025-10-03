with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    leveldb
    curl
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    leveldb.dev
    curl.dev
    curl
  ];
}
