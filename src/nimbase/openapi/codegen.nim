# Nimbase - Code Generator. OAPI 3.x clients, wrappers from C/C++, FFI bindings & native extensions
#
# (c) 2026 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/nimbase/nimbase

import std/[tables, json, strformat, strutils, os, times, sequtils, wordwrap, sets]
import pkg/openparser/json as openjson
import ./ir, ./specparser

const nimKeywords = ["addr", "and", "as", "asm", "bind", "block", "break", "case",
  "cast", "concept", "const", "continue", "converter", "defer", "discard",
  "distinct", "div", "do", "elif", "else", "end", "enum", "except", "export",
  "finally", "for", "from", "func", "if", "import", "in", "include", "interface",
  "is", "isnot", "iterator", "let", "macro", "method", "mixin", "mod", "nil",
  "not", "notin", "object", "of", "or", "out", "proc", "ptr", "raise", "ref",
  "return", "shl", "shr", "static", "template", "try", "tuple", "type", "using",
  "var", "when", "while", "xor", "yield"]

proc safeIdent(name: string): string =
  if name in nimKeywords: "`" & name & "`" else: name

proc fmtDocComment(indent: string, desc: string; maxWidth = 80): string =
  if desc.len == 0: return
  for line in desc.splitLines:
    let trimmed = line.strip
    if trimmed.len == 0:
      result &= &"{indent}##\n"
    else:
      let wrapped = wrapWords(trimmed, maxWidth)
      for wLine in wrapped.splitLines:
        result &= &"{indent}## {wLine.strip}\n"

const
  nimbaseOpenparserVersion = "0.1.9"
  stubMetaclient = staticRead("stubs/metaclient.nim")
  stubMetaclientOAuth2 = staticRead("stubs/metaclient_oauth2.nim")
  stubNimble = staticRead("stubs/pkg.nimble")
  stubHeader = staticRead("stubs/header.txt")
  stubMockserver = staticRead("mockserver.nim")
  stubStarterReadme = staticRead("stubs/starter_readme.md")
  stubStarterGitignore = staticRead("stubs/starter_gitignore")
  stubStarterLicense = staticRead("stubs/starter_license")
  stubWorkflowDocs = staticRead("stubs/starter_workflow_docs.yml")
  stubWorkflowTest = staticRead("stubs/starter_workflow_test.yml")
  stubWorkflowNimbase = staticRead("stubs/starter_workflow_nimbase.yml")
  stubWorkflowRunnableExamples = staticRead("stubs/starter_workflow_runnable_examples.yml")
  stubExampleBasic = staticRead("stubs/example_basic.nim")

type
  Generator* = ref object
    pkg*: Package
    outputDir*: string
    pkgName*: string
    pkgIdent*: string
    baseUri*: string
    schemas*: OrderedTableRef[string, Schema]
    authType*: string
    oauthTokenUrl*: string
    oauthAuthUrl*: string
    skipPrefixPath*: string
    stripPrefixModule*: string
    generateTests*: bool = true
    generateExamples*: bool = false
    source*: string
    repo*: string
    generator*: string
    spec*: openjson.JsonNode

proc toPascalCase(s: string): string =
  var nextUpper = true
  for c in s:
    if c.isAlphaAscii or c.isDigit:
      if nextUpper:
        add result, c.toUpperAscii
        nextUpper = false
      else:
        add result, c
    else:
      nextUpper = true

proc toSnakeCase(s: string): string =
  for i, c in s:
    if c.isUpperAscii:
      if i > 0:
        add result, '_'
      add result, c.toLowerAscii
    else:
      add result, c

proc nimFieldName(propName: string): string =
  ## A valid Nim object field identifier for a schema property: snake_case,
  ## leading underscores stripped (`_tag` -> `tag`) and every other
  ## non-alphanumeric character collapsed to `_` (`$schema` -> `schema`).
  ## Guards against empty and digit-leading identifiers.
  result = toSnakeCase(propName)
  var cleaned = ""
  var prevUnd = false
  for c in result:
    if c.isAlphaAscii or c.isDigit:
      cleaned.add(c)
      prevUnd = false
    elif not prevUnd:
      cleaned.add('_')
      prevUnd = true
  if cleaned.len > 0 and cleaned[^1] == '_':
    cleaned.setLen(cleaned.len - 1)
  result = cleaned
  while result.len > 0 and result[0] == '_':
    result = result[1 .. ^1]
  if result.len == 0:
    result = "field"
  if result[0].isDigit:
    result = "f" & result

proc toCamelCase(s: string): string =
  var nextUpper = false
  for c in s:
    if c.isAlphaAscii or c.isDigit:
      if nextUpper:
        add result, c.toUpperAscii
        nextUpper = false
      else:
        add result, c
    else:
      nextUpper = true

proc sanitizeIdent(s: string): string =
  ## Coerce any string into a valid Nim identifier: non-alphanumeric chars
  ## become underscores (runs collapsed), leading/trailing underscores
  ## stripped, digit-leading and empty results guarded.
  var prevUnd = false
  for c in s:
    if c.isAlphaAscii or c.isDigit:
      result.add(c)
      prevUnd = false
    elif not prevUnd:
      result.add('_')
      prevUnd = true
  if result.len > 0 and result[^1] == '_':
    result.setLen(result.len - 1)
  if result.len == 0:
    result = "field"
  if result[0].isDigit:
    result = "f" & result

proc paramIdent(name: string): string =
  ## A valid Nim identifier for a parameter: camelCase, sanitized
  ## (`location[directory]` -> `locationDirectory`).
  safeIdent(sanitizeIdent(toCamelCase(name)))

proc enumFieldName(val: string): string =
  ## A valid Nim enum field identifier for an enum value: camelCase,
  ## sanitized (`2EBOX` -> `f2EBOX`, `4_72` -> `f472`).
  sanitizeIdent(toCamelCase(val))

proc toModuleName(tag: string): string =
  ## Convert an arbitrary tag/group name into a valid Nim module identifier:
  ## lowercased, with every non-alphanumeric character collapsed to `_`.
  ## e.g. "opencode HttpApi" -> "opencode_httpapi", "session questions" ->
  ## "session_questions". Guards against empty names and digit-leading idents.
  var prevSep = true
  for c in tag.toLowerAscii:
    if c.isAlphaAscii or c.isDigit:
      result.add(c)
      prevSep = false
    elif not prevSep:
      result.add('_')
      prevSep = true
  if result.len > 0 and result[^1] == '_':
    result.setLen(result.len - 1)
  if result.len == 0 or result[0].isDigit:
    result = "_" & result

proc genEndpoint*(path: string, skipPrefixPath: sink string = "";
    stripPrefixModule: sink string = ""): tuple[ident, module, endpoint: string] =
  var i = 0
  while i <= path.high:
    case path[i]
    of '/', '_', '-':
      if i != 0:
        add result.module, '_'
      inc i
      while i <= path.high and path[i] notin Letters:
        inc i
      if i <= path.high:
        add result.ident, path[i].toUpperAscii
        add result.module, path[i]
    of '{', '}':
      discard
    of '#', '=', '.', ':':
      if i != 0:
        add result.module, '_'
      inc i
      while i <= path.high and path[i] notin Letters:
        inc i
      if i <= path.high:
        add result.ident, path[i].toUpperAscii
        add result.module, path[i]
    else:
      add result.ident, path[i]
      add result.module, path[i]
    inc i
  result.endpoint = path
  if skipPrefixPath.len > 0 and result.ident.startsWith(skipPrefixPath):
    result.ident = result.ident[skipPrefixPath.len .. ^1]
  result.module = result.module.toLowerAscii
  if stripPrefixModule.len > 0:
    if result.module.startsWith(stripPrefixModule):
      result.module = result.module[stripPrefixModule.len .. ^1]
      while result.module.len > 0 and result.module[0] == '_':
        result.module = result.module[1 .. ^1]
    var normPrefix = stripPrefixModule.toLowerAscii
    normPrefix = normPrefix.replace("_", "")
    var normIdent = result.ident.toLowerAscii
    normIdent = normIdent.replace("_", "")
    if normPrefix.len > 0 and normIdent.startsWith(normPrefix):
      result.ident = result.ident[normPrefix.len .. ^1]

proc schemaNameToTypeName(name: string): string =
  toPascalCase(name)

proc schemaNameToEnumName(name: string): string =
  toPascalCase(name)

proc computeTypeNames(schemas: OrderedTableRef[string, Schema]): Table[string, string] =
  ## Deterministic mapping of schema name -> unique Nim type name. Schema names
  ## that sanitize to the same PascalCase identifier (e.g. `QuestionReplied`
  ## and `question.replied`) get a numeric suffix so generated types never
  ## collide.
  result = initTable[string, string]()
  if schemas.isNil:
    return
  var used = initHashSet[string]()
  for schemaName, schema in schemas.pairs:
    let base = schemaNameToTypeName(schemaName)
    var candidate = base
    var n = 2
    while candidate in used:
      candidate = base & $n
      inc n
    used.incl(candidate)
    result[schemaName] = candidate

proc typeNameOf(typeNames: Table[string, string], name: string): string =
  typeNames.getOrDefault(name, schemaNameToTypeName(name))

proc nimTypeForSchema*(schema: Schema, schemas: OrderedTableRef[string, Schema];
    typeNames: Table[string, string] = initTable[string, string]();
    typeNameHint = ""; qualify = false): string =
  if schema.isNil:
    return "JsonNode"
  if schema.refPath.len > 0:
    let parts = schema.refPath.split("/")
    let name = typeNameOf(typeNames, parts[^1])
    return (if qualify: "types." & name else: name)
  case schema.fieldType
  of stString:
    if schema.enumValues.len > 0:
      let name = if schema.name.len > 0: schema.name else: typeNameHint
      if name.len > 0:
        return schemaNameToEnumName(name)
    return "string"
  of stInteger:
    if schema.integerFormat == int32:
      return "int32"
    return "int64"
  of stNumber:
    return "float64"
  of stBoolean:
    return "bool"
  of stArray:
    if not schema.items.isNil:
      return &"seq[{nimTypeForSchema(schema.items, schemas, typeNames, qualify = qualify)}]"
    return "seq[JsonNode]"
  of stObject:
    if schema.name.len > 0:
      let name = typeNameOf(typeNames, schema.name)
      return (if qualify: "types." & name else: name)
    return "JsonNode"

proc pascalSingular(tag: string): string =
  let singular =
    if tag.endsWith("s"): tag[0..^2]
    else: tag
  toPascalCase(singular)

proc paramHasEnum(param: Parameter): bool =
  param.schema != nil and param.schema.enumValues.len > 0

proc paramIsSimpleArray(param: Parameter): bool =
  param.schema != nil and param.schema.fieldType == stArray and
    param.schema.items != nil and param.schema.items.enumValues.len == 0

proc enumParamNimType(param: Parameter; tag: string): string =
  let enumName = safeIdent(pascalSingular(tag) & toPascalCase(param.name) & "Option")
  "set[" & enumName & "]"

proc enumParamDefault(param: Parameter; tag: string): string =
  if paramHasEnum(param): "{}"
  elif paramIsSimpleArray(param): "@[]"
  else: ""

proc paramDefaultValue(param: Parameter): string =
  if param.schema.isNil or param.schema.default.isNil or param.schema.default.kind == JNull:
    return
  let d = param.schema.default
  case param.schema.fieldType
  of stString:
    result = "\"" & d.getStr & "\""
  of stInteger:
    if d.kind == JInt:
      result = $d.getInt
  of stNumber:
    if d.kind == JFloat:
      result = $d.getFloat
  of stBoolean:
    result = if d.getBool: "true" else: "false"
  else: discard

proc isRefSchemaNullable(refPath: string; schemas: OrderedTableRef[string, Schema]): bool =
  if refPath.len == 0: return false
  let parts = refPath.split("/")
  let name = parts[^1]
  schemas.hasKey(name) and schemas[name] != nil and schemas[name].nullable

proc isOptionalField(propName: string; propSchema: Schema; schema: Schema;
                     schemas: OrderedTableRef[string, Schema]): bool =
  if propName notin schema.required:
    return true
  if propSchema.nullable:
    return true
  if isRefSchemaNullable(propSchema.refPath, schemas):
    return true

proc isOptionalField(propName: string; propSchema: Schema; required: seq[string];
                     schemas: OrderedTableRef[string, Schema]): bool =
  if propName notin required:
    return true
  if propSchema.nullable:
    return true
  if isRefSchemaNullable(propSchema.refPath, schemas):
    return true

proc genEnumForQueryParam(param: Parameter; tag: string): string =
  let enumName = safeIdent(pascalSingular(tag) & toPascalCase(param.name) & "Option")
  result = &"  {enumName}* = enum\n"
  for val in param.schema.enumValues:
    let fieldName = sanitizeIdent(toCamelCase(param.name) & toPascalCase(val))
    result &= &"    {fieldName} = \"{val}\"\n"

proc normIdent(s: string): string =
  ## Normalize an identifier for Nim's style-insensitive name comparison
  ## (case- and underscore-insensitive): lowercase, underscores removed.
  result = s.toLowerAscii
  result = result.replace("_", "")

proc collectAllOfProperties(schema: Schema; schemas: OrderedTableRef[string, Schema];
    visited: var HashSet[string]; props: var OrderedTableRef[string, Schema];
    required: var seq[string]) =
  ## Merge `properties`/`required` from an `allOf` chain into `props`/`required`,
  ## following `$ref` links into the components schemas table.
  if schema.isNil:
    return
  if schema.refPath.len > 0:
    let parts = schema.refPath.split("/")
    let name = parts[^1]
    let key = normIdent(name)
    if key notin visited and schemas != nil and schemas.hasKey(name):
      visited.incl(key)
      collectAllOfProperties(schemas[name], schemas, visited, props, required)
    return
  if not schema.properties.isNil:
    for propName, propSchema in schema.properties.pairs:
      props[propName] = propSchema
  for r in schema.required:
    if r notin required:
      required.add(r)
  for sub in schema.allOf:
    collectAllOfProperties(sub, schemas, visited, props, required)

proc mergedObjectSchema(schema: Schema; schemas: OrderedTableRef[string, Schema]):
    tuple[props: OrderedTableRef[string, Schema], required: seq[string]] =
  ## Resolve an object schema (including `allOf` chains) into its merged
  ## properties and required fields.
  result.props = newOrderedTable[string, Schema]()
  var visited = initHashSet[string]()
  collectAllOfProperties(schema, schemas, visited, result.props, result.required)

proc enumFieldNameUnique(val: string, enumName: string,
    reserved: HashSet[string]): string =
  ## A valid Nim enum field identifier that does not collide
  ## (style-insensitively) with any type name in the module.
  result = enumFieldName(val)
  var n = 2
  let base = result
  while normIdent(result) in reserved:
    result = base & $n
    inc n

proc genTypeDefinition*(schemaName: string, schema: Schema, schemas: OrderedTableRef[string, Schema];
    typeNames: Table[string, string] = initTable[string, string]();
    reserved: HashSet[string] = initHashSet[string]()): string =
  if schema.refPath.len > 0:
    let refParts = schema.refPath.split("/")
    let targetType = typeNameOf(typeNames, refParts[refParts.high])
    let typeName = typeNameOf(typeNames, schemaName)
    if typeName != targetType:
      result = &"  {typeName}* = {targetType}\n"
    return
  case schema.fieldType
  of stObject:
    let typeName = typeNameOf(typeNames, schemaName)
    result = &"  {typeName}* = ref object of RootObj\n"
    result &= fmtDocComment("    ", schema.description)
    let (props, required) = mergedObjectSchema(schema, schemas)
    for propName, propSchema in props.pairs:
      let nimName = safeIdent(nimFieldName(propName))
      let nimType = nimTypeForSchema(propSchema, schemas, typeNames)
      if isOptionalField(propName, propSchema, required, schemas):
        result &= &"    {nimName}*: Option[{nimType}]\n"
      else:
        result &= &"    {nimName}*: {nimType}\n"
      result &= fmtDocComment("      ", propSchema.description)
  of stString:
    if schema.enumValues.len > 0:
      let enumName = schemaNameToEnumName(schemaName)
      result = &"  {enumName}* = enum\n"
      result &= fmtDocComment("    ", schema.description)
      var seenValues = initHashSet[string]()
      for val in schema.enumValues:
        # skip duplicate wire values: Nim's string-enum parsing is
        # underscore/case-insensitive, so values that normalize identically
        # (e.g. `STAR_TRACK_EXPRESS` / `STARTRACK_EXPRESS`) cannot coexist
        let key = normIdent(val)
        if key in seenValues:
          continue
        seenValues.incl(key)
        let fieldName = enumFieldNameUnique(val, enumName, reserved)
        result &= &"    {fieldName} = \"{val}\"\n"
    else:
      # primitive alias (e.g. a `$ref`d string schema)
      result = &"  {typeNameOf(typeNames, schemaName)}* = string\n"
  else:
    # emit an alias for non-object/non-enum schemas (arrays, scalars) so
    # `$ref` references to them resolve (e.g. `QuestionAnswer* = seq[string]`).
    let baseType = nimTypeForSchema(schema, schemas, typeNames)
    if baseType.len > 0:
      result = &"  {typeNameOf(typeNames, schemaName)}* = {baseType}\n"

proc genTypes*(schemas: OrderedTableRef[string, Schema]): string =
  let typeNames = computeTypeNames(schemas)
  var reserved = initHashSet[string]()
  if not schemas.isNil:
    for schemaName, schema in schemas.pairs:
      reserved.incl(normIdent(typeNameOf(typeNames, schemaName)))
      reserved.incl(normIdent(schemaNameToEnumName(schemaName)))
  var body: string
  body &= "type\n"
  var first = true
  for schemaName, schema in schemas.pairs:
    let typeDef = genTypeDefinition(schemaName, schema, schemas, typeNames, reserved)
    if typeDef.len > 0:
      if not first:
        body &= "\n"
      body &= typeDef
      first = false

  var stdImports: seq[string]
  if body.contains("Option["):
    stdImports.add("options")
  if body.contains("JsonNode"):
    stdImports.add("json")
  result = "import std/[" & stdImports.join(", ") & "]\n"
  result &= "\n"
  result &= body

proc schemasNeedRenames(schemas: OrderedTableRef[string, Schema]): bool =
  ## True when any schema object property needs a renameHook mapping (i.e. its
  ## wire name differs from the generated Nim field name, e.g. `_tag` -> `tag`).
  if schemas.isNil:
    return false
  for schemaName, schema in schemas.pairs:
    if schema.isNil:
      continue
    let (props, _) = mergedObjectSchema(schema, schemas)
    for propName in props.keys:
      if nimFieldName(propName) != propName:
        return true
  false

proc genRenamesCode(schemas: OrderedTableRef[string, Schema]): string =
  ## Generate the `renames.nim` module: a per-type `renameHook` for every
  ## object schema whose property wire names differ from their Nim fields.
  ## The hook is an involution so it works for both parsing (`_tag` -> `tag`)
  ## and dumping (`tag` -> `_tag`).
  if not schemasNeedRenames(schemas):
    return
  let typeNames = computeTypeNames(schemas)
  result = "import ./types\n\n"
  for schemaName, schema in schemas.pairs:
    if schema.isNil:
      continue
    let (props, _) = mergedObjectSchema(schema, schemas)
    var renames: seq[tuple[wire, nim: string]]
    for propName in props.keys:
      let nimName = nimFieldName(propName)
      if nimName != propName:
        renames.add((propName, nimName))
    if renames.len == 0:
      continue
    let typeName = typeNameOf(typeNames, schemaName)
    result &= "proc renameHook*(v: " & typeName & ", fieldName: var string) {.inline.} =\n"
    var first = true
    for (wire, nim) in renames:
      let cond = if first: "if" else: "elif"
      result &= "  " & cond & " fieldName == \"" & wire & "\":\n"
      result &= "    fieldName = \"" & nim & "\"\n"
      result &= "  elif fieldName == \"" & nim & "\":\n"
      result &= "    fieldName = \"" & wire & "\"\n"
      first = false
    result &= "\n"

proc genEnumType(schemaName: string, schema: Schema): string =
  let enumName = schemaNameToEnumName(schemaName)
  result = &"  {enumName}* = enum\n"
  for val in schema.enumValues:
    let fieldName = enumFieldName(val)
    result &= &"    {fieldName} = \"{val}\"\n"

proc genRequestType(ident: string, httpMeth: string, bodySchema: Schema, schemas: OrderedTableRef[string, Schema];
    typeNames: Table[string, string]): string =
  if bodySchema.isNil or bodySchema.refPath.len > 0:
    return ""
  if bodySchema.fieldType == stObject and not bodySchema.properties.isNil:
    let typeName = httpMeth.toLowerAscii.toUpperAscii[0] & httpMeth.toLowerAscii[1..^1] & ident & "Request"
    result = &"  {typeName} = object\n"
    for propName, propSchema in bodySchema.properties.pairs:
      let nimName = safeIdent(nimFieldName(propName))
      let nimType = nimTypeForSchema(propSchema, schemas, typeNames, qualify = true)
      if isOptionalField(propName, propSchema, bodySchema, schemas):
        result &= &"    {nimName}: Option[{nimType}]\n"
      else:
        result &= &"    {nimName}: {nimType}\n"
    if result.endsWith("\n"):
      result.setLen(result.len - 1)

proc genResponseType(ident: string, httpMeth: string, responseSchema: Schema, schemas: OrderedTableRef[string, Schema];
    typeNames: Table[string, string]): string =
  if responseSchema.isNil or responseSchema.refPath.len > 0:
    return
  if responseSchema.fieldType == stObject and not responseSchema.properties.isNil:
    let typeName = httpMeth.toLowerAscii.toUpperAscii[0] & httpMeth.toLowerAscii[1..^1] & ident & "Response"
    let desc = fmtDocComment("    ", responseSchema.description)
    result = &"  {typeName}* = object\n"
    result &= desc
    for propName, propSchema in responseSchema.properties.pairs:
      let nimName = safeIdent(nimFieldName(propName))
      let nimType = nimTypeForSchema(propSchema, schemas, typeNames, qualify = true)
      result &= &"    {nimName}: {nimType}\n"
      result &= fmtDocComment("      ", propSchema.description)
    if result.endsWith("\n"):
      result.setLen(result.len - 1)

proc genEndpointProc(httpMeth: string; path: string; operation: Operation;
  schemas: OrderedTableRef[string, Schema];
  typeNames: Table[string, string];
  pkgIdent: string; tag: string;
  skipPrefixPath: sink string = ""; stripPrefixModule: sink string = ""): string =
  let ep = genEndpoint(path, skipPrefixPath, stripPrefixModule)
  let httpMethod = httpMeth.toLowerAscii
  let procName = httpMethod & ep.ident
  let errType = &"{pkgIdent}ClientError"
  let methUpper = httpMeth.toUpperAscii

  var pathParams: seq[Parameter]
  var queryParams: seq[Parameter]
  var hasBody = false
  var bodyRefName: string
  var bodyNeedsRequestType = false
  var successCode = ""
  var successSchema: Schema

  for param in operation.parameters:
    if param.isNil: continue
    case param.kind
    of pinPath: pathParams.add(param)
    of pinQuery: queryParams.add(param)
    else: discard

  if not operation.requestBody.isNil and not operation.requestBody.content.isNil:
    for mediaType, mt in operation.requestBody.content.pairs:
      if mediaType == "application/json" and not mt.schema.isNil:
        let bodySchema = mt.schema
        hasBody = true
        if bodySchema.refPath.len > 0:
          let refParts = bodySchema.refPath.split("/")
          bodyRefName = "types." & typeNameOf(typeNames, refParts[refParts.high])
        elif bodySchema.fieldType == stObject and not bodySchema.properties.isNil:
          bodyNeedsRequestType = true

  for statusCode, response in operation.responses.pairs:
    if statusCode.startsWith("2") and not response.content.isNil:
      for mediaType, mt in response.content.pairs:
        if mediaType == "application/json" and not mt.schema.isNil:
          successCode = statusCode
          successSchema = mt.schema
          break
    if successCode.len > 0: break

  let respTypeName =
    if successSchema.isNil:
      "AsyncResponse"
    elif successSchema.refPath.len > 0:
      let parts = successSchema.refPath.split("/")
      "types." & typeNameOf(typeNames, parts[parts.high])
    elif successSchema.fieldType == stObject and not successSchema.properties.isNil:
      httpMeth.toLowerAscii.toUpperAscii[0] & httpMeth.toLowerAscii[1..^1] & ep.ident & "Response"
    else:
      nimTypeForSchema(successSchema, schemas, typeNames, qualify = true)

  result = "\n"

  var paramStrs: seq[string]
  paramStrs.add("client: " & pkgIdent & "Client")
  for param in operation.parameters:
    if param.isNil: continue
    let paramName = paramIdent(param.name)
    let nimType = nimTypeForSchema(param.schema, schemas, typeNames, qualify = true)
    case param.kind
    of pinPath:
      paramStrs.add(paramName & ": " & nimType)
    of pinQuery:
      let defaultVal = paramDefaultValue(param)
      if defaultVal.len > 0:
        paramStrs.add(paramName & ": " & nimType & " = " & defaultVal)
      elif paramHasEnum(param):
        paramStrs.add(paramName & ": " & enumParamNimType(param, tag) & " = {}")
      elif paramIsSimpleArray(param):
        paramStrs.add(paramName & ": seq[string] = @[]")
      elif param.required:
        paramStrs.add(paramName & ": " & nimType)
      else:
        paramStrs.add(paramName & ": " & nimType & " = default(" & nimType & ")")
    else: discard

  if hasBody:
    if bodyRefName.len > 0:
      paramStrs.add("body: " & bodyRefName)
    elif bodyNeedsRequestType:
      paramStrs.add("body: " & httpMeth.toLowerAscii.toUpperAscii[0] & httpMeth.toLowerAscii[1..^1] & ep.ident & "Request")

  let procPrefix = "proc " & procName & "*("
  let suffix = ": Future[" & respTypeName & "] {.async.} =\n"
  const maxLine = 80
  let align = procPrefix.len
  result &= procPrefix
  var lineLen = procPrefix.len
  for i, p in paramStrs:
    let comma = if i > 0: ", " else: ""
    let totalLen = comma.len + p.len
    if lineLen + totalLen > maxLine and i > 0:
      result &= ",\n" & spaces(align)
      lineLen = align
    elif i > 0:
      result &= ", "
      lineLen += 2
    result &= p
    lineLen += p.len
  result &= ")" & suffix

  let docDesc =
    if operation.description.len > 0:
      fmtDocComment("  ", operation.description.strip)
    elif operation.summary.len > 0:
      fmtDocComment("  ", operation.summary)
    else: ""
  if docDesc.len > 0:
    result &= docDesc & "\n"

  if queryParams.len > 0:
    result &= "  var q = initOrderedTable[string, string]()\n"
    for param in queryParams:
      let paramName = paramIdent(param.name)
      if paramHasEnum(param) or paramIsSimpleArray(param):
        result &= &"  for v in {paramName}: q[\"{param.name}\"] = $v\n"
      else:
        result &= &"  q[\"{param.name}\"] = ${paramName}\n"

  if pathParams.len > 0:
    var fmtPath = ep.endpoint
    for param in pathParams:
      let paramName = paramIdent(param.name)
      fmtPath = fmtPath.replace(&"{{{param.name}}}", &"{{{paramName}}}")
    if queryParams.len > 0:
      result &= &"  let res = await client.http{methUpper}(fmt\"{fmtPath}\", q)\n"
    elif hasBody:
      result &= &"  let res = await client.http{methUpper}(fmt\"{fmtPath}\", body)\n"
    else:
      result &= &"  let res = await client.http{methUpper}(fmt\"{fmtPath}\")\n"
  else:
    if queryParams.len > 0:
      result &= &"  let res = await client.http{methUpper}(\"{ep.endpoint}\", q)\n"
    elif hasBody:
      result &= &"  let res = await client.http{methUpper}(\"{ep.endpoint}\", body)\n"
    else:
      result &= &"  let res = await client.http{methUpper}(\"{ep.endpoint}\")\n"

  if respTypeName == "AsyncResponse":
    result &= "  return res\n"
  else:
    result &= "  let body = await res.body\n"
    result &= &"  case res.code\n"
    result &= &"  of Http{successCode}:\n"
    result &= &"    result = fromJson(body, {respTypeName})\n"
    result &= "  else:\n"
    result &= &"    raise newException({errType}, body)\n"

proc successResponseSchema(operation: Operation): Schema =
  ## The first 2xx `application/json` response schema, mirroring the client proc.
  if operation.isNil or operation.responses.isNil:
    return
  for statusCode, response in operation.responses.pairs:
    if statusCode.startsWith("2") and not response.content.isNil:
      for mediaType, mt in response.content.pairs:
        if mediaType == "application/json" and not mt.schema.isNil:
          return mt.schema
      break

proc genEndpointFile*(tag: string, ops: seq[tuple[path: string, meth: string, operation: Operation]],
  schemas: OrderedTableRef[string, Schema];
  typeNames: Table[string, string];
  pkgIdent: string;
  skipPrefixPath: sink string = ""; stripPrefixModule: sink string = ""): string =
  var body: string

  var hasTypes = false
  var firstType = true
  for (path, meth, operation) in ops:
    let ep = genEndpoint(path, skipPrefixPath, stripPrefixModule)
    var bodySchema: Schema
    if not operation.requestBody.isNil and not operation.requestBody.content.isNil:
      for mediaType, mt in operation.requestBody.content.pairs:
        if mediaType == "application/json" and not mt.schema.isNil:
          bodySchema = mt.schema
          break
    if not bodySchema.isNil and bodySchema.refPath.len == 0 and bodySchema.fieldType == stObject and not bodySchema.properties.isNil:
      let reqType = genRequestType(ep.ident, meth, bodySchema, schemas, typeNames)
      if reqType.len > 0:
        if not hasTypes:
          body &= "type\n"
          hasTypes = true
        if not firstType:
          body &= "\n"
        body &= reqType
        firstType = false
    let successSchema = successResponseSchema(operation)
    if not successSchema.isNil and successSchema.refPath.len == 0 and
        successSchema.fieldType == stObject and not successSchema.properties.isNil:
      let respType = genResponseType(ep.ident, meth, successSchema, schemas, typeNames)
      if respType.len > 0:
        if not hasTypes:
          body &= "type\n"
          hasTypes = true
        if not firstType:
          body &= "\n"
        body &= respType
        firstType = false

  var emittedEnums: seq[string]
  for (path, meth, operation) in ops:
    for param in operation.parameters:
      if param != nil and param.kind == pinQuery and paramHasEnum(param):
        let enumName = pascalSingular(tag) & toPascalCase(param.name) & "Option"
        if enumName notin emittedEnums:
          emittedEnums.add(enumName)
          let enumDef = genEnumForQueryParam(param, tag)
          if enumDef.len > 0:
            if not hasTypes:
              body &= "type\n"
              hasTypes = true
            if not firstType:
              body &= "\n"
            body &= enumDef
            firstType = false

  if hasTypes:
    body &= "\n"

  for (path, meth, operation) in ops:
    body &= genEndpointProc(meth, path, operation, schemas, typeNames, pkgIdent, tag, skipPrefixPath, stripPrefixModule)

  var stdImports: seq[string]
  if body.contains("fmt\""):
    stdImports.add("strformat")
  if body.contains("Option["):
    stdImports.add("options")
  if body.contains("JsonNode"):
    stdImports.add("json")

  result = stubHeader
  if stdImports.len > 0:
    result &= "import std/[" & stdImports.join(", ") & "]\n"
  result &= "import ./private/metaclient\n"
  if body.contains("types."):
    result &= "import ./private/types\n"
  result &= "\n"
  result &= body

proc serverIdent(description, url: string): string =
  let src =
    if description.len > 0: description
    else: url
  result = ""
  var nextUpper = true
  for c in src:
    if c == ' ' or c == '-' or c == '_' or c == '/' or c == '.' or c == ':':
      nextUpper = true
    elif c.isAlphaAscii or c.isDigit:
      if nextUpper:
        result.add(c.toUpperAscii)
        nextUpper = false
      else:
        result.add(c)

proc genServers*(servers: seq[Server]): string =
  result = "const\n"
  var used = initHashSet[string]()
  for i, srv in servers:
    let base = "server" & serverIdent(srv.description, srv.url)
    var name = base
    var n = 2
    while name in used:
      name = base & $n
      inc n
    used.incl(name)
    result &= &"  {name}* = \"{srv.url}\"\n"

proc stripModulePrefix(name: string; prefix: string): string =
  ## Remove a leading module prefix (e.g. `x_amz_target_awslicensemanager`)
  ## from a tag/module name, collapsing the separator that follows it.
  if prefix.len == 0 or not name.startsWith(prefix):
    return name
  result = name[prefix.len .. ^1]
  while result.len > 0 and result[0] == '_':
    result = result[1 .. ^1]

proc groupOperations*(pkg: Package;
    stripPrefixModule = ""): OrderedTableRef[string, seq[tuple[path: string, meth: string, operation: Operation]]] =
  new(result)
  if pkg.oapi.isNil or pkg.oapi.paths.isNil:
    return
  for curPath, pathItem in pkg.oapi.paths.pairs:
    if pathItem.isNil: continue
    let items: array[8, tuple[op: Operation, meth: string]] = [
      (pathItem.get, "GET"), (pathItem.post, "POST"), (pathItem.put, "PUT"),
      (pathItem.delete, "DELETE"), (pathItem.patch, "PATCH"),
      (pathItem.options, "OPTIONS"), (pathItem.head, "HEAD"), (pathItem.trace, "TRACE")
    ]
    for (op, httpMeth) in items:
      if op == nil: continue
      let tag =
        if op.tags.len > 0:
          let firstTag = op.tags[0]
          if firstTag.len > 0: toModuleName(firstTag)
          else: toModuleName(genEndpoint(curPath, stripPrefixModule = stripPrefixModule).module)
        else:
          toModuleName(genEndpoint(curPath, stripPrefixModule = stripPrefixModule).module)
      let cleanTag = stripModulePrefix(tag, stripPrefixModule)
      if cleanTag.len == 0:
        continue
      if not result.hasKey(cleanTag):
        result[cleanTag] = newSeq[tuple[path: string, meth: string, operation: Operation]]()
      result[cleanTag].add((curPath, httpMeth, op))

proc detectOAuthUrl(scheme: SecurityScheme, kind: string): string =
  if scheme.isNil or scheme.flows.isNil or scheme.flows.kind != JObject:
    return
  for flowName in ["authorizationCode", "implicit", "password", "clientCredentials"]:
    if scheme.flows.hasKey(flowName) and scheme.flows[flowName].kind == JObject:
      let flow = scheme.flows[flowName]
      if flow.hasKey(kind) and flow[kind].kind == JString:
        return flow[kind].getStr

proc newGenerator*(pkg: Package, outputDir: string, skipPrefixPath = "";
    spec: openjson.JsonNode = nil; stripPrefixModule = ""): Generator =
  new(result)
  result.pkg = pkg
  result.outputDir = outputDir
  result.pkgName = if pkg.id.len > 0: pkg.id else: "client"
  result.pkgIdent = toPascalCase(result.pkgName)
  result.authType = "bearer"
  result.skipPrefixPath = skipPrefixPath
  result.stripPrefixModule = stripPrefixModule
  result.spec = spec
  if pkg.oapi != nil:
    if pkg.oapi.servers.len > 0:
      result.baseUri = pkg.oapi.servers[0].url
    if pkg.oapi.components.schemas != nil:
      result.schemas = pkg.oapi.components.schemas
    if pkg.oapi.components.securitySchemes != nil:
      for name, scheme in pkg.oapi.components.securitySchemes.pairs:
        if scheme != nil and scheme.schemeType == sstOAuth2:
          result.authType = "oauth2"
          result.oauthTokenUrl = detectOAuthUrl(scheme, "tokenUrl")
          result.oauthAuthUrl = detectOAuthUrl(scheme, "authorizationUrl")
          break

proc fillTemplate(tmpl: string, vars: Table[string, string]): string =
  result = tmpl
  for key, val in vars:
    result = result.replace(&"{{{key}}}", val)

proc ensureDir(path: string) =
  if not dirExists(path):
    createDir(path)

proc genSpecConst(spec: openjson.JsonNode): string =
  ## Embed the raw spec as a compact, escaped Nim string literal.
  result = openjson.toJson(spec)
  result = openjson.toJson(result)

proc sampleFieldValue(propName: string; propSchema: Schema;
    schemas: OrderedTableRef[string, Schema];
    typeNames: Table[string, string]): string =
  ## A Nim expression with a sample value for a required object field,
  ## or "" when the field should be left at its default.
  if propSchema.isNil:
    return
  var target = propSchema
  if propSchema.refPath.len > 0:
    let parts = propSchema.refPath.split("/")
    let name = parts[^1]
    if schemas != nil and schemas.hasKey(name):
      target = schemas[name]
    else:
      return
    if target.isNil:
      return
  case target.fieldType
  of stString:
    if target.enumValues.len > 0: return
    return "\"sample\""
  of stInteger:
    return "1"
  of stNumber:
    return "1.0"
  of stBoolean:
    return "true"
  of stArray:
    return "@[]"
  of stObject:
    if propSchema.refPath.len > 0:
      let parts = propSchema.refPath.split("/")
      return &"new{typeNameOf(typeNames, parts[^1])}()"
    if target.name.len == 0:
      return "openjson.newJObject()"
    return
  else:
    return

proc genDataBuilder(schemaName: string; schema: Schema;
    schemas: OrderedTableRef[string, Schema];
    typeNames: Table[string, string]; qualifier: string): string =
  ## A `new<Type>()` fixture builder for a component object schema, shared
  ## by every module test to avoid duplicating sample data. Type references
  ## are module-qualified (`pkg.Type`) to avoid collisions with stdlib names.
  let typeName = typeNameOf(typeNames, schemaName)
  let qType = qualifier & typeName
  result = &"proc new{typeName}*(): {qType} =\n"
  result &= &"  result = {qType}()\n"
  let (props, required) = mergedObjectSchema(schema, schemas)
  for propName, propSchema in props.pairs:
    if propName in required and
        not isOptionalField(propName, propSchema, required, schemas):
      let sample = sampleFieldValue(propName, propSchema, schemas, typeNames)
      if sample.len > 0:
        let fname = safeIdent(nimFieldName(propName))
        result &= &"  result.{fname} = {sample}\n"
  result &= "\n"

proc genCommonFile(gen: Generator): string =
  ## Generate `tests/common.nim`: embedded spec, mock-server bootstrap, and
  ## shared data builders for every component object schema.
  let typeNames = computeTypeNames(gen.schemas)
  let qualifier = gen.pkgName & "."
  result = fillTemplate(stubHeader, {
    "nimbase_pkg_name": gen.pkgName,
    "nimbase_pkg_license": gen.pkg.license,
  }.toTable)
  result &= "import std/net\n"
  result &= "from std/asyncdispatch import waitFor, asyncCheck\n"
  result &= "import pkg/openparser/json as openjson\n"
  result &= &"import {gen.pkgName}\n"
  result &= "import ./mockserver except File\n\n"
  result &= "const specJson* = " & genSpecConst(gen.spec) & "\n\n"
  result &= "proc spec*(): openjson.JsonNode =\n"
  result &= "  openjson.fromJson(specJson)\n\n"
  result &= "var mockServers*: seq[MockServer]\n\n"
  result &= "proc startMock*(): Port =\n"
  result &= "  ## Start a mock server backed by the embedded spec on an ephemeral port.\n"
  result &= "  let s = newMockServer(spec(), \"127.0.0.1\", Port(0))\n"
  result &= "  waitFor s.open()\n"
  result &= "  asyncCheck s.serve()\n"
  result &= "  mockServers.add(s)\n"
  result &= "  result = s.port\n\n"
  if not gen.schemas.isNil:
    var builderNames: seq[string]
    for schemaName, schema in gen.schemas.pairs:
      if schema != nil and schema.refPath.len == 0 and schema.fieldType == stObject:
        builderNames.add(typeNameOf(typeNames, schemaName))
    for name in builderNames:
      result &= &"proc new{name}*(): {qualifier}{name}\n"
    if builderNames.len > 0:
      result &= "\n"
    for schemaName, schema in gen.schemas.pairs:
      if schema != nil and schema.refPath.len == 0 and schema.fieldType == stObject:
        result &= genDataBuilder(schemaName, schema, gen.schemas, typeNames, qualifier)

proc collectSchemaRefs(schema: Schema; refs: var HashSet[string]) =
  if schema.isNil: return
  if schema.refPath.len > 0:
    let parts = schema.refPath.split("/")
    if parts.len > 0:
      refs.incl(parts[^1])
    return
  case schema.fieldType
  of stObject:
    if not schema.properties.isNil:
      for p in schema.properties.values:
        collectSchemaRefs(p, refs)
    for sub in schema.allOf:
      collectSchemaRefs(sub, refs)
  of stArray:
    collectSchemaRefs(schema.items, refs)
  else: discard

proc opRefs(op: Operation): HashSet[string] =
  result = initHashSet[string]()
  if op.isNil: return
  for p in op.parameters:
    if p != nil:
      collectSchemaRefs(p.schema, result)
  if op.requestBody != nil and not op.requestBody.content.isNil:
    for mt in op.requestBody.content.values:
      collectSchemaRefs(mt.schema, result)
  if not op.responses.isNil:
    for resp in op.responses.values:
      if resp != nil and not resp.content.isNil:
        for mt in resp.content.values:
          collectSchemaRefs(mt.schema, result)

proc resolveParamTarget(param: Parameter;
    schemas: OrderedTableRef[string, Schema]): Schema =
  if param.isNil or param.schema.isNil:
    return
  if param.schema.refPath.len > 0:
    let parts = param.schema.refPath.split("/")
    let name = parts[^1]
    if schemas != nil and schemas.hasKey(name):
      return schemas[name]
    return nil
  return param.schema

proc sampleParamArg(param: Parameter; tag: string;
    schemas: OrderedTableRef[string, Schema];
    typeNames: Table[string, string]): string =
  ## A sample call argument for a path/query parameter, or "" if unsampleable.
  ## Arguments must line up positionally with the generated proc signature.
  if param.kind == pinQuery and paramHasEnum(param):
    return "{}"
  let target = resolveParamTarget(param, schemas)
  if target.isNil:
    return
  case target.fieldType
  of stString:
    if target.enumValues.len > 0: return
    return "\"test\""
  of stInteger:
    return "1"
  of stNumber:
    return "1.0"
  of stBoolean:
    return "true"
  of stArray:
    if paramIsSimpleArray(param): return "@[\"test\"]"
    return
  of stObject:
    if param.schema.refPath.len > 0:
      let parts = param.schema.refPath.split("/")
      let name = typeNameOf(typeNames, parts[^1])
      return &"new{name}()"
    if param.schema.name.len == 0:
      return "openjson.newJObject()"
    return
  else:
    return

proc genModuleTest(tag: string; ops: seq[tuple[path: string, meth: string, operation: Operation]];
    gen: Generator; typeNames: Table[string, string]): string =
  ## Generate `tests/test_<tag>.nim`: serialization round-trips for the types
  ## the module touches plus mock-server integration tests for its endpoints.
  let pkgName = gen.pkgName
  let clientIdent = gen.pkgIdent & "Client"

  var body: string
  let qualifier = pkgName & "."

  body &= &"suite \"{tag} serialization\":\n"
  var hasSerTest = false
  var refs = initHashSet[string]()
  for (_, _, operation) in ops:
    for r in opRefs(operation):
      refs.incl(r)
  for r in refs:
    if gen.schemas != nil and gen.schemas.hasKey(r) and gen.schemas[r] != nil and
        gen.schemas[r].refPath.len == 0 and gen.schemas[r].fieldType == stObject:
      let typeName = typeNameOf(typeNames, r)
      body &= &"  test \"round-trips {typeName}\":\n"
      body &= &"    let obj = new{typeName}()\n"
      body &= &"    check openjson.toJson(openjson.fromJson(openjson.toJson(obj), {qualifier}{typeName})) == openjson.toJson(obj)\n"
      body &= "\n"
      hasSerTest = true

  var emittedResp = initHashSet[string]()
  for (path, meth, operation) in ops:
    let ep = genEndpoint(path, gen.skipPrefixPath, gen.stripPrefixModule)
    let successSchema = successResponseSchema(operation)
    if not successSchema.isNil and successSchema.refPath.len == 0 and
        successSchema.fieldType == stObject and not successSchema.properties.isNil:
      let typeName = meth.toLowerAscii.toUpperAscii[0] & meth.toLowerAscii[1..^1] & ep.ident & "Response"
      if typeName notin emittedResp:
        emittedResp.incl(typeName)
        body &= &"  test \"round-trips {typeName}\":\n"
        body &= &"    let obj = {qualifier}{typeName}()\n"
        body &= &"    check openjson.toJson(openjson.fromJson(openjson.toJson(obj), {qualifier}{typeName})) == openjson.toJson(obj)\n"
        body &= "\n"
        hasSerTest = true

  if not hasSerTest:
    body &= "  test \"module imports cleanly\":\n"
    body &= "    check true\n\n"

  body &= &"suite \"{tag} endpoints\":\n"
  var emitted = 0
  for (path, meth, operation) in ops:
    let ep = genEndpoint(path, gen.skipPrefixPath, gen.stripPrefixModule)
    let procName = meth.toLowerAscii & ep.ident
    var args: seq[string]
    var skip = false
    for param in operation.parameters:
      if param.isNil: continue
      case param.kind
      of pinPath, pinQuery:
        let sample = sampleParamArg(param, tag, gen.schemas, typeNames)
        if sample.len == 0:
          skip = true
          break
        args.add(sample)
      else: discard
    if skip: continue
    var bodyArg = ""
    if not operation.requestBody.isNil and not operation.requestBody.content.isNil:
      for mediaType, mt in operation.requestBody.content.pairs:
        if mediaType == "application/json" and not mt.schema.isNil:
          if mt.schema.refPath.len > 0:
            let parts = mt.schema.refPath.split("/")
            let target =
              if gen.schemas != nil and gen.schemas.hasKey(parts[^1]): gen.schemas[parts[^1]]
              else: nil
            if target != nil and target.fieldType == stObject:
              bodyArg = &"new{typeNameOf(typeNames, parts[^1])}()"
            else:
              skip = true
          elif mt.schema.fieldType == stObject and not mt.schema.properties.isNil:
            skip = true  # inline private request type
          break
    if skip: continue
    if bodyArg.len > 0:
      args.add(bodyArg)
    let callArgs = args.join(", ")
    let initArg = if gen.authType == "oauth2": "()" else: "(\"test-key\")"
    body &= &"  test \"{meth} {path}\":\n"
    body &= &"    let client = init{clientIdent}{initArg}\n"
    body &= "    client.baseUri = \"http://127.0.0.1:\" & $int(startMock())\n"
    body &= &"    discard waitFor client.{procName}({callArgs})\n"
    body &= "\n"
    inc emitted

  if emitted == 0:
    body &= "  test \"module has no sampleable endpoints\":\n"
    body &= "    check true\n\n"

  result = fillTemplate(stubHeader, {
    "nimbase_pkg_name": gen.pkgName,
    "nimbase_pkg_license": gen.pkg.license,
  }.toTable)
  var stdImports: seq[string]
  if body.contains("Option["):
    stdImports.add("options")
  if body.contains("JsonNode"):
    stdImports.add("json")
  result &= "import std/[asyncdispatch"
  for imp in stdImports:
    result &= ", " & imp
  result &= "]\n"
  result &= "import unittest\n"
  result &= "import pkg/openparser/json as openjson\n"
  result &= &"import {pkgName}\n"
  result &= "import ./common\n\n"
  result &= body


proc countEndpoints(gen: Generator): int =
  if gen.pkg.oapi.isNil or gen.pkg.oapi.paths.isNil:
    return
  for _, pi in gen.pkg.oapi.paths.pairs:
    if pi.isNil: continue
    if not pi.get.isNil: inc result
    if not pi.post.isNil: inc result
    if not pi.put.isNil: inc result
    if not pi.delete.isNil: inc result
    if not pi.patch.isNil: inc result
    if not pi.options.isNil: inc result
    if not pi.head.isNil: inc result
    if not pi.trace.isNil: inc result

proc genRepoFeatures(gen: Generator; modules: int): string =
  let title =
    if not gen.pkg.oapi.isNil and gen.pkg.oapi.info.title.len > 0:
      gen.pkg.oapi.info.title
    else:
      gen.pkgIdent
  result = "- Typed client for " & title & " (" & $countEndpoints(gen) & " endpoints)\n"
  if gen.authType == "oauth2":
    result &= "- OAuth2 authentication with token refresh\n"
  else:
    result &= "- Bearer-token authentication\n"
  if gen.generateTests and not gen.spec.isNil:
    result &= "- Mock-server backed test suite\n"
  result &= "- Async-first, generated with Nimbase\n"

proc sampleableCall(gen: Generator;
    groups: OrderedTableRef[string, seq[tuple[path: string, meth: string, operation: Operation]]];
    typeNames: Table[string, string]): tuple[procName, args: string] =
  ## The first endpoint across the package that can be called with plain sample
  ## arguments (mirroring the generated tests), skipping endpoints that need
  ## fixture builders (`new<Type>()`) — those only exist in the test harness.
  ## Returns "" when none exist.
  for tag, ops in groups.pairs:
    for (path, meth, operation) in ops:
      let ep = genEndpoint(path, gen.skipPrefixPath, gen.stripPrefixModule)
      let procName = meth.toLowerAscii & ep.ident
      var args: seq[string]
      var skip = false
      for param in operation.parameters:
        if param.isNil: continue
        case param.kind
        of pinPath, pinQuery:
          let sample = sampleParamArg(param, tag, gen.schemas, typeNames)
          if sample.len == 0 or sample.startsWith("new"):
            skip = true
            break
          args.add(sample)
        else: discard
      if skip: continue
      var bodyArg = ""
      if not operation.requestBody.isNil and not operation.requestBody.content.isNil:
        for mediaType, mt in operation.requestBody.content.pairs:
          if mediaType == "application/json" and not mt.schema.isNil:
            if mt.schema.refPath.len > 0:
              let parts = mt.schema.refPath.split("/")
              let target =
                if gen.schemas != nil and gen.schemas.hasKey(parts[^1]): gen.schemas[parts[^1]]
                else: nil
              if target != nil and target.fieldType == stObject:
                skip = true  # body needs a fixture builder
              else:
                skip = true
            elif mt.schema.fieldType == stObject and not mt.schema.properties.isNil:
              skip = true  # inline private request type
            break
      if skip: continue
      if bodyArg.len > 0:
        args.add(bodyArg)
      return (procName, args.join(", "))

proc genExampleBody(gen: Generator;
    groups: OrderedTableRef[string, seq[tuple[path: string, meth: string, operation: Operation]]];
    typeNames: Table[string, string]): string =
  let initArg =
    if gen.authType == "oauth2": "()"
    else: "(\"your-api-key\")"
  let baseUri = gen.baseUri
  let call = sampleableCall(gen, groups, typeNames)
  if call.procName.len > 0:
    result = "  let client = init" & gen.pkgIdent & "Client" & initArg & "\n"
    if baseUri.len > 0:
      result &= "  client.baseUri = \"" & baseUri & "\"\n"
    result &= "  try:\n"
    result &= "    let res = await client." & call.procName & "(" & call.args & ")\n"
    result &= "    echo res\n"
    result &= "  except CatchableError as e:\n"
    result &= "    echo \"request failed: \", e.msg\n"
  else:
    result = "  let client = init" & gen.pkgIdent & "Client" & initArg & "\n"
    if baseUri.len > 0:
      result &= "  client.baseUri = \"" & baseUri & "\"\n"
    result &= "  echo \"client ready — see the docs for the available endpoints\"\n"

proc genNimbaseCommand(gen: Generator): string =
  ## The full `gen-command` block embedded in `.github/workflows/nimbase.yml`.
  ## When `generator` is set it is used verbatim; otherwise a default flow
  ## generates into a temp dir and copies only `src`/`tests` over the repo root.
  ## Lines are indented to match the YAML block scalar (`gen-command: |`).
  let indent = "            "
  if gen.generator.len > 0:
    result = gen.generator
  elif gen.source.len == 0:
    result = "# TODO: set `source` in nimbase.oapi.config.yaml to enable regeneration"
  else:
    let outArg = "$tmp/" & gen.pkgName
    let genCmd =
      if gen.source.contains("://"):
        "nimbase oapi.gen \"" & gen.source & "\" \"" & outArg & "\""
      else:
        "nimbase oapi.gurugen \"" & gen.source & "\" \"" & outArg & "\""
    result = "tmp=\"$(mktemp -d)\"\n" &
      indent & genCmd & "\n" &
      indent & "cp -R \"$tmp/" & gen.pkgName & "/src\" .\n" &
      indent & "cp -R \"$tmp/" & gen.pkgName & "/tests\" .\n" &
      indent & "rm -rf \"$tmp\""

proc generate*(gen: Generator) =
  let srcDir = gen.outputDir / "src"
  let srcPkgDir = srcDir / gen.pkgName
  let privateDir = srcPkgDir / "private"
  ensureDir(srcPkgDir)
  ensureDir(privateDir)

  let serverUrl =
    if gen.baseUri.len > 0:
      if gen.baseUri[^1] != '/': gen.baseUri & "/"
      else: gen.baseUri
    else: ""

  let oauth2Require =
    if gen.authType == "oauth2": "\nrequires \"oauth2\""
    else: ""

  let renamesCode = genRenamesCode(gen.schemas)
  let renamesImport =
    if renamesCode.len > 0: "import ./renames\n"
    else: ""
  let renamesExport =
    if renamesCode.len > 0: "export renames\n"
    else: ""

  var hasServers = false
  if not gen.pkg.oapi.isNil and gen.pkg.oapi.servers.len > 1:
    let serversCode = genServers(gen.pkg.oapi.servers)
    writeFile(privateDir / "server_urls.nim", serversCode)
    hasServers = true

  let groups = groupOperations(gen.pkg, gen.stripPrefixModule)
  let typeNames = computeTypeNames(gen.schemas)
  let repoName =
    if gen.repo.len > 0: gen.repo
    else: gen.pkgName
  let pkgTitle =
    if not gen.pkg.oapi.isNil and gen.pkg.oapi.info.title.len > 0:
      gen.pkg.oapi.info.title
    else:
      gen.pkgIdent
  let features = genRepoFeatures(gen, if groups.isNil: 0 else: groups.len)
  let exampleBody = genExampleBody(gen, groups, typeNames)
  let readmeExample =
    "```nim\n" &
    "import " & gen.pkgName & "\n" &
    "import std/asyncdispatch\n\n" &
    "proc main() {.async.} =\n" &
    exampleBody &
    "\nwhen isMainModule:\n" &
    "  waitFor main()\n" &
    "```\n"
  let regenSource =
    if gen.source.len > 0: gen.source
    else: "the upstream OpenAPI 3.x specification"

  let vars = {
    "nimbase_pkg_name": gen.pkgName,
    "nimbase_pkg_title": pkgTitle,
    "nimbase_client_ident": gen.pkgIdent & "Client",
    "nimbase_client_ident_error": gen.pkgIdent & "ClientError",
    "nimbase_pkg_license": gen.pkg.license,
    "nimbase_pkg_desc": gen.pkg.description,
    "nimbase_pkg_url": (if gen.pkg.url.len > 0: gen.pkg.url & "\n" else: ""),
    "nimbase_pkg_license_url": (if gen.pkg.licenseUrl.len > 0: " - " & gen.pkg.licenseUrl else: ""),
    "nimbase_base_uri": serverUrl,
    "nimbase_oauth_token_url": gen.oauthTokenUrl,
    "nimbase_oauth_auth_url": gen.oauthAuthUrl,
    "nimbase_requires_oauth2": oauth2Require,
    "nimbase_openparser_version": nimbaseOpenparserVersion,
    "nimbase_renames_import": renamesImport,
    "nimbase_renames_export": renamesExport,
    "nimbase_repo_name": repoName,
    "nimbase_repo_features": features,
    "nimbase_repo_examples": readmeExample,
    "nimbase_example_body": exampleBody,
    "nimbase_gen_command": genNimbaseCommand(gen),
    "nimbase_regen_source": regenSource,
    "pkgVersion": gen.pkg.pkgVersion,
    "pkgAuthor": gen.pkg.author,
    "pkgDesc": gen.pkg.description,
    "pkgLicense": gen.pkg.license,
  }.toTable

  let metaclientStub =
    if gen.authType == "oauth2": stubMetaclientOAuth2
    else: stubMetaclient
  writeFile(privateDir / "metaclient.nim", fillTemplate(metaclientStub, vars))

  if not gen.schemas.isNil and gen.schemas.len > 0:
    let typesCode = genTypes(gen.schemas)
    writeFile(privateDir / "types.nim", typesCode)

  if renamesCode.len > 0:
    writeFile(privateDir / "renames.nim", renamesCode)

  # starter scaffolding: workflows, gitignore, license, README, examples
  let ghDir = gen.outputDir / ".github/workflows"
  ensureDir(ghDir)
  writeFile(ghDir / "docs.yml", fillTemplate(stubWorkflowDocs, vars))
  writeFile(ghDir / "test.yml", fillTemplate(stubWorkflowTest, vars))
  writeFile(ghDir / "nimbase.yml", fillTemplate(stubWorkflowNimbase, vars))
  if gen.generateExamples:
    writeFile(ghDir / "runnable_examples.yml", fillTemplate(stubWorkflowRunnableExamples, vars))
  writeFile(gen.outputDir / ".gitignore", stubStarterGitignore)
  writeFile(gen.outputDir / "LICENSE", stubStarterLicense)
  writeFile(gen.outputDir / "README.md", fillTemplate(stubStarterReadme, vars))
  let examplesDir = gen.outputDir / "examples"
  ensureDir(examplesDir)
  writeFile(examplesDir / "config.nims", "switch(\"path\", \"$projectDir/../src\")\nswitch(\"define\", \"ssl\")\n")
  writeFile(examplesDir / "basic.nim", fillTemplate(stubExampleBasic, vars))

  if not groups.isNil:
    for tag, ops in groups.pairs:
      let fileName = tag & ".nim"
      let endpointCode = fillTemplate(genEndpointFile(tag, ops, gen.schemas, typeNames, gen.pkgIdent, gen.skipPrefixPath, gen.stripPrefixModule), vars)
      writeFile(srcPkgDir / fileName, endpointCode)

    if gen.generateTests and not gen.spec.isNil:
      let testsDir = gen.outputDir / "tests"
      ensureDir(testsDir)
      writeFile(testsDir / "config.nims", "switch(\"path\", \"$projectDir/../src\")\n")
      writeFile(testsDir / "mockserver.nim", stubMockserver)
      writeFile(testsDir / "common.nim", genCommonFile(gen))
      for tag, ops in groups.pairs:
        let testCode = genModuleTest(tag, ops, gen, typeNames)
        writeFile(testsDir / &"test_{tag}.nim", testCode)

  var modules: seq[string]
  var mainExports: seq[string]
  for tag, _ in groups.pairs:
    modules.add(tag)
    mainExports.add(tag)
  var privateModules: seq[string]
  if not gen.schemas.isNil and gen.schemas.len > 0:
    privateModules.add("types")
  if renamesCode.len > 0:
    privateModules.add("renames")
  privateModules.add("metaclient")
  if hasServers:
    privateModules.add("server_urls")

  let importPrefix = "import ./" & gen.pkgName & "/["
  let importIndent = " ".repeat(importPrefix.len)

  let importLine =
    if modules.len <= 5:
      importPrefix & modules.join(", ") & "]\n"
    else:
      var lines: seq[string]
      var i = 0
      while i < modules.len:
        let chunk = modules[i..min(i + 4, modules.high)]
        if i == 0:
          lines.add(importPrefix & chunk.join(", ") & ",")
        else:
          lines.add(importIndent & chunk.join(", ") & ",")
        i += 5
      lines[^1] = lines[^1][0..^2] & "]"
      lines.join("\n") & "\n"

  mainExports.add(privateModules)
  let privateImportLine =
    "import ./" & gen.pkgName & "/private/[" & privateModules.join(", ") & "]\n"

  let exportLine =
    if mainExports.len <= 5:
      "export " & mainExports.join(", ") & "\n"
    else:
      var lines: seq[string]
      var i = 0
      while i < mainExports.len:
        let chunk = mainExports[i..min(i + 4, mainExports.high)]
        if i == 0:
          lines.add("export " & chunk.join(", ") & ",")
        else:
          lines.add("       " & chunk.join(", ") & ",")
        i += 5
      lines[^1] = lines[^1][0..^2]
      lines.join("\n") & "\n"

  let mainCode = fillTemplate(stubHeader, vars) & importLine & privateImportLine & "\n" & exportLine
  writeFile(srcDir / &"{gen.pkgName}.nim", mainCode)

  writeFile(gen.outputDir / &"{gen.pkgName}.nimble", fillTemplate(stubNimble, vars))

  echo "Generated client package at: ", gen.outputDir
