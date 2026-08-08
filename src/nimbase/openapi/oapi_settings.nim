import std/json
import pkg/openparser/yaml

const defaultConfigFile* = "nimbase.oapi.config.yaml"

type
  PreFilters* = object
    routePrefix*: string
    stripPrefixModule*: string

  OApiSettings* = object
    prefilters*: PreFilters

proc parseOApiSettings*(yamlContent: string): OApiSettings =
  result = parseYAML(yamlContent, OApiSettings)

proc dumpDefaultSettings*(): YAML =
  let root = %*{
    "prefilters": {
      "routePrefix": "",
      "stripPrefixModule": ""
    }
  }
  result = dump(root)
