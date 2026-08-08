# {nimbase_pkg_name} API client for Nim
#
# Auto-generated from OpenAPI 3.x specification
# using the awesome [Nimbase CLI](https://github.com/nimbase/nimbase)
#
# Generated at: {nimbase_pkg_generation_time}
# License: {nimbase_pkg_license}

import std/[asyncdispatch, httpclient, tables,
        strutils, sequtils, times, uri, options]

import pkg/oauth2
import pkg/openparser/json
{nimbase_renames_import}

export asyncdispatch, httpclient, json, options, times, oauth2, tables, sequtils

type
  {nimbase_client_ident}* = ref object of RootObj
    baseUri*: string
    httpClient*: AsyncHttpClient
    accessToken*: Option[string]
    refreshToken*: Option[string]
    tokenExpiry*: Option[int]
    oauthClientId*: Option[string]
    oauthClientSecret*: Option[string]

  QueryTable* = OrderedTable[string, string]

  {nimbase_client_ident_error}* = object of CatchableError

const
  oauthTokenUrl* = "{nimbase_oauth_token_url}"
  oauthAuthUrl* = "{nimbase_oauth_auth_url}"

proc `$`*(query: QueryTable): string =
  if query.len > 0:
    add result, "?"
    add result, join(query.keys.toSeq.mapIt(it & "=" & query[it]), "&")

proc init{nimbase_client_ident}*: {nimbase_client_ident} =
  new(result)
  result.baseUri = "{nimbase_base_uri}"
  result.httpClient = newAsyncHttpClient()
  result.httpClient.headers = newHttpHeaders({
    "Accept": "application/json"
  })

proc configureOAuth*(client: {nimbase_client_ident}, clientId, clientSecret: string) =
  client.oauthClientId = some(clientId)
  client.oauthClientSecret = some(clientSecret)

proc setTokens*(client: {nimbase_client_ident}, accessToken, refreshToken: string,
                expiresIn: Option[int] = none(int)) =
  client.accessToken = some(accessToken)
  if refreshToken.len > 0:
    client.refreshToken = some(refreshToken)
  client.tokenExpiry = expiresIn

proc canAutoRefresh*(client: {nimbase_client_ident}): bool =
  client.refreshToken.isSome and
    client.oauthClientId.isSome and
    client.oauthClientSecret.isSome and
    oauthTokenUrl.len > 0

proc tryRefreshToken*(client: {nimbase_client_ident}): Future[bool] {.async.} =
  if not client.canAutoRefresh:
    return false
  let resp = await refreshToken(
    client.httpClient,
    oauthTokenUrl,
    client.oauthClientId.get,
    client.oauthClientSecret.get,
    client.refreshToken.get
  )
  let body = await resp.body
  let json = parseJson(body)
  if not json.hasKey("access_token"):
    return false
  let newAccessToken = json["access_token"].getStr()
  let newRefreshToken =
    if json.hasKey("refresh_token"): json["refresh_token"].getStr()
    else: client.refreshToken.get
  client.setTokens(newAccessToken, newRefreshToken)
  return true

proc getAuthorizationUrl*(clientId, redirectUri: string,
                          scopes: openArray[string] = [],
                          state = ""): string =
  result = oauthAuthUrl & "?" &
    "client_id=" & clientId.encodeUrl & "&" &
    "redirect_uri=" & redirectUri.encodeUrl & "&" &
    "response_type=code"
  if scopes.len > 0:
    result.add("&scope=" & scopes.join(" ").encodeUrl)
  if state.len > 0:
    result.add("&state=" & state.encodeUrl)

proc exchangeCodeForToken*(clientId, clientSecret, code, redirectUri: string): Future[JsonNode] {.async.} =
  var http = newAsyncHttpClient()
  http.headers = newHttpHeaders({
    "Accept": "application/json",
    "Content-Type": "application/x-www-form-urlencoded"
  })
  let body =
    "client_id=" & clientId.encodeUrl &
    "&client_secret=" & clientSecret.encodeUrl &
    "&code=" & code.encodeUrl &
    "&grant_type=authorization_code" &
    "&redirect_uri=" & redirectUri.encodeUrl
  let resp = await http.post(oauthTokenUrl, body)
  result = parseJson(await resp.body)

proc authRequest(client: {nimbase_client_ident}) =
  if client.accessToken.isSome:
    client.httpClient.headers["Authorization"] = "Bearer " & client.accessToken.get

proc httpGet*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.get(url)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.get(url)

proc httpGet*(client: {nimbase_client_ident},
  endpoint: string, query: QueryTable): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint & $query
  result = await client.httpClient.get(url)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.get(url)

proc httpPost*[T](client: {nimbase_client_ident},
  endpoint: string, body: T): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.post(url, toJson(body))
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.post(url, toJson(body))

proc httpPost*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.post(url)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.post(url)

proc httpPost*(client: {nimbase_client_ident},
  endpoint: string, query: QueryTable): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint & $query
  result = await client.httpClient.post(url)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.post(url)

proc httpPut*[T](client: {nimbase_client_ident},
  endpoint: string, body: T): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpPut,
    body = toJson(body))
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.request(url, httpMethod = HttpPut,
      body = toJson(body))

proc httpPut*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpPut)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.request(url, httpMethod = HttpPut)

proc httpPut*(client: {nimbase_client_ident},
  endpoint: string, query: QueryTable): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint & $query
  result = await client.httpClient.request(url, httpMethod = HttpPut)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.request(url, httpMethod = HttpPut)

proc httpDelete*[T](client: {nimbase_client_ident},
  endpoint: string, body: T): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpDelete,
    body = toJson(body))
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.request(url, httpMethod = HttpDelete,
      body = toJson(body))

proc httpDelete*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpDelete)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.request(url, httpMethod = HttpDelete)

proc httpDelete*(client: {nimbase_client_ident},
  endpoint: string, query: QueryTable): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint & $query
  result = await client.httpClient.request(url, httpMethod = HttpDelete)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.request(url, httpMethod = HttpDelete)

proc httpPatch*[T](client: {nimbase_client_ident},
  endpoint: string, body: T): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpPatch,
    body = toJson(body))
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.request(url, httpMethod = HttpPatch,
      body = toJson(body))

proc httpPatch*(client: {nimbase_client_ident},
  endpoint: string): Future[AsyncResponse] {.async.} =
  client.authRequest
  let url = client.baseUri & endpoint
  result = await client.httpClient.request(url, httpMethod = HttpPatch)
  if result.code == Http401 and await client.tryRefreshToken:
    client.authRequest
    result = await client.httpClient.request(url, httpMethod = HttpPatch)
