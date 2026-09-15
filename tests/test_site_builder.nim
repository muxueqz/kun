import std/[json, os, strutils, times, unittest]

import site_builder
import template_engine

proc testRoot(): string =
  getTempDir() / ("kun-test-" & $int(epochTime()))

proc writeFixture(root, name, content: string) =
  let path = root / name
  createDir(parentDir(path))
  writeFile(path, content)

suite "site builder":
  test "parses metadata with blank lines and category tags":
    let root = testRoot()
    createDir(root)
    defer: removeDir(root)
    let source = root / "post.md"
    writeFile(source, """Title: Example

Tags: nim, blog, nim
Date: 2024-01-02 03:04
Category: notes
Slug: example

Body
""")
    let post = parsePost(source)
    check post.title == "Example"
    check post.slug == "example"
    check post.tags == @["blog", "nim", "notes"]
    check post.content.contains("Body")

  test "rejects invalid metadata":
    let root = testRoot()
    createDir(root)
    defer: removeDir(root)
    let source = root / "post.md"
    writeFile(source, "Title: Example\nDate: not-a-date\n\nBody\n")
    expect BuildError:
      discard parsePost(source)

  test "rejects duplicate slugs":
    let root = testRoot()
    let sourceDir = root / "srcs"
    createDir(sourceDir)
    defer: removeDir(root)
    writeFixture(sourceDir, "one.md", "Title: One\nDate: 2024-01-01 00:00\nSlug: same\n\nOne\n")
    writeFixture(sourceDir, "two.md", "Title: Two\nDate: 2024-01-02 00:00\nSlug: same\n\nTwo\n")
    expect BuildError:
      buildSite(BuildConfig(sourceDir: sourceDir, templateDir: root,
        outputDir: root / "public", siteRoot: "https://example.com"))

  test "template engine preserves missing variables and rejects malformed variables":
    let root = testRoot()
    createDir(root)
    defer: removeDir(root)
    writeFixture(root, "base.templ", "{% block content %}default{% endblock %}")
    writeFixture(root, "page.templ", "{% extends \"base.templ\" %}{% block content %}{{missing}}ok{% endblock %}")
    let engine = newTemplateEngine(root)
    check engine.renderTemplate("page.templ", %* {}) == "ok"
    writeFixture(root, "broken.templ", "{{broken")
    expect ValueError:
      discard engine.renderTemplate("broken.templ", %* {})

  test "generates an empty site without crashing":
    let root = testRoot()
    let sourceDir = root / "srcs"
    let templateDir = root / "templates"
    let outputDir = root / "public"
    createDir(sourceDir)
    createDir(templateDir)
    defer: removeDir(root)
    writeFixture(templateDir, "layout.templ", "{% block meta_data %}{% endblock %}{% block content %}{% endblock %}")
    writeFixture(templateDir, "index.templ", "{% extends \"layout.templ\" %}{% block content %}{{content}}{% endblock %}")
    writeFixture(templateDir, "post.templ", "{% extends \"layout.templ\" %}{% block content %}{{content}}{% endblock %}")
    writeFixture(templateDir, "tags.templ", "{% extends \"layout.templ\" %}{% block content %}{{content}}{% endblock %}")
    writeFixture(templateDir, "rss.templ", "{{content}}")
    writeFixture(templateDir, "atom.templ", "{{updated}}{{content}}")
    writeFixture(templateDir, "sitemap.templ", "{{content}}")
    buildSite(BuildConfig(sourceDir: sourceDir, templateDir: templateDir,
      outputDir: outputDir, siteRoot: "https://example.com"))
    check fileExists(outputDir / "index.html")
    check fileExists(outputDir / "feed.xml")
    check fileExists(outputDir / "all.atom.xml")
    check fileExists(outputDir / "sitemap.xml")

  test "generates configurable SEO descriptions and one h1 per page":
    let root = testRoot()
    let sourceDir = root / "srcs"
    let outputDir = root / "public"
    createDir(sourceDir)
    defer: removeDir(root)
    writeFixture(sourceDir, "explicit.md", """Title: Explicit
Date: 2024-01-01 00:00
Tags: notes
Summary: Explicit summary
Slug: explicit

# Section

Body text.
""")
    writeFixture(sourceDir, "fallback.md", """Title: Fallback
Date: 2024-01-02 00:00
Tags: notes
Slug: fallback

Fallback body text.
""")

    var config = defaultBuildConfig()
    config.sourceDir = sourceDir
    config.templateDir = getCurrentDir() / "templates"
    config.outputDir = outputDir
    config.siteRoot = "https://example.com"
    config.siteDescription = "自定义站点描述 & 技术博客"
    buildSite(config)

    let index = readFile(outputDir / "index.html")
    let explicit = readFile(outputDir / "explicit.html")
    let fallback = readFile(outputDir / "fallback.html")
    let tag = readFile(outputDir / "tags" / "notes.html")
    check index.count("<h1>") == 1
    check index.count("<h2>") >= 2
    check index.contains("content=\"自定义站点描述 &amp; 技术博客\"")
    check explicit.count("<h1>") == 1
    check explicit.contains("<h2>Section</h2>")
    check explicit.contains("content=\"Explicit summary\"")
    check fallback.count("<h1>") == 1
    check fallback.contains("content=\"Fallback body text.\"")
    check tag.count("<h1>") == 1
    check tag.contains("content=\"自定义站点描述 &amp; 技术博客\"")

  test "clean removes stale generated files but keeps static assets":
    let root = testRoot()
    let sourceDir = root / "srcs"
    let templateDir = root / "templates"
    let outputDir = root / "public"
    createDir(sourceDir)
    createDir(templateDir)
    defer: removeDir(root)
    writeFixture(templateDir, "layout.templ", "{% block meta_data %}{% endblock %}{% block content %}{% endblock %}")
    writeFixture(templateDir, "index.templ", "{% extends \"layout.templ\" %}{% block content %}{{content}}{% endblock %}")
    writeFixture(templateDir, "post.templ", "{% extends \"layout.templ\" %}{% block content %}{{content}}{% endblock %}")
    writeFixture(templateDir, "tags.templ", "{% extends \"layout.templ\" %}{% block content %}{{content}}{% endblock %}")
    writeFixture(templateDir, "rss.templ", "{{content}}")
    writeFixture(templateDir, "atom.templ", "{{updated}}{{content}}")
    writeFixture(templateDir, "sitemap.templ", "{{content}}")
    writeFixture(sourceDir, "one.md", "Title: One\nDate: 2024-01-01 00:00\nSlug: one\n\nOne\n")
    createDir(outputDir)
    writeFile(outputDir / "static.txt", "keep")
    buildSite(BuildConfig(sourceDir: sourceDir, templateDir: templateDir,
      outputDir: outputDir, siteRoot: "https://example.com"))
    removeFile(sourceDir / "one.md")
    writeFixture(sourceDir, "two.md", "Title: Two\nDate: 2024-01-02 00:00\nSlug: two\n\nTwo\n")
    buildSite(BuildConfig(sourceDir: sourceDir, templateDir: templateDir,
      outputDir: outputDir, siteRoot: "https://example.com", cleanOutput: true))
    check not fileExists(outputDir / "one.html")
    check fileExists(outputDir / "two.html")
    check fileExists(outputDir / "static.txt")
