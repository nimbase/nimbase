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
      openapi:
        ## OpenAPI 3.x utilities
        init:
          ## Initialize a default clue.openapi.config.yaml file
        gen path(spec), string("output"), ?string("--config"), ?bool("-y"):
          ## Generate a new API client library from OpenAPI 3.x spec file.
          ## Automatically runs prescripts before and postscripts after.
        mock path(spec), ?string("--host"), ?string("--port"):
          ## Spin up a local mock server from OpenAPI 3.x spec file

      -- "Scripts"
      prescripts:
        ## Run pre-generation scripts contributed by kapsis plugins
        list ?string("--dir"):
          ## List available prescript commands from plugins in a directory
        run path(target), ?string("--spec"), ?string("--dir"), ?string("--name"):
          ## Run prescript commands from plugins in a directory against a target
      postscripts:
        ## Run post-generation scripts contributed by kapsis plugins
        list ?string("--dir"):
          ## List available postscript commands from plugins in a directory
        run path(target), ?string("--spec"), ?string("--dir"), ?string("--name"):
          ## Run postscript commands from plugins in a directory against a target

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