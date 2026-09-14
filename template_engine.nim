import std/[json, os, strutils, tables]

type
  TemplateEngine* = object
    baseDir*: string
    cache: ref Table[string, string]

  RenderState = object
    stack: seq[string]

proc newTemplateEngine*(baseDir = "templates"): TemplateEngine =
  result.baseDir = baseDir
  new(result.cache)
  result.cache[] = initTable[string, string]()

proc templatePath(engine: TemplateEngine; name: string): string =
  let base = normalizedPath(absolutePath(engine.baseDir))
  let path = normalizedPath(absolutePath(engine.baseDir / name))
  if name.isAbsolute or (path != base and not path.startsWith(base & $DirSep)):
    raise newException(ValueError, "template path escapes template directory: " & name)
  if not fileExists(path):
    raise newException(IOError, "template not found: " & path)
  path

proc loadTemplate(engine: TemplateEngine; path: string): string =
  if path in engine.cache[]:
    return engine.cache[][path]
  result = readFile(path)
  engine.cache[][path] = result

proc findBlockEnd(source: string; start: int): tuple[bodyEnd, endEnd: int] =
  let endStart = source.find("{% endblock", start)
  if endStart < 0:
    raise newException(ValueError, "template block has no endblock")
  let endMarker = source.find("%}", endStart)
  if endMarker < 0:
    raise newException(ValueError, "malformed endblock")
  (endStart, endMarker + 2)

proc blockName(source: string; start, headerEnd: int): string =
  result = source[start + "{% block".len ..< headerEnd].strip
  if result.len == 0:
    raise newException(ValueError, "template block must have a name")

proc collectBlocks(source: string): Table[string, string] =
  result = initTable[string, string]()
  var position = 0
  while true:
    let start = source.find("{% block", position)
    if start < 0:
      break
    let headerEnd = source.find("%}", start)
    if headerEnd < 0:
      raise newException(ValueError, "malformed block")
    let name = blockName(source, start, headerEnd)
    let ends = findBlockEnd(source, headerEnd + 2)
    if name in result:
      raise newException(ValueError, "duplicate template block: " & name)
    result[name] = source[headerEnd + 2 ..< ends.bodyEnd]
    position = ends.endEnd

proc applyBlocks(source: string; overrides: Table[string, string]): string =
  var position = 0
  while true:
    let start = source.find("{% block", position)
    if start < 0:
      if position < source.len:
        result.add source[position ..< source.len]
      break
    if position < start:
      result.add source[position ..< start]
    let headerEnd = source.find("%}", start)
    if headerEnd < 0:
      raise newException(ValueError, "malformed block")
    let name = blockName(source, start, headerEnd)
    let ends = findBlockEnd(source, headerEnd + 2)
    if name in overrides:
      result.add overrides[name]
    else:
      result.add source[headerEnd + 2 ..< ends.bodyEnd]
    position = ends.endEnd

proc renderSource(engine: TemplateEngine; name: string; context: JsonNode;
                  inherited: Table[string, string]; state: var RenderState): string

proc renderImports(engine: TemplateEngine; source: string; context: JsonNode;
                   state: var RenderState): string =
  result = source
  for keyword in ["importnimja", "importnwt"]:
    var position = 0
    while true:
      let start = result.find("{% " & keyword, position)
      if start < 0:
        break
      let endMarker = result.find("%}", start)
      if endMarker < 0:
        raise newException(ValueError, "malformed template import")
      let quoteStart = result.find('"', start, endMarker)
      let quoteEnd = if quoteStart >= 0:
        result.find('"', quoteStart + 1, endMarker)
      else:
        -1
      if quoteStart < 0 or quoteEnd < 0:
        raise newException(ValueError, "template import must name a file")
      let imported = result[quoteStart + 1 ..< quoteEnd]
      let rendered = engine.renderSource(imported, context,
        initTable[string, string](), state)
      let suffix = if endMarker + 2 < result.len: result[endMarker + 2 ..< result.len] else: ""
      result = result[0 ..< start] & rendered & suffix
      position = start + rendered.len

proc renderVariables(source: string; context: JsonNode): string =
  var position = 0
  while true:
    let start = source.find("{{", position)
    if start < 0:
      if position < source.len:
        result.add source[position ..< source.len]
      break
    if position < start:
      result.add source[position ..< start]
    let endMarker = source.find("}}", start + 2)
    if endMarker < 0:
      raise newException(ValueError, "template variable has no closing braces")
    let name = source[start + 2 ..< endMarker].strip
    if name.len == 0:
      raise newException(ValueError, "template variable must have a name")
    if context != nil and context.hasKey(name):
      result.add context[name].getStr
    position = endMarker + 2

proc renderSource(engine: TemplateEngine; name: string; context: JsonNode;
                  inherited: Table[string, string]; state: var RenderState): string =
  let path = engine.templatePath(name)
  if path in state.stack:
    raise newException(ValueError, "template import/extends cycle: " & path)
  state.stack.add path
  defer: state.stack.setLen(state.stack.len - 1)

  let source = engine.loadTemplate(path)
  let extendsStart = source.find("{% extends")
  if extendsStart >= 0:
    let extendsEnd = source.find("%}", extendsStart)
    if extendsEnd < 0:
      raise newException(ValueError, "malformed template extends")
    let quoteStart = source.find('"', extendsStart, extendsEnd)
    let quoteEnd = if quoteStart >= 0:
      source.find('"', quoteStart + 1, extendsEnd)
    else:
      -1
    if quoteStart < 0 or quoteEnd < 0:
      raise newException(ValueError, "template extends must name a file")
    var overrides = collectBlocks(source)
    for blockName, blockContent in inherited:
      overrides[blockName] = blockContent
    return engine.renderSource(source[quoteStart + 1 ..< quoteEnd], context,
      overrides, state)

  var rendered = applyBlocks(source, inherited)
  rendered = renderImports(engine, rendered, context, state)
  renderVariables(rendered, context)

proc renderTemplate*(engine: TemplateEngine; name: string;
                     context: JsonNode): string =
  var state = RenderState()
  engine.renderSource(name, context, initTable[string, string](), state)
