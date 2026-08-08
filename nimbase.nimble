# Package

version       = "0.1.0"
author        = "OpenPeeps"
description   = "Nim Codegen – OAPI 3.x, C wrappers, FFI bindings & native extensions"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["nimbase"]

installDirs = @["nimbase"]


# Dependencies

requires "nim >= 2.2.10"
requires "semver >= 1.2.3"
requires "kapsis >= 0.4.0"
requires "boogie >= 0.1.0"
requires "openparser >= 0.1.9"
requires "sweetsyntax >= 0.1.0"
