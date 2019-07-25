import os, times, strutils, osproc, streams
# import moustachu
import tables
import pegs
import nwt, json
import markdown

var templates = newNwt("templates/*.html") # we have all the templates in a folder called "templates"

proc write_post(post: JsonNode)=
    # if post.get('legacy_url'):
        # path = pathlib.Path("./docs/{}/index.html".format(post['stem']))
        # path.parent.mkdir(parents=True, exist_ok=True)
    # else:
        # path = pathlib.Path("./docs/{}.html".format(post['stem']))
    var content = templates.renderTemplate("post.html", post)
    
    writeFile("public/" & post["Slug"].getStr & ".html", content)

proc parse_source(file_path: string): JsonNode = 
  var
    file_meta = splitFile(file_path)
    head = true
    post = initTable[string, string]()
    matches: array[0..1, string]
    src = ""
  # post.slug = file_meta.name
  for line in file_path.open().lines:

    if head and line.match(peg"\s* {\w+} \s* ':' \s* {.+}", matches):
      post[matches[0]] = matches[1]
    else:
      head = false
    if head == false:
      src.add line & "\n"
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

# def write_index(posts: Sequence[frontmatter.Post]):
    # posts = sorted(posts, key=lambda post: post['date'], reverse=True)
    # path = pathlib.Path("./docs/index.html")
    # template = jinja_env.get_template('index.html')
    # rendered = template.render(posts=posts)
    # path.write_text(rendered)
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
    # write_index(posts)
    # write_rss(posts)


main()
