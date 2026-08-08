# {nimbase_pkg_name}

{nimbase_pkg_desc}

## Installation

```bash
nimble install {nimbase_pkg_name}
```

## Usage

```nim
import {nimbase_pkg_name}

proc main() {.async.} =
  var client = init{nimbase_client_ident}("your-api-key")
  let servers = await client.getServers()
  echo servers

waitFor main()
```

## License

{nimbase_pkg_license}
