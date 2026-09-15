import std/[os, strutils]

import site_builder

proc usage() =
  echo "Usage: kun [options]"
  echo ""
  echo "Options:"
  echo "  --source-dir DIR     Markdown source directory (default: srcs)"
  echo "  --template-dir DIR   Template directory (default: templates)"
  echo "  --output-dir DIR     Output directory (default: public)"
  echo "  --site-root URL      Site root URL (default: https://muxueqz.top)"
  echo "  --site-description TEXT"
  echo "                       Site description (default: " & DefaultSiteDescription & ")"
  echo "  --clean              Remove files from the previous generated manifest"
  echo "  --help               Show this help"

proc optionValue(args: seq[string]; index: var int; option, inlineValue: string): string =
  if inlineValue.len > 0:
    return inlineValue
  inc index
  if index >= args.len or args[index].startsWith("-"):
    raise newException(ValueError, option & " requires a value")
  args[index]

proc main() =
  var
    config = defaultBuildConfig()
    args = commandLineParams()
    index = 0

  while index < args.len:
    let argument = args[index]
    if argument == "--help" or argument == "-h":
      usage()
      return
    if argument == "--clean":
      config.cleanOutput = true
    elif argument.startsWith("--"):
      let separator = argument.find('=')
      let option = if separator >= 0: argument[0 ..< separator] else: argument
      let inlineValue = if separator >= 0: argument[separator + 1 .. ^1] else: ""
      case option
      of "--source-dir": config.sourceDir = optionValue(args, index, option, inlineValue)
      of "--template-dir": config.templateDir = optionValue(args, index, option, inlineValue)
      of "--output-dir": config.outputDir = optionValue(args, index, option, inlineValue)
      of "--site-root": config.siteRoot = optionValue(args, index, option, inlineValue)
      of "--site-description": config.siteDescription = optionValue(args, index, option, inlineValue)
      else: raise newException(ValueError, "unknown option: " & option)
    else:
      raise newException(ValueError, "unexpected argument: " & argument)
    inc index

  try:
    buildSite(config)
  except CatchableError as error:
    stderr.writeLine("kun: " & error.msg)
    quit(1)

when isMainModule:
  try:
    main()
  except ValueError as error:
    stderr.writeLine("kun: " & error.msg)
    stderr.writeLine("Try 'kun --help' for usage.")
    quit(1)
