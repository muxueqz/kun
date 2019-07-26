import os, times, strutils, osproc, streams
# import moustachu
import tables
import pegs
import nwt, json
import markdown
import algorithm
import times

var templates = newNwt("templates/*.html") # we have all the templates in a folder called "templates"

proc write_post(post: JsonNode)=
    var content = templates.renderTemplate("post.html", post)
    
    writeFile("public/" & post["Slug"].getStr & ".html", content)

proc parse_source(file_path: string): JsonNode = 
  var
    file_meta = splitFile(file_path)
    head = true
    post = initTable[string, string]()
    matches: array[0..1, string]
    src = ""
  for line in file_path.open().lines:

    if head and line.match(peg"\s* {\w+} \s* ':' \s* {.+}", matches):
      post[matches[0]] = matches[1]
    else:
      head = false
    if head == false:
      src.add line & "\n"
  if post.contains"Slug":
    post["Slug"] = file_meta.name
  post["content"] = markdown(src)
  result = %* post

proc write_posts(): seq[JsonNode] = 
  for file in walkDirRec "./srcs/":
    if file.endsWith ".md":
      echo file
      var
        post = parse_source(file)
        # post['stem'] = source.stem
      write_post(post)
#
        # posts.append(post)
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
#
#
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
  # write_rss(posts)


main()
