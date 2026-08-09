import std/json
import std/options
import pkg/openparser/yaml

const defaultConfigFile* = "nimbase.oapi.config.yaml"

type
  PreFilters* = object
    routePrefix*: string
    stripPrefixModule*: string

  OApiSettings* = object
    description*: string
    author*: string
    license*: string
    licenseUrl*: string
    url*: string
    version*: string
    id*: string
    baseUri*: string
    source*: string
    repo*: string
    skipComponentSchemas*: Option[bool]
    verbose*: Option[bool]
    generateTests*: Option[bool]
    prefilters*: PreFilters

proc parseOApiSettings*(yamlContent: string): OApiSettings =
  result = parseYAML(yamlContent, OApiSettings)

proc dumpDefaultSettings*(): YAML =
  let root = %*{
    "description": "",
    "author": "",
    "license": "MIT",
    "licenseUrl": "",
    "url": "",
    "version": "",
    "id": "",
    "baseUri": "",
    "source": "",
    "repo": "",
    "skipComponentSchemas": false,
    "verbose": false,
    "generateTests": true,
    "prefilters": {
      "routePrefix": "",
      "stripPrefixModule": ""
    }
  }
  result = dump(root)
