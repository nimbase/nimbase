# {nimbase_pkg_name} API client for Nim
#
# Auto-generated from OpenAPI 3.x specification
# using the awesome [Nimbase CLI](https://github.com/nimbase/nimbase)
#
# Generated at: {nimbase_pkg_generation_time}
# License: {nimbase_pkg_license}

import std/[asyncdispatch, httpclient, tables,
        strutils, sequtils, times, uri]

import pkg/openparser/json
{nimbase_renames_import}

export asyncdispatch, httpclient, json, tables, sequtils, times
{nimbase_renames_export}

type
  {nimbase_client_ident}* = ref object of RootObj
    baseUri*: string
    httpClient*: AsyncHttpClient
    apiKey*: string

  QueryTable* = OrderedTable[string, string]

  {nimbase_client_ident_error}* = object of CatchableError

proc `$`*(query: QueryTable): string =
  if query.len > 0:
    add result, "?"
    add result, join(query.keys.toSeq.mapIt(it & "=" & query[it]), "&")

proc init{nimbase_client_ident}*(apiKey: string): {nimbase_client_ident} =
  new(result)
  result.baseUri = "{nimbase_base_uri}"
  result.httpClient = newAsyncHttpClient()
  result.httpClient.headers = newHttpHeaders({
    "Accept": "application/json",
    "Authorization": "Bearer " & apiKey
  })
  result.apiKey = apiKey

proc httpGet*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.get(url)

proc httpGet*(client: {nimbase_client_ident},
  endpoint: string, query: QueryTable): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint & $query
  result = await client.httpClient.get(url)

proc httpPost*[T](client: {nimbase_client_ident},
  endpoint: string, body: T): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.post(url, toJson(body))

proc httpPost*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.post(url)

proc httpPost*(client: {nimbase_client_ident},
  endpoint: string, query: QueryTable): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint & $query
  result = await client.httpClient.post(url)

proc httpPut*[T](client: {nimbase_client_ident},
  endpoint: string, body: T): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpPut,
    body = toJson(body))

proc httpPut*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpPut)

proc httpPut*(client: {nimbase_client_ident},
  endpoint: string, query: QueryTable): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint & $query
  result = await client.httpClient.request(url, httpMethod = HttpPut)

proc httpDelete*[T](client: {nimbase_client_ident},
  endpoint: string, body: T): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpDelete,
    body = toJson(body))

proc httpDelete*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpDelete)

proc httpDelete*(client: {nimbase_client_ident},
  endpoint: string, query: QueryTable): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint & $query
  result = await client.httpClient.request(url, httpMethod = HttpDelete)

proc httpPatch*[T](client: {nimbase_client_ident},
  endpoint: string, body: T): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpPatch,
    body = toJson(body))

proc httpPatch*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpPatch)
