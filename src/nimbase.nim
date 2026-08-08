# Nimbase - A CLI for generating C wrappers, OAPI 3.x HTTP clients
# native extensions for other programming languages and more
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/nimbase/nimbase

when isMainModule:
  # Build the CLI with Kapsis
  import pkg/kapsis
  import ./nimbase/commands/[kits_cmd, oapi_cmd, scripts_cmd]

  initKapsis do:
    plugins do:
      dir: "postscripts"
    commands:
      #
      # Build native extensions for other languages
      # from your Nim code
      #
      -- "Native Extensions"
      extension path(module), ?string("--ext"):
        ## Build a native extension for other languages from Nim code
      
      -- "Code generator"
      oapi:
        ## OAPI 3.x utilities
        init:
          ## Create nimbase.oapi.config.yaml
        gen string(spec), string("output"), ?string("--config"), ?bool("-y"):
          ## Generate a Nim client from an OAPI spec or URL
        mock string(spec), ?string("--host"), ?string("--port"):
          ## Start a local mock server from an OAPI spec

      -- "Scripts"
      prescripts:
        ## Pre-generation scripts contributed by kapsis plugins
        list ?string("--dir"):
          ## List available prescripts from plugins in a directory
        run path(target), ?string("--spec"), ?string("--dir"), ?string("--name"):
          ## Run a prescript from plugins in a directory against a target
      postscripts:
        ## Post-generation scripts contributed by kapsis plugins
        list ?string("--dir"):
          ## List available scripts from plugins in a directory
        run path(target), ?string("--spec"), ?string("--dir"), ?string("--name"):
          ## Run postscripts from plugins in a directory against a target

      # -- "Bundlers"
      #   ## Commands for bundling plugins for different package managers
      #   npm path(module):
      #     ## Bundle a JavaScript N-API addon for publishing on npm
      #   pypi path(module):
      #     ## Bundle a Python extension for publishing on PyPI
      #   pie path(module):
      #     ## Bundle a PHP extension for publishing on PIE (PHP Installer for Extensions)
else:
  error("Nothing to see here. Import submodules you need directly")