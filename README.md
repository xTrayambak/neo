# neo
Neo is a new package manager for the [Nim programming language](https://nim-lang.org). It aims to:
- Have a clean, maintainable codebase
- Be simple to use
- Fix everything Nimble does badly
- Be as fast as possible (this includes multithreading)
- Interoperate with the existing Nimble infrastructure so that packages using Neo can easily be uploaded to the Nimble index
- Using modern algorithms since we're not scared of breaking things (like using SHA-256 for hashing)
- Add infrastructure for "custom targets" like WASM

# Roadmap
Neo is currently a ~1.1K LoC project, and has the following features ready and working:
- [X] Internal storage area (`~/.local/share/neo`)
- [X] Package lists/indices (stored at `~/.local/share/neo/indices`)
- [X] Internal state is stored as a LevelDB database (at `~/.local/share/neo/state`)
- [X] `neo build` command
- [X] `neo search` command
- [X] `neo init` command
- [X] `neo search` command
- [X] `neo fmt` command
- [X] Naive dependency solver

The following are pending tasks that will hopefully be completed soon:
- [ ] Proper dependency solver
- [ ] Tasks
- [ ] Hooks
- [ ] Proper dependency management
- [ ] `neo info` command

# Building Neo
Neo can be built using Neo itself, or via Nimble. To build it via itself, run:
```
$ neo build
```

# Dependencies
- libcURL

# Usage
## Creating a project
```command
$ neo init myproject
  Project Type:
    1. Binary
    2. Library
    3. Hybrid
  
  License: GPL3

  Description: A super awesome Nim project

  Backend:
    > C
    > C++
    > JavaScript
    > Objective-C
```

## Building your project
```command
$ neo build --arguments --here --are --passed --to --nim
Building myproject with the C backend
```
