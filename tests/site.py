#!/usr/bin/env python3
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []
        self.ids = set()
        self.images = []
        self.meta = {}
        self.canonical = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "img":
            self.images.append(attrs)
        if tag == "meta" and "content" in attrs:
            key = attrs.get("property", attrs.get("name"))
            if key:
                self.meta[key] = attrs["content"]
        if tag == "link" and attrs.get("rel") == "canonical":
            self.canonical = attrs.get("href")
        for key in ("href", "src"):
            if key in attrs:
                self.refs.append(attrs[key])


parser = Links()
parser.feed((ROOT / "index.html").read_text(encoding="utf-8"))
required_ids = {"main", "top", "modes", "features", "install", "support"}
assert required_ids <= parser.ids
assert parser.canonical == "https://rouboufy.github.io/Tuim/"
for key in ("description", "theme-color", "og:title", "og:description", "og:image", "twitter:card"):
    assert parser.meta.get(key), f"missing metadata: {key}"
for attrs in parser.images:
    assert "alt" in attrs, f"image missing alt text: {attrs.get('src')}"
    if attrs.get("src", "").endswith(".webp"):
        assert attrs.get("width") and attrs.get("height"), f"raster image missing dimensions: {attrs.get('src')}"
for ref in parser.refs:
    if ref.startswith("#"):
        assert ref[1:] in parser.ids, f"missing anchor: {ref}"
        continue
    parsed = urlparse(ref)
    if parsed.scheme or ref.startswith("//"):
        continue
    path = ROOT / parsed.path
    assert path.exists(), f"missing local site asset: {ref}"

html = (ROOT / "index.html").read_text(encoding="utf-8")
for phrase in ("Normal", "IDE", "Zen", "Installation", "Platform status", "limitations"):
    assert phrase.lower() in html.lower(), f"missing site content: {phrase}"
assert '<details class="download-menu" id="download-options">' in html
assert html.count('class="install-tag"') == 3
print("Static site validated")
