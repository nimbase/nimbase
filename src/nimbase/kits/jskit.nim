# Nimbase - Code Generator. OAPI 3.x clients, wrappers from C/C++, FFI bindings & native extensions
#
# (c) 2026 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/nimbase/nimbase

## This module implements DSL interface for creating Node.js/Bun 
## extensions in Nim

import std/[macros, strutils]
import ./js/js_api