with import <nixpkgs> { };

mkShell {
  nativeBuildInputs = [
    pkg-config
    leveldb
    curl
    clang
    llvm
  ];

  LD_LIBRARY_PATH = lib.makeLibraryPath [
    leveldb.dev
    curl.dev
    curl
  ];
}
