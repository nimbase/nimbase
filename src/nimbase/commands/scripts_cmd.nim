# Nimbase - Prescript & postscript engines
#
# Runs pre- and post-generation scripts contributed by kapsis plugins. Scripts
# are shared libraries (built with `nim c --app:lib`) that declare CLI commands
# against `kapsis/pluginapi`; each command receives the generated package
# directory as `path` and, when declared, the OpenAPI spec as `spec`.
#
# `openapi.gen` invokes prescripts before generating and postscripts after.
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/nimbase/nimbase

import std/[os, json, tables]

import pkg/kapsis
import pkg/kapsis/runtime
import pkg/kapsis/plugins
import pkg/kapsis/interactive/prompts

type ScriptKind* = enum
  skPre, skPost

proc scriptLabel*(kind: ScriptKind): string =
  case kind
  of skPre: "prescript"
  of skPost: "postscript"

proc scriptDirName*(kind: ScriptKind): string =
  case kind
  of skPre: "prescripts"
  of skPost: "postscripts"

proc pluginDir(kind: ScriptKind, raw: string): string =
  ## Resolve the plugin directory the engine should scan. A relative `--dir`
  ## is resolved against the current working directory (kapsis resolves it
  ## against the app executable otherwise); without `--dir` we look for a
  ## local `./prescripts` / `./postscripts` directory.
  if raw.len > 0:
    if isAbsolute(raw):
      return raw
    return getCurrentDir() / raw
  let local = getCurrentDir() / scriptDirName(kind)
  if dirExists(local):
    return local
  ""

proc runScriptCommands(kind: ScriptKind; dir, nameFilter: string;
    values: Table[string, string]; quiet = false): int =
  ## Load every plugin command from `dir` and invoke each with the JSON args
  ## built from its declared arguments (matching known values).
  let host = initPluginHost(getAppFilename(), dir)
  let label = scriptLabel(kind)
  for name, cmd in host.commands:
    if nameFilter.len > 0 and name != nameFilter:
      continue
    var raw = newJObject()
    for arg in cmd.args:
      if values.hasKey(arg.name):
        raw[arg.name] = %values[arg.name]
    let fn = cast[PluginRunFn](cmd.plugin.getHandle().symAddr(cmd.symbol))
    if fn.isNil:
      displayError(label & " symbol not found: " & cmd.symbol)
      continue
    let resp = $fn(cstring($raw))
    inc result
    try:
      let node = parseJson(resp)
      if node.hasKey("error"):
        displayError(label & " " & name & " failed: " & node["error"].getStr)
      else:
        displaySuccess(label & " " & name & " applied")
    except CatchableError:
      displayError(label & " " & name & " returned an invalid response: " & resp)
  if result == 0 and not quiet:
    if nameFilter.len > 0:
      displayWarning(label & " not found: " & nameFilter)
    else:
      displayWarning("No " & scriptDirName(kind) & " commands found")

proc runScripts*(kind: ScriptKind; target, spec: string; dir = ""): int =
  ## Run all script commands of `kind` against `target` (the package/output
  ## dir) with `spec` available to commands that declare it. Used by the CLI
  ## handlers and by `openapi.gen` (silent when no scripts are present).
  var values = initTable[string, string]()
  values["path"] = target
  if spec.len > 0:
    values["spec"] = spec
  runScriptCommands(kind, pluginDir(kind, dir), "", values, quiet = true)

proc listScripts(kind: ScriptKind, dir: string) =
  let host = initPluginHost(getAppFilename(), dir)
  if host.commands.len == 0:
    displayWarning("No " & scriptDirName(kind) & " commands found")
    return
  for name, cmd in host.commands:
    if cmd.description.len > 0:
      echo name, "\t", cmd.description
    else:
      echo name

proc prescriptsListCommand*(v: Values) =
  ## List prescript commands contributed by plugins
  let dir =
    if v.has("--dir"): pluginDir(skPre, v.get("--dir").getStr)
    else: pluginDir(skPre, "")
  listScripts(skPre, dir)

proc prescriptsRunCommand*(v: Values) =
  ## Run prescript commands against a target
  let target = v.get("target").getPath.path
  let spec =
    if v.has("--spec"): v.get("--spec").getStr
    else: ""
  let dir =
    if v.has("--dir"): pluginDir(skPre, v.get("--dir").getStr)
    else: pluginDir(skPre, "")
  let nameFilter =
    if v.has("--name"): v.get("--name").getStr
    else: ""
  var values = initTable[string, string]()
  values["path"] = target
  if spec.len > 0:
    values["spec"] = spec
  discard runScriptCommands(skPre, dir, nameFilter, values)

proc postscriptsListCommand*(v: Values) =
  ## List postscript commands contributed by plugins
  let dir =
    if v.has("--dir"): pluginDir(skPost, v.get("--dir").getStr)
    else: pluginDir(skPost, "")
  listScripts(skPost, dir)

proc postscriptsRunCommand*(v: Values) =
  ## Run postscript commands against a target
  let target = v.get("target").getPath.path
  let spec =
    if v.has("--spec"): v.get("--spec").getStr
    else: ""
  let dir =
    if v.has("--dir"): pluginDir(skPost, v.get("--dir").getStr)
    else: pluginDir(skPost, "")
  let nameFilter =
    if v.has("--name"): v.get("--name").getStr
    else: ""
  var values = initTable[string, string]()
  values["path"] = target
  if spec.len > 0:
    values["spec"] = spec
  discard runScriptCommands(skPost, dir, nameFilter, values)
