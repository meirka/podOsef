# PodOsef

PodOsef is an MP3-first, lightweight, simple, self-hosted podcast publishing system.

## What it does

- Extracts metadata (and embedded cover art) from MP3 files
- Generates a static HTML page and RSS feed from MP3 metadata + configuration
- Serves the MP3 files and the generated site/feed
- Optionally mirrors a remote podcast RSS feed by downloading episodes into your archive (useful for backup or secondary hosting)

## Source of truth

PodOsef is filesystem-first and database-free.

PodOsef generates the site and RSS directly from your files:

- Episode **metadata** comes from MP3 ID3 tags (missing tags will show up as missing fields in HTML/RSS).
- Episode **order** is taken from the **first number in the filename** (so name files with numbers).
- Episode **publish time** is based on the file **modify date**.

There is no database to populate or maintain. To publish, add tags to your MP3, configure PodOsef, and place the MP3 into the media folder—everything is generated from configuration + your MP3 files.

> Note: extracted metadata is stored as generated JSON. If you update MP3 tags for an existing episode, delete its JSON file in `data/publisher/data/generated/episodes/` to force re-extraction.

## Containerized

The system is containerized and can be launched with a simple Docker Compose setup:

```yaml
services:
  publisher:
    image: ghcr.io/meirka/podosef-publisher:v26.2.14.1
    volumes:
      - ./data/publisher:/work/publisher/hugo
      - ./data/media:/srv/media
      - ./data/site:/srv/www

  # Downloader is optional if you want an archive/backup of a remote podcast feed
  downloader:
    image: ghcr.io/meirka/podosef-downloader:v26.2.14.1
    environment:
      MAIN_CDN_SERVER: "https://feed.rcmp.cloud"  # Remote feed URL
      CHECK_CDN_TIME: "3600"
    volumes:
      - ./data/media:/srv/media

  nginx:
    image: ghcr.io/meirka/podosef-nginx:v26.2.14.1
    ports:
      - "80:80"
    volumes:
      - ./data/site:/usr/share/nginx/html
      - ./data/media:/srv/media
```

On the default launch, PodOsef creates the required default files and folders in the mounted volumes.

## Structure & Configuration

On first start, the default structure will appear (unless you pre-create it).
Main configuration is done via docker-compose.yml and hugo.yaml.

Default HTML: `http://localhost`
Default RSS: `http://localhost/feed`

- `docker-compose.yml` - specifies volume mounts and downloader feed URL
- `hugo.yaml` - specifies feed/site information, base URL, and header links in HTML

Covers:
- Replace `rss_cover.jpg` to set your podcast cover for the feed/templates
- Optionally replace `default_cover.jpg` (used when an episode has no embedded cover art)

Static RSS and HTML generation is done by [Hugo](https://gohugo.io/). If you wish to modify templates, edit files in `layouts`. A [Bootstrap](https://getbootstrap.com/) CSS file is included under `static/css/` and can be replaced as you see fit.

Mp3 files are placed under `data/media/episodes`, where they will be pickup by a script and metadata will be extracted by [ExifTool](https://exiftool.org/) into `data/publisher/data/generated/episodes`. 

MP3 filenames must include a number to define ordering, for example: `1st myPodcast.mp3`, `2 myPodcast.mp3`, `10th podcast.mp3`.


```text
.
|-- docker-compose.yml
`-- data/
    |-- media/
    |   |-- covers/
    |   |   |-- default_cover.jpg
    |   |   |-- rss_cover.jpg
    |   |   `-- <episode-cover>.png
    |   `-- episodes/
    |       `-- <episode-audio>.mp3
    |-- publisher/
    |   |-- hugo.yaml
    |   |-- data/
    |   |   `-- generated/
    |   |       `-- episodes/
    |   |           `-- <episode>.json
    |   |-- layouts/
    |   |   |-- index.html
    |   |   |-- home.rss.xml
    |   |   `-- partials/
    |   |       `-- episodes-data.html
    |   `-- static/
    |       `-- css/
    |           `-- bootstrap.5.3.8.min.css
    `-- site/
        |-- index.html
        |-- index.xml
        |-- sitemap.xml
        |-- categories/
        |   `-- index.xml
        |-- tags/
        |   `-- index.xml
        `-- css/
            `-- bootstrap.5.3.8.min.css
```

