import os, times, strutils, osproc, streams
# import moustachu
import tables
import pegs
import nwt, json
import markdown
import algorithm
import times
import packages/docutils/rst
import packages/docutils/rstgen , strtabs

var templates = newNwt("templates/*.html") # we have all the templates in a folder called "templates"

proc write_post(post: JsonNode)=
    var content = templates.renderTemplate("post.html", post)
    
    writeFile("public/" & post["Slug"].getStr & ".html", content)

proc md_processor(file_path: string): JsonNode = 
  var
    file_meta = splitFile(file_path)
    head = true
    post = initTable[string, string]()
    matches: array[0..1, string]
    src = ""
  for line in file_path.open().lines:

    if head and line.match(peg"\s* {\w+} \s* ':' \s* {.+}", matches):
      post[matches[0]] = matches[1]
    elif head and line.strip.len == 0:
      discard
    else:
      head = false
    if head == false:
      src.add line & "\n"
  if not post.contains"Slug":
    post["Slug"] = file_meta.name
  post["content"] = markdown(src)
  result = %* post

proc rstToHtml*(s: string, options: RstParseOptions,
                config: StringTableRef): string =
  ## Converts an input rst string into embeddable HTML.
  ##
  ## This convenience proc parses any input string using rst markup (it doesn't
  ## have to be a full document!) and returns an embeddable piece of HTML. The
  ## proc is meant to be used in *online* environments without access to a
  ## meaningful filesystem, and therefore rst ``include`` like directives won't
  ## work. For an explanation of the ``config`` parameter see the
  ## ``initRstGenerator`` proc. Example:
  ##
  ## .. code-block:: nim
  ##   import packages/docutils/rstgen, strtabs
  ##
  ##   echo rstToHtml("*Hello* **world**!", {},
  ##     newStringTable(modeStyleInsensitive))
  ##   # --> <em>Hello</em> <strong>world</strong>!
  ##
  ## If you need to allow the rst ``include`` directive or tweak the generated
  ## output you have to create your own ``RstGenerator`` with
  ## ``initRstGenerator`` and related procs.

  const filen = "input"
  var d: RstGenerator
  initRstGenerator(d, outHtml, config, filen, options, nil,
                   rst.defaultMsgHandler)
  var dummyHasToc = false
  var rst = rstParse(s, filen, 0, 1, dummyHasToc, options)
  # echo rst.getFieldValue("date").strip()
  result = ""
  renderRstToOut(d, rst, result)
  echo d.meta

proc rst_processor(file_path: string): JsonNode = 
  var
    file_meta = splitFile(file_path)
    head = true
    post = initTable[string, string]()
    matches: array[0..1, string]
    src = ""
  for line in file_path.open().lines:

    if head and not post.hasKey("Title") and "###" notin line:
      post["Title"] = line
    elif head and "###" in line:
      echo line
    elif head and line.match(peg"':' \s* {\w+} \s* ':' \s* {.+}", matches):
      echo matches
      post[matches[0]] = matches[1]
    elif line.strip.len == 0:
      discard
    else:
      head = false
    if head == false:
      src.add line & "\n"
  if not post.hasKey"slug":
    post["slug"] = file_meta.name
  post["Slug"] = post["slug"]
  if post.hasKey"tags":
    post["Tags"] = post["tags"]
  if post.hasKey"Date":
    post["date"] = post["Date"]
  # post["Date"] = "2019-07-26 10:00"
  post["Date"] = post["date"][0..15]

  # src = file_path.open().readAll()
# echo rstToHtml("*Hello* **world**!", {},
  post["content"] = rstToHtml(src, {
      roSkipPounds,
      roSupportRawDirective}, 
    newStringTable(modeStyleInsensitive))
  # post["content"] = markdown(src)
  result = %* post

proc write_posts(): seq[JsonNode] = 
  var
    post: JsonNode
  for file in walkDirRec "./srcs/":
    if file.endsWith ".md":
      echo file
      post = md_processor(file)
      write_post(post)
      result.add post

proc date_cmp(x, y: JsonNode): int =
  var
    a = parse(x["Date"].getStr, "yyyy-MM-dd HH:mm")
    b = parse(y["Date"].getStr, "yyyy-MM-dd HH:mm")
  if a < b: -1 else: 1

proc write_index(posts: seq[JsonNode]) =
    var
      seq_post : seq[string]
      p: string
      post_tables: seq[JsonNode]
    for post in posts:
      post_tables.add post
    post_tables.sort(date_cmp, order = SortOrder.Descending)

    for key, post in post_tables:
      p = """
    <a href="/$1.html">
      <dt>$2</dt>
      <dd>
        <time>$3</time>
      </dd>
    </a>
    """ % [
          post["Slug"].getStr,
          post["Title"].getStr,
          post["Date"].getStr,
          ]
      seq_post.add p

    var index_post = %* {
        "content": seq_post.join("\n")
      }
    var content = templates.renderTemplate("index.html", index_post)
    
    writeFile("public/" & "index.html", content)

proc write_tags(posts: seq[JsonNode]) =
    var
      post_tags = initTable[string, string]()
      p: string
      post_tables: seq[JsonNode]
      tag: string
    for post in posts:
      post_tables.add post
    post_tables.sort(date_cmp, order = SortOrder.Descending)

    for _, post in post_tables:
      if "Tags" in post:
        p = """
      <a href="/$1.html">
        <dt>$2</dt>
        <dd>
          <time>$3</time>
        </dd>
      </a>
      """ % [
            post["Slug"].getStr,
            post["Title"].getStr,
            post["Date"].getStr,
            ]
        for t_tag in post["Tags"].getStr.split(","):
          tag = t_tag.strip()
          if tag in post_tags:
            post_tags[tag].add p
          else:
            post_tags[tag] = p

    for tag, post in post_tags:
      var index_post = %* {
          "content": post,
          "tag_name": tag,
        }
      var content = templates.renderTemplate("tags.html", index_post)
      
      writeFile("public/tags/" & tag & ".html", content)


# def write_rss(posts: Sequence[frontmatter.Post]):
    # posts = sorted(posts, key=lambda post: post['date'], reverse=True)
    # path = pathlib.Path("./docs/feed.xml")
    # template = jinja_env.get_template('rss.xml')
    # rendered = template.render(posts=posts, root="https://blog.thea.codes")
    # path.write_text(rendered)

proc main()= 
  # write_pygments_style_sheet()
  # echo 1
  var
    posts = write_posts()
  # echo $posts
  write_index(posts)
  write_tags(posts)
  # write_rss(posts)


main()
