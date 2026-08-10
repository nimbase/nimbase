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
  - Nimbase OAPI configurator via `nimbase.oapi.config.yaml`
  - Mock server, spin up a local mock server from an OAPI 3.x spec
  - Generate nimble tests from OAPI 3.x spec
- Generate native extensions from Nim code to Python, Lua, Ruby, PHP, NodeJS (or any NAPI-compatible JS runtimes)
- Generate low-level Nim wrappers from C/C++
- Generate Bindings from Nim to Go, Python, Rust, Zig, D, and more

### OpenAPI 3.x codegen

OAPI 3.x CLI commands:

```sh
nimbase oapi.init                            # create a nimbase.oapi.config.yaml
nimbase oapi.gen api.yaml ./client           # auto-detects nimbase.oapi.config.yaml
nimbase oapi.gen api.yaml ./client --config other.yaml   # or pass one explicitly
nimbase oapi.gurugen "stripe.com" ./stripe   # generate from apis.guru
nimbase oapi.mock petstore.yaml --port:8080
```

`gurugen` looks up an API in [apis.guru](https://api.apis.guru/v2/list.json) by its
key (e.g. `stripe.com`, `1password.com:events`) and uses the API's `preferred`
spec version unless `--spec-version` is given:

```sh
nimbase oapi.gurugen "1password.com:events" ./events --spec-version:1.0.0
```

Generator settings live in `nimbase.oapi.config.yaml` (auto-loaded from the
current directory unless `--config` is given):

```yaml
description: ""                # override the package description (default: spec info.description)
author: ""                     # package author (default: `git config user.name`)
license: "MIT"                 # package license (default: MIT)
licenseUrl: ""                 # license link shown in the generated README
url: ""                        # package homepage/repo URL shown in the generated README
version: ""                    # override the generated package version (default: 0.1.0)
id: ""                         # override the package/module name (default: output dir basename)
baseUri: ""                    # override the default client base URL (default: spec's first server)
source: ""                     # spec source used by the generated nimbase.yml (guru key → gurugen, URL/path → oapi.gen)
repo: ""                       # GitHub repo name for the generated README badges/links (default: package name)
generator: ""                  # custom regeneration command for the generated nimbase.yml (e.g. ./scripts/gen.sh)
skipComponentSchemas: false    # skip generating component schemas (same as --skipComponentSchemas)
verbose: false                 # verbose generation output
generateTests: true            # generate the tests/ suite (mock server + per-module tests)
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

### Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/nimbase/nimbase/issues)
- 👋 Wanna help? [Fork it!](https://github.com/nimbase/nimbase/fork)

### License
MIT license.