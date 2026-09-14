version       = "1.4.0"
author        = "muxueqz"
description   = "A small static site generator"
license       = "MIT"
srcDir        = "."
bin           = @["kun"]

requires "nim >= 2.0.0"
requires "marvdown == 0.2.3"

task test, "Run the test suite":
  exec "nim c -r --hints:off --path:. tests/test_site_builder.nim"

task build, "Build the kun executable":
  exec "mkdir -p dist"
  exec "nim c -d:release --path:. -o:dist/kun kun.nim"
