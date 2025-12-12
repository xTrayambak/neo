# Building Neo
This aims to be a comprehensive guide on compiling Neo.

## Installing its dependencies
Neo only relies on a single external library: `libcURL`.

**Debian and its derivatives (e.g Ubuntu)**: `sudo apt-get update && sudo apt-get install libcurl4 libcurl4-openssl-dev`

**Fedora and its derivatives**: `sudo dnf install libcurl libcurl-devel`

**Arch Linux and its derivatives**: `sudo pacman -S curl`

**OpenSUSE**: `sudo zypper install libcurl4 libcurl-devel`

## Obtaining a copy of Neo
You can get a copy of Neo by running the following command:
```
$ git clone https://github.com/xTrayambak/neo
```

## Build (Nimble)
If you have [Nimble](https://github.com/nim-lang/nimble) installed, which you probably do if you have Nim installed, you can follow this path.

```
$ cd neo/
$ nimble build
```

## Build (Manual)
If you do not have Nimble installed, this is what you can do to compile Neo. **This is not recommended!**

### Preparing all dependencies (transitive and direct)
Neo depends on several Nim libraries to function, here is what you need to vendor in:
- zippy 0.10.6
- semver 1.2.3
- jsony 1.1.5
- floof 1.0.0
- url 0.1.3
- nimsimd 1.3.2
- benchy 0.0.1
- shakar 0.1.3
- noise 0.1.10
- results 0.5.1
- curly 1.1.1
- pretty 0.2.0
- crunchy 0.1.11
- libcurl 1.0.0
- parsetoml 0.7.2
- webby 0.1.7

After cloning all of these and checking them out to the intended version, do the next substep.

### Compiling Neo with vendored dependencies
Assuming all your dependencies are in a directory like `vendor/`:
```
$ ls vendor/
benchy-0.0.1    floof-1.0.0    nimsimd-1.3.2    pretty-0.2.0   shakar-0.1.3  zippy-0.10.6
crunchy-0.1.11  jsony-1.1.5    noise-0.1.10     results-0.5.1  url-0.1.3
curly-1.1.1     libcurl-1.0.0  parsetoml-0.7.2  semver-1.2.3   webby-0.1.7
```

Use the following command to compile Neo:
```
$ nim c -o:neo <PATHS> src/neo.nim
```

Paths should be a bunch of `--path:` for each of the above-listed dependencies, so the compiler can supply them to Neo's codebase properly.

## Making Neo bootstrap itself

After Neo is done being built, you are recommended to use the compiled result to let Neo "bootstrap" itself, by running the following command:
```
$ ./neo install
```
Neo will then do its own bootstrap and install itself at `~/.local/share/neo`.
