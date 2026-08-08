# Nimbase - Code Generator. OAPI 3.x clients, wrappers from C/C++, FFI bindings & native extensions
#
# (c) 2026 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/nimbase/nimbase

import std/[os, osproc, strutils, httpclient, algorithm]
import std/editdistance

import pkg/kapsis/runtime
import pkg/kapsis/interactive/prompts
import pkg/openparser/json as openjson

import ../openapi/specparser
import ../openapi/codegen
import ../openapi/oapi_settings
import ../openapi/mockserver
import ./scripts_cmd

const guruListUrl* = "https://api.apis.guru/v2/list.json"

proc derivePkgId(pkg: Package): string =
  if pkg.oapi.isNil: return "client"
  let title = pkg.oapi.info.title.toLowerAscii
  var parts = title.split({' ', '/', '-', '_'})
  if parts.len == 0: return "client"
  result = parts[0]

proc fetchHttpContent(url: string): string =
  ## Fetch a URL over HTTP(S), returning its content or "" on failure.
  var httpClient = newHttpClient()
  try:
    result = httpClient.getContent(url)
  except CatchableError as e:
    displayError("Failed to fetch " & url & ": " & e.msg)
  finally:
    httpClient.close()

proc loadOpenApiSpec(specpath: string): openjson.JsonNode =
  ## Load and parse an OpenAPI spec from a JSON file, YAML file, or URL.
  if specpath.fileExists:
    if specpath.endsWith(".yml") or specpath.endsWith(".yaml"):
      let content = readFile(specpath)
      try:
        result = openjson.fromJson(content)
        if result.isNil:
          displayError("Failed to parse YAML spec")
          return
      except:
        displayError("Failed to parse YAML spec: " & getCurrentExceptionMsg())
        return
    else:
      try:
        result = openjson.fromJsonFile(specpath)
      except:
        displayError("Failed to parse JSON spec: " & getCurrentExceptionMsg())
        return
  elif specpath.startsWith("http://") or specpath.startsWith("https://"):
    let content = fetchHttpContent(specpath)
    if content.len == 0:
      return
    try:
      result = openjson.fromJson(content)
    except:
      displayError("Failed to parse spec: " & getCurrentExceptionMsg())
      return
  else:
    displayError("Spec file not found: " & specpath)

proc shortDescription(desc: string): string =
  ## A short, single-line package description from the spec's `info.description`
  ## (first non-heading sentence, markdown stripped, capped), falling back to a
  ## generic label.
  if desc.len == 0:
    return "Awesome Nim client"
  for line in desc.split('\n'):
    let stripped = line.strip
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    result = stripped
    break
  if result.len == 0:
    return "Awesome Nim client"
  result = result.replace("`", "").replace("**", "")
  let period = result.find(". ")
  if period > 0:
    result = result[0 ..< period + 1]
  if result.len > 80:
    let cut = result[0 ..< 80]
    let space = cut.rfind(' ')
    if space > 40:
      result = cut[0 ..< space] & "..."
    else:
      result = cut & "..."
  result = result.strip
  if result.len == 0:
    result = "Awesome Nim client"

proc generateClient(v: Values; specpath, outputDir: string) =
  ## Shared flow for `oapi.gen` and `oapi.gurugen`: resolve settings, load the
  ## spec, run prescripts/postscripts and emit the client package.
  if dirExists(outputDir):
    if v.has("-y"):
      removeDir(outputDir)
    else:
      displayWarning("Output directory already exists: " & outputDir)
      if not promptConfirm("Overwrite existing directory?"):
        displayInfo("Aborted")
        return
      removeDir(outputDir)

  var skipPrefixPath = ""
  var stripPrefixModule = ""
  var configDescription = ""
  var configPath = ""
  if v.has("--config"):
    configPath = v.get("--config").getStr
  elif fileExists(defaultConfigFile):
    configPath = defaultConfigFile
  if configPath.len > 0 and fileExists(configPath):
    let configContent = readFile(configPath)
    try:
      let settings = parseOApiSettings(configContent)
      skipPrefixPath = settings.prefilters.routePrefix
      stripPrefixModule = settings.prefilters.stripPrefixModule
      configDescription = settings.description
    except CatchableError as e:
      displayWarning("Failed to parse config, using defaults: " & e.msg)

  let root = loadOpenApiSpec(specpath)
  if root.isNil:
    return

  # prescripts run before generation
  discard runScripts(skPre, outputDir, specpath)

  try:
    var pkg = Package(
      id: "",
      description: "Awesome Nim client",
      author: "",
      license: "MIT",
    )

    pkg.parseSpecification(
      root,
      prefs = PackagePreferences(
        verbose: false,
        skipComponentSchemas: v.has("--skipComponentSchemas")
      ),
      skipPrefixPath = skipPrefixPath
    )

    pkg.description = shortDescription(pkg.oapi.info.description)
    if configDescription.len > 0:
      pkg.description = configDescription

    let outputName = outputDir.extractFilename
    pkg.id =
      if outputName.len > 0: outputName
      else: derivePkgId(pkg)

    if pkg.author.len == 0:
      let (gitName, _) = execCmdEx("git config user.name")
      pkg.author = gitName.strip()

    let gen = newGenerator(pkg, outputDir, skipPrefixPath, root, stripPrefixModule)
    gen.generate()

    # postscripts run after generation
    discard runScripts(skPost, outputDir, specpath)

    displaySuccess("Client package generated at " & outputDir)

  except CatchableError as e:
    displayError("Failed to parse spec: " & e.msg)

proc oapiGenCommand*(v: Values) =
  ## Generate a new API client library from OpenAPI spec file
  let specpath = v.get("spec").getStr
  let outputDir = v.get("output").getStr
  generateClient(v, specpath, outputDir)

proc oapiGurugenCommand*(v: Values) =
  ## Generate a client library from an apis.guru API, e.g. "stripe.com"
  let apiName = v.get("apiName").getStr
  let outputDir = v.get("output").getStr

  let listContent = fetchHttpContent(guruListUrl)
  if listContent.len == 0:
    return
  var list: openjson.JsonNode
  try:
    list = openjson.fromJson(listContent)
  except:
    displayError("Failed to parse apis.guru list: " & getCurrentExceptionMsg())
    return

  if list.isNil or not list.hasKey(apiName):
    displayError("API not found in apis.guru: " & apiName)
    var suggestions: seq[tuple[name: string, dist: int]]
    for k in list.keys:
      suggestions.add((k, editDistance(k, apiName)))
    suggestions.sort(proc(a, b: tuple[name: string, dist: int]): int = cmp(a.dist, b.dist))
    if suggestions.len > 0:
      var top: seq[string]
      for s in suggestions[0 .. min(2, suggestions.high)]:
        top.add(s.name)
      displayInfo("Did you mean: " & top.join(", "))
    return

  let entry = list[apiName]
  var version = ""
  if entry.hasKey("preferred"):
    version = entry["preferred"].getStr
  if v.has("--spec-version"):
    version = v.get("--spec-version").getStr
  if version.len == 0 and entry.hasKey("versions") and entry["versions"].kind == JObject:
    for vk in entry["versions"].keys:
      version = vk
      break

  if entry.isNil or entry["versions"].isNil or entry["versions"].kind != JObject or
      not entry["versions"].hasKey(version):
    displayError("Version not found for " & apiName & ": " & version)
    var vs: seq[string]
    if entry["versions"].kind == JObject:
      for vk in entry["versions"].keys:
        vs.add(vk)
    displayInfo("Available versions: " & vs.join(", "))
    return

  let versionInfo = entry["versions"][version]
  if versionInfo.isNil or not versionInfo.hasKey("swaggerUrl"):
    displayError("No spec URL found for " & apiName & " v" & version)
    return
  let swaggerUrl = versionInfo["swaggerUrl"].getStr

  generateClient(v, swaggerUrl, outputDir)

proc oapiInitCommand*(v: Values) =
  ## Create nimbase.oapi.config.yaml
  let configPath = defaultConfigFile
  if fileExists(configPath):
    displayWarning("Config file already exists: " & configPath)
    if not promptConfirm("Overwrite existing file?"):
      displayInfo("Aborted")
      return
  let content = dumpDefaultSettings()
  writeFile(configPath, content)
  displaySuccess("Created " & configPath)

proc oapiMockCommand*(v: Values) =
  ## Command for starting a local mock server from an OpenAPI 3.x spec file or URL
  let specpath = v.get("spec").getStr
  let host =
    if v.has("--host"):
      v.get("--host").getStr
    else:
      "127.0.0.1"
  var port = Port(8080)
  if v.has("--port"):
    try:
      port = Port(parseInt(v.get("--port").getStr))
    except:
      displayError("Invalid --port value: " & v.get("--port").getStr)
      return
  let root = loadOpenApiSpec(specpath)
  if root.isNil:
    return
  startMockServer(root, host, port)
