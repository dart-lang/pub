#!/usr/bin/bash

[ tool/test.dart -nt .dart_tool/pub/test.jit ] && dart compile jit-snapshot tool/test.dart precompiling && mv tool/test.jit .dart_tool/pub/test.jit
dart .dart_tool/pub/test.jit $*