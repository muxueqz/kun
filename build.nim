import os, times, strutils, osproc, streams
import tables
import sequtils
import pegs
import nwt, json
import markdown
import algorithm
import times

var templates = newNwt("templates/*.*ml") # we have all the templates in a folder called "templates"

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
        <a href="/tags/$1.html">
        $1
        </a>
        """ % tag.strip()
        new_post["tag_links"].add p
    var json_post = %* new_post
    var content = templates.renderTemplate("post.html", json_post)
    
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
    <a href="/$1.html">
      <dt>$2</dt>
      <dd>
        <time>$3</time>
      </dd>
    </a>
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
          tags.inc tag.strip()

    for tag, count in tags:
      p = """
      <a href="/tags/$1.html">
      $1
      </a>
      """ % tag
      tag_cloud.add p
    seq_post.add tag_cloud

    var index_post = %* {
        "content": seq_post.join("\n")
      }
    var content = templates.renderTemplate("index.html", index_post)
    
    writeFile("public/" & "index.html", content)

proc write_rss(posts: seq[JsonNode]) =
    var
      seq_post : seq[string]
      p, summary, tag_cloud: string
      site_root = "https://muxueqz.coding.me"

    for key, post in posts:
      if "Summary" in post:
        summary = post["Summary"].getStr
      else:
        summary = ""
    # <pubDate>{{ post.date.strftime("%a, %d %b %Y 12:00:00 Z") }}</pubDate>
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
          post["Date"].getStr,
          summary,
          site_root,
          ]
      seq_post.add p

    var index_post = %* {
        "content": seq_post.join("\n"),
        "root": site_root,
      }
    var content = templates.renderTemplate("rss.xml", index_post)
    
    writeFile("public/" & "feed.xml", content)

proc write_tags(posts: seq[JsonNode]) =
    var
      post_tags = initTable[string, string]()
      p: string
      tag: string

    for _, post in posts:
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
      var content = templates.renderTemplate("tags.html", index_post)
      
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


main()
