# Nimbase - Code generator. OAPI 3.x clients, wrappers from C/C++, FFI bindings & native extensions
#
# (c) 2026 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/nimbase/nimbase

import std/[tables, json]
import ../ir
import ./schemas, ./parameters, ./requestBodies

proc parseResponse*(node: JsonNode): Response =
  if node.isNil or node.kind != JObject:
    return nil
  new(result)
  if node.hasKey("$ref"):
    result.refPath = node["$ref"].getStr
    return
  if node.hasKey("description"):
    result.description = node["description"].getStr
  if node.hasKey("headers"):
    result.headers = parseParameterMap(node["headers"])
  if node.hasKey("content"):
    result.content = parseContent(node["content"])

proc parseResponseMap*(node: JsonNode): OrderedTableRef[string, Response] =
  if node.isNil or node.kind != JObject:
    return
  new(result)
  for key, val in node.fields:
    result[key] = parseResponse(val)
