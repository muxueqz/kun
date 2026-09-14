# Kun
[![CI Pipeline](https://github.com/muxueqz/kun/actions/workflows/ci.yml/badge.svg)](https://github.com/muxueqz/kun/actions/workflows/ci.yml)

a small static site generator written in Nim.

## Usage

Install the dependency and build Kun:

```bash
nimble install -y
nimble build
```

The default command reads Markdown files from `srcs/`, renders templates from
`templates/`, and writes the generated site to `public/`:

```bash
./dist/kun
```

Directories and the site URL can be overridden from the command line:

```text
kun --source-dir srcs --template-dir templates --output-dir public \
    --site-root https://muxueqz.top
```

Use `--clean` to remove files recorded by the previous Kun generation while
preserving static assets in the output directory.

Kun者，鲲也，《庄子》云：鲲之大，不知其几千里也。然而“鲲”本指鱼苗，原是鱼中最小者，庄子却喻为至大。
