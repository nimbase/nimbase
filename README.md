<p align="center">
  Nim Codegen — OAPI 3.x clients, C wrappers, FFI bindings & native extensions
</p>

<p align="center">
  <code>nimble install nimbase</code>
</p>

<p align="center">
  <a href="https://github.com/">API reference</a>
</p>

### Why Nimbase?
Generate Nim HTTP clients straight from OpenAPI 3.x specs, generate C/C++ (and
more) wrappers for your Nim libraries, and build your Nim code into FFI native
extensions for high-level programming languages — without learning every detail
of each target language's native API.

## 😍 Key Features
- [x] **Native extensions** — plugin kits for **PHP**, **Ruby**, **Lua (LuaJIT)**, **Python** and **JS (Node/Bun)** via a macro-based DSL
- [x] **C/C++ wrappers & FFI bindings** — generate C headers + bindings for **Go**, **Rust**, **Crystal**, **Nim** and C/C++ straight from your exported symbols
- [x] **OpenAPI 3.x codegen** — generate Nim HTTP client libraries from any JSON / YAML / URL spec
- [x] **Mock server** — spin up a local mock server from an OpenAPI 3.x spec
- [ ] **Package generator** — bundle and publish extensions for `npm`, `pip`/PyPI, `composer`, `gem` and more

> [!NOTE]
> Nimbase used to be part of the [Clue](https://github.com/openpeeps/clue) package.
> Clue now focuses on local package management; this codebase carries on
> everything related to generating native libraries, C wrappers and OpenAPI
> clients.

## Native Extensions

All kits follow the same macro-based DSL pattern. Write your logic once in Nim,
generate native extensions for the target language.

### PHP
```nim
import nimbase/kits/phpkit

phpModule do:
  name = "example"
  version = "0.1.0"

  proc hello(name: string) =
    echo "Hello ", $name, " from Nim!"

  proc add(a: int, b: int) =
    php_zval_long(retTy, zend_long(a + b))
```

- [PHP example](examples/plugin_php/README.md)

### Ruby
```nim
import nimbase/kits/rubykit

rubyModule do:
  name: "Example"
  version: "0.1.0"

  proc hello(name: string) =
    echo "Hello ", name, " from Nim!"

  proc add(a: int, b: int) =
    result = INT2NUM(cint(a + b))
```

- [Ruby example](examples/plugin_ruby/README.md)

### Lua (LuaJIT)
```nim
import nimbase/kits/luakit

luaModule do:
  name: "mylib"

  proc hello(name: string) =
    lua_pushstring(L, cstring("Hello " & name & " from Nim!"))
    return 1

  proc add(a: int, b: int) =
    lua_pushinteger(L, a + b)
    return 1
```

- [Lua example](examples/plugin_lua/README.md)

### Python
```nim
import nimbase/kits/pykit

pythonModule do:
  name: "mylib"

  proc hello(name: string) =
    result = PyUnicode_FromString(cstring("Hello " & name & " from Nim!"))

  proc add(a: int, b: int) =
    result = PyLong_FromLong(a + b)
```

- [Python example](examples/plugin_python/README.md)

### JS (Node.js / Bun)
```nim
import nimbase/kits/jskit

jsModule do:
  name: "mylib"
  # ...
```

Build any kit as a native extension from the CLI or the compiler:

```sh
nimbase extension example.nim --ext:py    # py, rb, lua, php
nim c --app:lib -d:nimbaseExtension --out:build/out.so my_extension.nim
```

<details>
  <summary>Use <code>-d:clueDebugExtension</code> to inspect the generated code 👇</summary>
  Pass this flag when compiling to see the Nim-to-C expansion for any module kit:

```
nim c -d:clueDebugExtension --app:lib -o:out.so my_extension.nim
```
</details>

> [!NOTE]
> All major dynamic languages that support native extensions will be supported
> via plugin kits, with the goal of a unified DSL for defining extensions across
> all supported languages.

## C wrappers & FFI bindings

Mark exports with `{.exportc.}` and generate C headers plus bindings for
Go, Rust, Crystal and Nim in a single step:

```nim
import nimbase/wrapper

type MyEnum* {.exportc.} = enum eA, eB, eC
proc myFunc*(a: cint): cdouble {.exportc, cdecl, dynlib.} = discard

genCHeader(MyEnum, myFunc)
genGoHeader(MyEnum, myFunc)
genRustHeader(MyEnum, myFunc)
genCrystalHeader(MyEnum, myFunc)
genNimHeader(MyEnum, myFunc)
```

Compile with `--app:lib -d:clueBuild` and wrappers are emitted under
`wrappers/` (`c/`, `go/`, `rust/`, `crystal/`, `nim/`). Similar to
[@treeform/genny](https://github.com/treeform/genny), but extended to all
low-level languages from a single Nim definition.

- [Wrappers example](examples/wrappers_example/README.md)

## OpenAPI 3.x codegen

Generate a typed Nim client library from any OpenAPI 3.0 spec — JSON, YAML or a
remote URL:

```sh
nimbase openapi init                       # create a clue.openapi.config.yaml
nimbase openapi gen api.yaml ./client      # generate the client               
nimbase openapi mock petstore.yaml --port:8080
```

## Package generator

_TODO_ — generate the structure and metadata files (`package.json`, `setup.py`,
`*.gemspec`, `composer.json`, etc.) plus the built native library for publishing
directly from the CLI.

## Roadmap
- [ ] Plugin kits — detect and enforce the target language runtime version
- [ ] Plugin kits — more languages (Crystal, Dart, Zig, …)
- [ ] Plugin kits — an `initModules` macro for bulk module definitions
- [ ] Package generator — bundling & publishing for `npm`, PyPI, `composer`, `gem`
- [ ] API bindings — generate header files for C, C++, D, Crystal, Dart, Zig, Rust and more

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/nimbase/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/nimbase/fork)

|  |  |
|---|---|
| <a href="https://opencode.ai/go?ref=BHMEEK48QX"><img src="https://github.com/openpeeps/pistachio/blob/main/.github/opencode.png" alt="OpenCode"></a> | Switch to **Open-Source LLMs** via OpenCode GO, choosing from a variety of powerful models such as DeepSeek, Qwen, Kimi, GLM-5, MiniMax, MiMo. 🍕 [Use our referral link to get started!](https://opencode.ai/go?ref=BHMEEK48QX)|

### 🎩 License
Nimbase | MIT license. [Made by humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.