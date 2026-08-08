<p align="center">
  Nim Codegen — OAPI 3.x clients, wrappers from C/C++, FFI bindings & native extensions
</p>

<p align="center">
  <code>nimble install nimbase</code>
</p>

<p align="center">
  <a href="https://nimbase.github.io/nimbase">API reference</a>
</p>

## Features
- OpenAPI 3.x HTTP client generator from `JSON`/`YAML`/`URL` OAPI spec
- Mock server, spin up a local mock server from an OpenAPI 3.x spec
- Generate nimble tests from OAPI 3.x spec
- Generate native extensions from Nim code to Python, Lua, Ruby, PHP, NodeJS (or any NAPI-compatible JS runtimes)
- Generate low-level Nim wrappers from C/C++
- Generate Bindings from Nim to Go, Python, Rust, Zig, D, and more

> [!NOTE]
> Nimbase used to be part of the [Clue](https://github.com/openpeeps/clue) package.
> Clue now focuses on local package management; this codebase carries on
> everything related to generating native libraries, C wrappers and OpenAPI
> clients.

## OpenAPI 3.x codegen

Generate a typed Nim client library from any OpenAPI 3.0 spec — JSON, YAML or a
remote URL:

```sh
nimbase oapi init                            # create a nimbase.oapi.config.yaml
nimbase oapi gen api.yaml ./client           # auto-detects nimbase.oapi.config.yaml
nimbase oapi gen api.yaml ./client --config other.yaml   # or pass one explicitly
nimbase oapi gurugen "stripe.com" ./stripe   # generate from apis.guru
nimbase oapi mock petstore.yaml --port:8080
```

`gurugen` looks up an API in [apis.guru](https://api.apis.guru/v2/list.json) by its
key (e.g. `stripe.com`, `1password.com:events`) and uses the API's `preferred`
spec version unless `--spec-version` is given:

```sh
nimbase oapi gurugen "1password.com:events" ./events --spec-version:1.0.0
```

Generator settings live in `nimbase.oapi.config.yaml` (auto-loaded from the
current directory unless `--config` is given):

```yaml
prefilters:
  routePrefix: ""              # strip a leading path prefix from endpoint idents
  stripPrefixModule: ""        # strip a common prefix from generated module names
```

For example, AWS specs group every operation under `?X-Amz-Target=...`, producing
modules like `x_amz_target_awslicensemanager_acceptgrant.nim`. Setting
`stripPrefixModule: "x_amz_target_awslicensemanager"` generates `acceptgrant.nim`
instead.

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
- 🐛 Found a bug? [Create a new Issue](https://github.com/nimbase/nimbase/issues)
- 👋 Wanna help? [Fork it!](https://github.com/nimbase/nimbase/fork)

### 🎩 License
Nimbase | MIT license. [Made by humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.