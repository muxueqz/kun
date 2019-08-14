import os, times, strutils, osproc, streams
import tables
import sequtils
import pegs
import nwt, json
import markdown
import algorithm

var
  templates = newNwt("templates/*.templ") # we have all the templates in a folder called "templates"
  site_root = "https://muxueqz.top"

proc write_post(post: JsonNode)=
    var
      p: string
      new_post = initTable[string, string]()
    new_post["Tags"] = ""
    for k, v in post:
      new_post[k] = v.getStr
    new_post["tag_links"] = ""
    if "Tags" in post:
      for tag in post["Tags"].getStr.split(","):
        p = """
        <a class="label" href="/tags/$1.html">
        $1
        </a>
        """ % tag
        new_post["tag_links"].add p
    new_post["root"] = "https://muxueqz.top"
    var json_post = %* new_post
    var content = templates.renderTemplate("post.templ", json_post)
    
    writeFile("public/" & post["Slug"].getStr & ".html", content)

proc md_processor(file_path: string): JsonNode = 
  var
    file_meta = splitFile(file_path)
    head = true
    post = initTable[string, string]()
    matches: array[0..1, string]
    src = ""
    tags = initCountTable[string]()
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
  if "Category" in post:
    if "Tags" in post:
      post["Tags"].add "," & post["Category"]
    else:
      post["Tags"] = post["Category"]

  if "Tags" in post:
    for tag in post["Tags"].split(","):
      tags.inc tag.strip()

    post["Tags"] = toSeq(tags.keys()).join(",")
  post["content"] = markdown(src)
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

proc sort_posts(posts: seq[JsonNode]): seq[JsonNode] = 
    for post in posts:
      result.add post
    result.sort(date_cmp, order = SortOrder.Descending)

proc write_index(posts: seq[JsonNode]) =
    var
      seq_post : seq[string]
      tags = initCountTable[string]()
      p, summary, tag_cloud: string

    for key, post in posts:
      if "Summary" in post:
        summary = post["Summary"].getStr
      else:
        summary = ""
      p = """
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
          post["Slug"].getStr,
          post["Title"].getStr,
          post["Date"].getStr,
          summary,
          ]
      seq_post.add p
      if "Tags" in post:
        for tag in post["Tags"].getStr.split(","):
          tags.inc tag

    for tag, count in tags:
      p = """
      <a class="label" href="/tags/$1.html">
      $1
      </a>
      """ % tag
      tag_cloud.add p

    var index_post = %* {
        "content": seq_post.join("\n"),
        "tags": tag_cloud,
      }
    var content = templates.renderTemplate("index.templ", index_post)
    
    writeFile("public/" & "index.html", content)

proc write_rss(posts: seq[JsonNode]) =
    var
      seq_post : seq[string]
      p, summary, post_dt: string
      dt: DateTime

    for key, post in posts:
      dt = parse(post["Date"].getStr, "yyyy-MM-dd HH:mm") - 8.hours
      post_dt = format(dt, "ddd, dd MMM yyyy HH:mm:ss \'GMT\'")
      if "Summary" in post:
        summary = post["Summary"].getStr
      else:
        summary = ""
      p = """
  <item>
    <title>$2</title>
    <link>$5/$1.html</link>
    <guid>$5/$1.html</guid>
    <pubDate>$3</pubDate>
  </item>
    """ % [
          post["Slug"].getStr,
          post["Title"].getStr,
          post_dt,
          summary,
          site_root,
          ]
      seq_post.add p

    var index_post = %* {
        "content": seq_post.join("\n"),
        "root": site_root,
      }
    var content = templates.renderTemplate("rss.templ", index_post)
    
    writeFile("public/" & "feed.xml", content)

proc write_atom(posts: seq[JsonNode]) =
    var
      seq_post : seq[string]
      p, summary, post_dt: string
      dt: DateTime

    for key, post in posts:
      dt = parse(post["Date"].getStr, "yyyy-MM-dd HH:mm")
      post_dt = format(dt, "yyyy-MM-dd\'T\'HH:mm:sszzz")
      if "Summary" in post:
        summary = post["Summary"].getStr
      else:
        summary = ""
      p = """
  <entry>
    <title>$2</title>
    <link href="$5/$1.html" rel="alternate"></link>
    <published>$3</published>
    <updated>$3</updated>
    <author><name>muxueqz</name></author>
    <id>tag:muxueqz.top,$6:/$1.html</id>
    <summary type="html">$4</summary>
    """ % [
          post["Slug"].getStr,
          post["Title"].getStr,
          post_dt,
          summary,
          site_root,
          format(dt, "yyyy-MM-dd"),
          ]
      seq_post.add p
      if "Tags" in post:
        for tag in post["Tags"].getStr.split(","):
          p = """
          <category term="$1"></category>
          """ % tag
          seq_post.add p
      seq_post.add "</entry>"

    dt = parse(posts[0]["Date"].getStr, "yyyy-MM-dd HH:mm")
    post_dt = format(dt, "yyyy-MM-dd\'T\'HH:mm:sszzz")
    var index_post = %* {
        "content": seq_post.join("\n"),
        "root": site_root,
        "updated": post_dt,
      }
    var content = templates.renderTemplate("atom.templ", index_post)
    
    writeFile("public/" & "all.atom.xml", content)

proc write_sitemap(posts: seq[JsonNode]) =
    var
      seq_post : seq[string]
      p, post_dt: string
      dt: DateTime

    for key, post in posts:
      dt = parse(post["Date"].getStr, "yyyy-MM-dd HH:mm")
      post_dt = format(dt, "yyyy-MM-dd\'T\'HH:mm:sszzz")
      p = """
<url>
  <loc>$3/$1.html</loc>
  <lastmod>$2</lastmod>
  <priority>1.00</priority>
</url>
    """ % [
          post["Slug"].getStr,
          post_dt,
          site_root,
          ]
      seq_post.add p

    var index_post = %* {
        "content": seq_post.join("\n"),
        "root": site_root,
      }
    var content = templates.renderTemplate("sitemap.templ", index_post)
    
    writeFile("public/" & "sitemap.xml", content)

proc write_tags(posts: seq[JsonNode]) =
    var
      post_tags = initTable[string, string]()
      p: string

    for _, post in posts:
      if "Tags" in post:
        p = """
          <h2>
            <a href="/$1.html"> $2 </a>
          </h2>
          <div id=date>
            <time>$3</time>
          </div>
          """ % [
            post["Slug"].getStr,
            post["Title"].getStr,
            post["Date"].getStr,
            ]
        for tag in post["Tags"].getStr.split(","):
          if tag in post_tags:
            post_tags[tag].add p
          else:
            post_tags[tag] = p

    for tag, post in post_tags:
      var index_post = %* {
          "content": post,
          "tag_name": tag,
        }
      var content = templates.renderTemplate("tags.templ", index_post)
      
      writeFile("public/tags/" & tag & ".html", content)


proc main()= 
  var
    posts = write_posts()
  posts = sort_posts(posts)
  # echo $posts
  write_index(posts)
  # TODO
  # write_archive(posts)
  write_tags(posts)
  write_rss(posts)
  write_atom(posts)
  write_sitemap(posts)


main()
