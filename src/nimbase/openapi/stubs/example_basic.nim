# {nimbase_pkg_name} — runnable example
#
# Auto-generated from OpenAPI 3.x via Nimbase. Run with:
#   nim r examples/basic.nim

import {nimbase_pkg_name}
import std/asyncdispatch

proc main() {.async.} =
{nimbase_example_body}

when isMainModule:
  waitFor main()
