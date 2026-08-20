# Nimbase - Code Generator. OAPI 3.x clients, wrappers from C/C++, FFI bindings & native extensions
#
# (c) 2026 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/nimbase/nimbase

import std/[os, osproc, strutils, httpclient, algorithm]
import std/options
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

proc rawSpecContent(specpath: string): string =
  ## Raw spec bytes from a local file or URL ("" on failure).
  if specpath.fileExists:
    result = readFile(specpath)
  elif specpath.startsWith("http://") or specpath.startsWith("https://"):
    result = fetchHttpContent(specpath)

proc resolveSpecUrl(apiName: string; specVersion = ""): string =
  ## Resolve the apis.guru swaggerUrl for an API identifier, e.g. "hetzner.cloud".
  ## Returns "" when the API or version cannot be resolved.
  let listContent = fetchHttpContent(guruListUrl)
  if listContent.len == 0:
    return ""
  var list: openjson.JsonNode
  try:
    list = openjson.fromJson(listContent)
  except CatchableError as e:
    displayError("Failed to parse apis.guru list: " & e.msg)
    return ""

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
    return ""

  let entry = list[apiName]
  var version = specVersion
  if version.len == 0 and entry.hasKey("preferred"):
    version = entry["preferred"].getStr
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
    return ""

  let versionInfo = entry["versions"][version]
  if versionInfo.isNil or not versionInfo.hasKey("swaggerUrl"):
    displayError("No spec URL found for " & apiName & " v" & version)
    return ""
  result = versionInfo["swaggerUrl"].getStr

proc shortDescription(desc: string): string =
  ## A short, single-line package description from the spec's `info.description`
  ## (first non-heading sentence, markdown stripped, capped), falling back to a
  ## generic label.
  result = "Awesome Nim client"
  if desc.len == 0: return # result
  for line in desc.split('\n'):
    let stripped = line.strip
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    result = stripped
    break
  if result.len == 0: return # result
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

  var settings = OApiSettings()
  var configPath = ""
  if v.has("--config"):
    configPath = v.get("--config").getStr
  elif fileExists(defaultConfigFile):
    configPath = defaultConfigFile
  if configPath.len > 0 and fileExists(configPath):
    let configContent = readFile(configPath)
    try:
      settings = parseOApiSettings(configContent)
    except CatchableError as e:
      displayWarning("Failed to parse config, using defaults: " & e.msg)

  let root = loadOpenApiSpec(specpath)
  if root.isNil:
    return

  if v.has("--save-spec"):
    let savePath = v.get("--save-spec").getStr
    if savePath.len > 0:
      let raw = rawSpecContent(specpath)
      if raw.len > 0:
        let parent = savePath.parentDir
        if parent.len > 0:
          createDir(parent)
        writeFile(savePath, raw)
      else:
        displayWarning("Could not fetch raw spec for --save-spec: " & savePath)

  # prescripts run before generation
  discard runScripts(skPre, outputDir, specpath)

  try:
    var pkg = Package(
      id: settings.id,
      description: settings.description,
      author: settings.author,
      license: settings.license,
      licenseUrl: settings.licenseUrl,
      url: settings.url,
      pkgVersion: "0.1.0",
    )
    if pkg.license.len == 0:
      pkg.license = "MIT"
    if pkg.description.len == 0:
      pkg.description = "Awesome Nim client"

    pkg.parseSpecification(
      root,
      prefs = PackagePreferences(
        verbose: settings.verbose.get(false),
        skipComponentSchemas: v.has("--skipComponentSchemas") or
          settings.skipComponentSchemas.get(false)
      ),
      skipPrefixPath = settings.prefilters.routePrefix
    )

    pkg.description = shortDescription(pkg.oapi.info.description)
    if settings.description.len > 0:
      pkg.description = settings.description

    let outputName = outputDir.extractFilename
    if settings.id.len == 0:
      pkg.id =
        if outputName.len > 0: outputName
        else: derivePkgId(pkg)

    if pkg.author.len == 0:
      let (gitName, _) = execCmdEx("git config user.name")
      pkg.author = gitName.strip()

    if settings.version.len > 0:
      pkg.pkgVersion = settings.version

    let gen = newGenerator(pkg, outputDir,
      settings.prefilters.routePrefix, root, settings.prefilters.stripPrefixModule)
    gen.generateTests = settings.generateTests.get(true)
    gen.generateExamples = settings.generateExamples.get(false)
    gen.source = settings.source
    gen.repo = settings.repo
    gen.generator = settings.generator
    if settings.baseUri.len > 0:
      gen.baseUri = settings.baseUri
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
  let specVersion =
    if v.has("--spec-version"): v.get("--spec-version").getStr
    else: ""
  let swaggerUrl = resolveSpecUrl(apiName, specVersion)
  if swaggerUrl.len == 0:
    return
  generateClient(v, swaggerUrl, outputDir)

proc oapiDiffCommand*(v: Values) =
  ## Compare a remote OpenAPI spec (URL or apis.guru id) with a local spec file.
  ## Exit code: 0 identical, 1 different, 2 error.
  let remote = v.get("remote").getStr
  let local = v.get("local").getStr

  if not local.fileExists:
    displayError("Local spec file not found: " & local)
    quit(2)
  if not (local.endsWith(".json") or local.endsWith(".yaml") or local.endsWith(".yml")):
    displayError("Unsupported local spec format (expected .json/.yaml/.yml): " & local)
    quit(2)

  let remoteUrl =
    if remote.startsWith("http://") or remote.startsWith("https://"):
      remote
    else:
      resolveSpecUrl(remote)
  if remoteUrl.len == 0:
    quit(2)

  let remoteContent = fetchHttpContent(remoteUrl)
  if remoteContent.len == 0:
    quit(2)

  var remoteNode, localNode: openjson.JsonNode
  try:
    remoteNode = openjson.fromJson(remoteContent)
    localNode = openjson.fromJson(readFile(local))
  except CatchableError as e:
    displayError("Failed to parse spec: " & e.msg)
    quit(2)
  if remoteNode.isNil or localNode.isNil:
    displayError("Failed to parse spec")
    quit(2)

  if remoteNode == localNode:
    displayInfo("Specs are identical: " & local)
    quit(0)
  else:
    displayInfo("Specs differ: " & local)
    quit(1)

proc oapiInitCommand*(v: Values) =
  ## Scaffold a package: config, workflows, gitignore, and LICENSE.
  ## After init, fill the config (set source/generator) and push — the
  ## nimbase-bot workflow regenerates src/ and tests/ on CI.
  if not dirExists(".github/workflows"):
    createDir(".github/workflows")

  let configPath = defaultConfigFile
  if fileExists(configPath):
    displayWarning("Config file already exists: " & configPath)
    if not promptConfirm("Overwrite existing file?"):
      displayInfo("Aborted")
      return
  writeFile(configPath, dumpDefaultSettings())
  # writeFile(".gitignore", staticRead("openapi/stubs/starter_gitignore"))
  # writeFile("LICENSE", staticRead("openapi/stubs/starter_license"))
  # writeFile(".github/workflows/docs.yml", staticRead("openapi/stubs/starter_workflow_docs.yml"))
  # writeFile(".github/workflows/test.yml", staticRead("openapi/stubs/starter_workflow_test.yml"))
  # writeFile(".github/workflows/nimbase.yml", staticRead("openapi/stubs/starter_workflow_nimbase.yml"))

  displaySuccess("Scaffolded nimbase.oapi.config.yaml + workflows + LICENSE + .gitignore")

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
