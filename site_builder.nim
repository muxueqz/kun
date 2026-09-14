import std/[algorithm, json, os, sequtils, strutils, tables, terminal, times]

import markdown
import template_engine

const
  InputDateFormat* = "yyyy-MM-dd HH:mm"
  DefaultSiteRoot* = "https://muxueqz.top"

type
  BuildError* = object of CatchableError

  BuildConfig* = object
    sourceDir*: string
    templateDir*: string
    outputDir*: string
    siteRoot*: string
    cleanOutput*: bool
    progressEnabled: bool

  Post* = object
    metadata*: Table[string, string]
    slug*: string
    title*: string
    dateText*: string
    date*: DateTime
    tags*: seq[string]
    author*: string
    summary*: string
    content*: string

  GeneratedFile = object
    relativePath: string
    content: string

  ProgressReporter = object
    total: int
    completed: int
    enabled: bool
    interactive: bool
    active: bool

proc defaultBuildConfig*(): BuildConfig =
  BuildConfig(
    sourceDir: "srcs",
    templateDir: "templates",
    outputDir: "public",
    siteRoot: DefaultSiteRoot,
    cleanOutput: false,
    progressEnabled: true,
  )

proc buildError(message: string): ref BuildError =
  newException(BuildError, message)

proc fail(path, message: string; line = 0) {.noreturn.} =
  let location = if line > 0: path & ":" & $line else: path
  raise buildError(location & ": " & message)

proc htmlEscape*(value: string): string =
  for c in value:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add c

proc xmlEscape(value: string): string =
  htmlEscape(value)

proc isSafeComponent(value: string): bool =
  if value.len == 0 or value in [".", ".."]:
    return false
  for c in value:
    if c == DirSep or c == AltSep or c.ord < 0x20 or c == '\x7f':
      return false
  true

proc parseMetadataLine(line: string): tuple[matched: bool, key, value: string] =
  let separator = line.find(':')
  if separator <= 0:
    return (false, "", "")
  let key = line[0 ..< separator].strip
  if key.len == 0:
    return (false, "", "")
  for c in key:
    if not (c.isAlphaNumeric or c == '_'):
      return (false, "", "")
  let value = if separator + 1 < line.len: line[separator + 1 .. ^1].strip else: ""
  (true, key, value)

proc parsePost*(filePath: string): Post =
  if not fileExists(filePath):
    fail(filePath, "source file does not exist")

  var
    inHeader = true
    metadata = initTable[string, string]()
    source = newStringOfCap(getFileSize(filePath).int)
    lineNumber = 0

  for line in filePath.lines:
    inc lineNumber
    if inHeader:
      let parsed = parseMetadataLine(line)
      if parsed.matched:
        if parsed.key in metadata:
          fail(filePath, "duplicate metadata field '" & parsed.key & "'", lineNumber)
        metadata[parsed.key] = parsed.value
        continue
      if line.strip.len == 0:
        continue
      inHeader = false
    source.add line
    source.add '\n'

  if not metadata.hasKey("Title") or metadata["Title"].strip.len == 0:
    fail(filePath, "missing required metadata field 'Title'")
  if not metadata.hasKey("Date") or metadata["Date"].strip.len == 0:
    fail(filePath, "missing required metadata field 'Date'")

  result.metadata = metadata
  result.title = metadata["Title"].strip
  result.dateText = metadata["Date"].strip
  try:
    result.date = parse(result.dateText, InputDateFormat)
  except ValueError:
    fail(filePath, "invalid Date, expected " & InputDateFormat)

  result.slug = if metadata.hasKey("Slug") and metadata["Slug"].strip.len > 0:
    metadata["Slug"].strip
  else:
    splitFile(filePath).name
  if not isSafeComponent(result.slug):
    fail(filePath, "Slug contains an unsafe path component: " & result.slug)

  var rawTags: seq[string]
  if metadata.hasKey("Tags"):
    rawTags.add metadata["Tags"].split(',')
  if metadata.hasKey("Category"):
    rawTags.add metadata["Category"]
  for rawTag in rawTags:
    let tag = rawTag.strip
    if tag.len == 0:
      continue
    if not isSafeComponent(tag):
      fail(filePath, "tag contains an unsafe path component: " & tag)
    if tag notin result.tags:
      result.tags.add tag
  result.tags.sort(system.cmp[string])

  result.author = if metadata.hasKey("Author"): metadata["Author"].strip else: ""
  result.summary = if metadata.hasKey("Summary"): metadata["Summary"].strip else: ""
  result.content = markdown(source)

proc parsePosts(config: BuildConfig): seq[Post] =
  if not dirExists(config.sourceDir):
    raise buildError("source directory does not exist: " & config.sourceDir)

  var files: seq[string]
  for file in walkDirRec(config.sourceDir):
    if file.toLowerAscii.endsWith(".md"):
      files.add file
  files.sort(system.cmp[string])

  var slugs = initTable[string, string]()
  for file in files:
    let post = parsePost(file)
    if post.slug in slugs:
      fail(file, "duplicate Slug '" & post.slug & "', already used by " & slugs[post.slug])
    slugs[post.slug] = file
    result.add post

proc postDateCmp(a, b: Post): int =
  result = cmp(a.date, b.date)
  if result == 0:
    result = cmp(a.slug, b.slug)

proc htmlPostContext(post: Post; siteRoot: string): JsonNode =
  var context = initTable[string, string]()
  for key, value in post.metadata:
    context[key] = htmlEscape(value)
  context["Title"] = htmlEscape(post.title)
  context["Date"] = htmlEscape(post.dateText)
  context["Slug"] = htmlEscape(post.slug)
  context["Tags"] = htmlEscape(post.tags.join(","))
  context["Author"] = htmlEscape(post.author)
  context["Summary"] = htmlEscape(post.summary)
  context["content"] = post.content
  context["root"] = htmlEscape(siteRoot)
  context["tag_links"] = ""
  for tag in post.tags:
    context["tag_links"].add "\n<a class=\"label\" href=\"/tags/" & htmlEscape(tag) & ".html\">\n" &
      htmlEscape(tag) & "\n</a>\n"
  %* context

proc indexPostHtml(posts: seq[Post]): string =
  var postHtml: seq[string]
  for post in posts:
    postHtml.add """
    <h2>
      <a href="/$1.html"> $2 </a>
    </h2>
    <div id=date>
      <time>$3</time>
    </div>
    <div class="summary">
    $4
    </div>
    """ % [
      htmlEscape(post.slug), htmlEscape(post.title), htmlEscape(post.dateText),
      htmlEscape(post.summary),
    ]
  postHtml.join("\n")

proc tagCloudHtml(posts: seq[Post]): string =
  var tags = initTable[string, int]()
  for post in posts:
    for tag in post.tags:
      tags[tag] = tags.getOrDefault(tag, 0) + 1
  var names = toSeq(tags.keys)
  names.sort(system.cmp[string])
  for tag in names:
    result.add """
      <a class="label" href="/tags/$1.html">
      $1
      </a>
      """ % htmlEscape(tag)

proc renderFile(relativePath, content: string): GeneratedFile =
  GeneratedFile(relativePath: relativePath, content: content)

proc generatedFileCount(posts: seq[Post]): int =
  var tags = initTable[string, bool]()
  for post in posts:
    for tag in post.tags:
      tags[tag] = true
  posts.len + tags.len + 5

proc newProgressReporter(total: int; enabled: bool): ProgressReporter =
  ProgressReporter(total: total, enabled: enabled,
    interactive: enabled and stderr.isatty)

proc showProgress(reporter: var ProgressReporter; path: string) =
  let percent = if reporter.total > 0: reporter.completed * 100 div reporter.total else: 100
  let message = "Building pages [" & $reporter.completed & "/" & $reporter.total & "] " &
    $percent & "% - " & path
  if reporter.interactive:
    stderr.write('\r')
    stderr.eraseLine()
    stderr.write(message)
    flushFile(stderr)
  else:
    stderr.writeLine(message)

proc beginFile(reporter: var ProgressReporter; path: string) =
  if not reporter.enabled:
    return
  reporter.active = true
  if reporter.interactive:
    let message = "Building pages [" & $reporter.completed & "/" & $reporter.total & "] - " & path
    stderr.write('\r')
    stderr.eraseLine()
    stderr.write(message)
    flushFile(stderr)

proc completeFile(reporter: var ProgressReporter; path: string) =
  if not reporter.enabled:
    return
  inc reporter.completed
  reporter.showProgress(path)

proc finish(reporter: var ProgressReporter; success: bool) =
  if not reporter.enabled or not reporter.active:
    return
  if reporter.interactive:
    stderr.write("\n")
  elif success:
    stderr.writeLine("Built " & $reporter.completed & " generated files.")
  reporter.active = false

proc renderTracked(reporter: var ProgressReporter; engine: TemplateEngine;
                   relativePath, templateName: string; context: JsonNode): GeneratedFile =
  reporter.beginFile(relativePath)
  result = renderFile(relativePath, engine.renderTemplate(templateName, context))
  reporter.completeFile(relativePath)

proc generateFiles(config: BuildConfig; posts: seq[Post];
                   reporter: var ProgressReporter): seq[GeneratedFile] =
  var engine = newTemplateEngine(config.templateDir)
  var orderedPosts = posts
  orderedPosts.sort(postDateCmp, order = SortOrder.Descending)

  for post in orderedPosts:
    result.add renderTracked(reporter, engine, post.slug & ".html", "post.templ",
      htmlPostContext(post, config.siteRoot))

  let indexContext = %* {
    "content": indexPostHtml(orderedPosts),
    "tags": tagCloudHtml(orderedPosts),
  }
  result.add renderTracked(reporter, engine, "index.html", "index.templ", indexContext)

  var postsByTag = initTable[string, seq[Post]]()
  for post in orderedPosts:
    for tag in post.tags:
      postsByTag.mgetOrPut(tag, @[]).add post
  var tagNames = toSeq(postsByTag.keys)
  tagNames.sort(system.cmp[string])
  for tag in tagNames:
    var tagContent: seq[string]
    for post in postsByTag[tag]:
      tagContent.add """
          <h2>
            <a href="/$1.html"> $2 </a>
          </h2>
          <div id=date>
            <time>$3</time>
          </div>
          """ % [htmlEscape(post.slug), htmlEscape(post.title), htmlEscape(post.dateText)]
    let tagContext = %* {
      "content": tagContent.join("\n"),
      "tag_name": htmlEscape(tag),
    }
    result.add renderTracked(reporter, engine, "tags" / (tag & ".html"),
      "tags.templ", tagContext)

  var rssItems: seq[string]
  for post in orderedPosts:
    let link = config.siteRoot & "/" & post.slug & ".html"
    let rssDate = post.date - 8.hours
    rssItems.add """
  <item>
    <title>$1</title>
    <link>$2</link>
    <guid>$2</guid>
    <pubDate>$3</pubDate>
  </item>
    """ % [xmlEscape(post.title), xmlEscape(link),
      xmlEscape(format(rssDate, "ddd, dd MMM yyyy HH:mm:ss \'GMT\'"))]
  result.add renderTracked(reporter, engine, "feed.xml", "rss.templ", %* {
    "content": rssItems.join("\n"),
    "site_root": xmlEscape(config.siteRoot),
  })

  let atomUpdated = if orderedPosts.len > 0:
    format(orderedPosts[0].date, "yyyy-MM-dd\'T\'HH:mm:sszzz")
  else:
    format(now().utc, "yyyy-MM-dd\'T\'HH:mm:ss\'Z\'")
  var atomEntries: seq[string]
  for post in orderedPosts:
    let link = config.siteRoot & "/" & post.slug & ".html"
    atomEntries.add """
  <entry>
    <title>$1</title>
    <link href="$2" rel="alternate"></link>
    <published>$3</published>
    <updated>$3</updated>
    <author><name>muxueqz</name></author>
    <id>$2</id>
    <summary type="html">$4</summary>
    """ % [xmlEscape(post.title), xmlEscape(link),
      xmlEscape(format(post.date, "yyyy-MM-dd\'T\'HH:mm:sszzz")),
      xmlEscape(post.summary)]
    for tag in post.tags:
      atomEntries.add "  <category term=\"" & xmlEscape(tag) & "\"></category>"
    atomEntries.add "</entry>"
  result.add renderTracked(reporter, engine, "all.atom.xml", "atom.templ", %* {
    "content": atomEntries.join("\n"),
    "root": xmlEscape(config.siteRoot),
    "updated": xmlEscape(atomUpdated),
  })

  var sitemapEntries: seq[string]
  for post in orderedPosts:
    sitemapEntries.add """
<url>
  <loc>$1/$2.html</loc>
  <lastmod>$3</lastmod>
  <priority>1.00</priority>
</url>
    """ % [xmlEscape(config.siteRoot), xmlEscape(post.slug),
      xmlEscape(format(post.date, "yyyy-MM-dd\'T\'HH:mm:sszzz"))]
  result.add renderTracked(reporter, engine, "sitemap.xml", "sitemap.templ", %* {
    "content": sitemapEntries.join("\n"),
    "root": xmlEscape(config.siteRoot),
  })

proc safeManifestPath(path: string): bool =
  let normalized = normalizedPath(path)
  not path.isAbsolute and path != "" and
    not normalized.startsWith(".." & $DirSep) and
    not (DirSep & ".." & $DirSep in normalized) and
    not (AltSep & ".." & AltSep in normalized)

proc readManifest(outputDir: string): seq[string] =
  let manifestPath = outputDir / ".kun-manifest.json"
  if not fileExists(manifestPath):
    return
  let manifest = parseJson(readFile(manifestPath))
  if manifest.kind != JArray:
    raise buildError("invalid generated manifest: " & manifestPath)
  for item in manifest:
    if item.kind != JString or not safeManifestPath(item.getStr):
      raise buildError("invalid path in generated manifest: " & manifestPath)
    result.add item.getStr

proc writeAtomically(path, content: string) =
  let temporaryPath = path & ".tmp"
  writeFile(temporaryPath, content)
  try:
    moveFile(temporaryPath, path)
  except CatchableError:
    if fileExists(temporaryPath):
      removeFile(temporaryPath)
    raise

proc buildSite*(config: BuildConfig) =
  var effective = config
  while effective.siteRoot.endsWith("/"):
    effective.siteRoot.setLen(effective.siteRoot.len - 1)
  if effective.siteRoot.len == 0:
    raise buildError("site root cannot be empty")

  let posts = parsePosts(effective)
  var sortedPosts = posts
  sortedPosts.sort(postDateCmp, order = SortOrder.Descending)
  var reporter = newProgressReporter(generatedFileCount(sortedPosts), effective.progressEnabled)
  var buildSucceeded = false
  defer: reporter.finish(buildSucceeded)
  let generated = generateFiles(effective, sortedPosts, reporter)

  createDir(effective.outputDir)
  createDir(effective.outputDir / "tags")
  let oldManifest = if effective.cleanOutput: readManifest(effective.outputDir) else: @[]
  var currentManifest: seq[string]
  for file in generated:
    currentManifest.add file.relativePath
    let target = effective.outputDir / file.relativePath
    createDir(parentDir(target))
    writeAtomically(target, file.content)

  if effective.cleanOutput:
    for oldPath in oldManifest:
      if oldPath notin currentManifest:
        let target = effective.outputDir / oldPath
        if fileExists(target):
          removeFile(target)

  var manifest = newJArray()
  for path in currentManifest:
    manifest.add %path
  writeAtomically(effective.outputDir / ".kun-manifest.json", $manifest)
  reporter.beginFile(".kun-manifest.json")
  reporter.completeFile(".kun-manifest.json")
  buildSucceeded = true
