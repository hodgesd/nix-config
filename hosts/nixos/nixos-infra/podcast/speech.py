"""Turn an article into text that sounds like a person reading it aloud.

Deterministic, no LLM. Two entry points build the same Article:

- extract_html() for a fetched page: trafilatura finds the article, then
  its XML output (which keeps headings, links and inline code as
  structure) is walked block by block.
- from_text() for pasted text, plain or markdown.

to_pieces() then returns what to send to Kokoro, intro first, each piece
paired with the pause that follows it. Every spoken string passes through
speakable(), which is also where the Kokoro-specific fixes live.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Literal

import trafilatura

CODE_NOTE = "Code sample omitted."
# Below this the page is a paywall stub, a login wall or not an article.
MIN_WORDS = 200
# Characters per Kokoro request. Kokoro-FastAPI re-chunks internally to
# its 510-token model window, so this only bounds one HTTP request. A
# paragraph per request keeps pauses ours and a failure local.
MAX_PIECE_CHARS = 1200
PARAGRAPH_PAUSE = 0.6  # seconds of silence after a paragraph
HEADING_PAUSE = 1.0  # after a heading (and before, via the paragraph pause)

# Replaces every <pre> before trafilatura sees the page. trafilatura drops
# most highlighted code blocks outright, which would leave "run this
# command:" followed by nothing; the marker survives as its own paragraph
# and becomes CODE_NOTE.
_CODE_MARKER = "PODCASTCODEBLOCKMARKER"
_PRE_RE = re.compile(r"<pre\b.*?</pre\s*>", re.S | re.I)
_FIGCAPTION_RE = re.compile(r"<figcaption\b.*?</figcaption\s*>", re.S | re.I)
# Inline <code> is read as plain words, and trafilatura reorders text when
# a link wraps one (go.dev: "<a><code>Context</code></a>, and that" came
# out as ", and that" with Context moved to the next block). Unwrap it.
_INLINE_CODE_RE = re.compile(r"</?code\b[^>]*>", re.I)
# trafilatura trims the whitespace after an inline element ("pitfalls</a>
# of" became "pitfallsof"). A rare printable character holds the space
# through extraction; _SPACE_HOLD goes back to " " afterwards.
_SPACE_HOLD = "\u2042"  # ⁂; trafilatura deletes unprintable placeholders
_INLINE_TAGS = r"(?:a|em|strong|b|i|span|abbr)"
_SPACE_AFTER_RE = re.compile(rf"(</{_INLINE_TAGS}\s*>)\s+", re.I)
_SPACE_BEFORE_RE = re.compile(rf"\s+(<{_INLINE_TAGS}\b)", re.I)

# Sections dropped from their heading to the next heading.
_SKIP_SECTIONS = {
    "references",
    "footnotes",
    "notes",
    "sources",
    "citations",
    "further reading",
    "see also",
    "contents",
    "table of contents",
    "on this page",
    "in this article",
}
# Short paragraphs that are site furniture rather than article. The labels
# only count without a closing full stop: "Share this" is furniture,
# "Share prices fell sharply on Monday." is the article.
_BOILERPLATE_RE = re.compile(
    r"^(share( this)?|subscribe|sign up|follow us|related( articles| posts)?"
    r"|read more|advertisement|comments?|blog index|back to top)\b(?!.*[.?!]$)"
    r"|\b(next|previous) (article|post):",
    re.I,
)
# Press-release end marks ("-end-" on NASA, "###" by US convention):
# what follows is the media contact block.
_END_MARKS = {"-end-", "- end -", "###"}

Kind = Literal["heading", "para"]


@dataclass(frozen=True)
class Block:
    kind: Kind
    text: str


@dataclass
class Article:
    title: str
    author: str = ""
    site: str = ""
    url: str = ""
    blocks: list[Block] = field(default_factory=list)

    @property
    def words(self) -> int:
        return sum(
            len(b.text.split()) for b in self.blocks if b.kind == "para" and b.text != CODE_NOTE
        )


class ExtractionError(ValueError):
    """The input did not yield an article worth reading; the message says why."""


# ── Extraction ──────────────────────────────────────────────────────────


def extract_html(html: str, url: str = "") -> Article:
    """Article from a fetched page. Raises ExtractionError on junk."""
    html = _FIGCAPTION_RE.sub("", html)
    html = _PRE_RE.sub(f"<p>{_CODE_MARKER}</p>", html)
    html = _INLINE_CODE_RE.sub("", html)
    html = _SPACE_AFTER_RE.sub(rf"\1{_SPACE_HOLD}", html)
    html = _SPACE_BEFORE_RE.sub(rf"{_SPACE_HOLD}\1", html)
    xml = trafilatura.extract(
        html,
        url=url or None,
        output_format="xml",
        with_metadata=True,
        include_links=True,  # kept so link-only nav can be recognised
        include_formatting=True,
        include_images=False,
        include_tables=False,
        include_comments=False,
    )
    if not xml:
        raise ExtractionError("no article text found on the page")
    doc = ET.fromstring(xml.replace(_SPACE_HOLD, " "))
    site = (doc.get("sitename") or doc.get("hostname") or "").strip()
    title = _clean_title(doc.get("title") or "", site)
    main = doc.find("main")
    blocks = _xml_blocks(main, title) if main is not None else []
    article = Article(
        title=title or "Untitled article",
        author=_clean_author(doc.get("author") or ""),
        site=site,
        url=url,
        blocks=blocks,
    )
    if article.words < MIN_WORDS:
        raise ExtractionError(
            f"only {article.words} words extracted (paywall, login wall or not an article)"
        )
    return article


# A share with a URL and at most this many other words is a link, not text
# to read: news apps share "Headline https://…". Same rule and number as the
# mini's #listen watcher (hosts/darwin/mini/podcast-listen/watch.py).
_SHARED_URL_RE = re.compile(r"https?://[^\s)>\]]+")
LINK_CAPTURE_WORDS = 40
# A first paragraph this short, on its own, is the pasted text's headline.
TITLE_WORDS = 12


def link_capture(text: str) -> str | None:
    """The URL to fetch when shared text is really a link, else None."""
    urls = _SHARED_URL_RE.findall(text)
    if urls and len(_SHARED_URL_RE.sub("", text).split()) <= LINK_CAPTURE_WORDS:
        if urls[0] == text.strip():
            return urls[0]  # a bare URL is taken as is ("…/wiki/Oliver!")
        return urls[0].rstrip(".,;:!?")  # "…firsts https://n.pr/x." ends a sentence
    return None


def from_text(text: str, title: str = "") -> Article:
    """Article from pasted text (plain or markdown)."""
    blocks: list[Block] = []
    in_fence = False
    para: list[str] = []

    def flush() -> None:
        if para:
            blocks.append(Block("para", " ".join(para)))
            para.clear()

    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith(("```", "~~~")):
            flush()
            if not in_fence:
                blocks.append(Block("para", CODE_NOTE))
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if not line:
            flush()
            continue
        if m := re.match(r"#{1,6}\s+(.*)", line):
            flush()
            blocks.append(Block("heading", m.group(1)))
            continue
        if m := re.match(r"(?:[-*+]|\d+[.)])\s+(.*)", line):
            flush()  # each list item reads as its own sentence
            blocks.append(Block("para", m.group(1)))
            continue
        para.append(line)
    flush()

    if not title and blocks and blocks[0].kind == "heading":
        title = blocks.pop(0).text
    # No title given (the Share Sheet Shortcut never asks): a short first
    # paragraph is the headline; otherwise the opening words name it.
    readable_after = any(b.kind == "para" and b.text != CODE_NOTE for b in blocks[1:])
    if not title and readable_after and len(blocks[0].text.split()) <= TITLE_WORDS:
        title = blocks.pop(0).text
    elif not title and blocks:
        words = blocks[0].text.split()
        title = " ".join(words[:8]) + ("…" if len(words) > 8 else "")
    article = Article(title=title.strip() or "Untitled note", blocks=_tidy(blocks, title))
    if article.words == 0:
        raise ExtractionError("the pasted text is empty")
    return article


def _clean_title(title: str, site: str) -> str:
    title = " ".join(title.split())
    if site:
        # "NASA Announces X-70 … - NASA" → drop the site suffix.
        for sep in (" - ", " | ", " — ", " – "):
            if title.lower().endswith(f"{sep}{site}".lower()):
                return title[: -len(sep) - len(site)].strip()
    return title


def _clean_author(author: str) -> str:
    # trafilatura joins bylines with ";" ("Austin Clements; For The Go
    # Team"). The first name is the byline; the rest reads as noise.
    return author.split(";")[0].strip()


def _inline(el: ET.Element) -> str:
    """Spoken text of an element: link and code text kept, markup dropped."""
    parts = [el.text or ""]
    for child in el:
        if child.tag == "lb":
            parts.append(" ")
        elif child.tag == "graphic":
            pass
        elif (
            child.tag == "hi"
            and "sup" in (child.get("rend") or "")
            and re.fullmatch(r"\s*\[?\d+\]?\s*", _inline(child))
        ):
            pass  # footnote marker
        else:
            parts.append(_inline(child))
        parts.append(child.tail or "")
    return "".join(parts)


def _link_only(el: ET.Element) -> bool:
    """True when every word of the element sits inside a link (nav, related links)."""
    linked = " ".join(_inline(r) for r in el.iter("ref"))
    return bool(linked.split()) and linked.split() == _inline(el).split()


def _xml_blocks(main: ET.Element, title: str) -> list[Block]:
    blocks: list[Block] = []
    skipping = False
    if main.text and main.text.strip():
        blocks.append(Block("para", main.text))
    for el in main:
        tail = el.tail or ""
        if el.tag == "head":
            text = _inline(el)
            refs = list(el.iter("ref"))
            # A heading that is just a link to another page is a crumb
            # ("The Go Blog"); same-page anchors (#section) are real headings.
            crumb = _link_only(el) and all("#" not in (r.get("target") or "") for r in refs)
            skipping = _norm(text) in _SKIP_SECTIONS
            if not crumb and not skipping and _norm(text) != _norm(title):
                blocks.append(Block("heading", text))
            if tail.strip():
                blocks.append(Block("para", tail))
            continue
        if skipping:
            continue
        if el.tag == "list":
            items = list(el.iter("item"))
            if items and all(_link_only(i) for i in items):
                continue  # table of contents or a related-links list
            blocks.extend(Block("para", _inline(i)) for i in items)
        elif el.tag in ("code", "hi", "ref"):
            # Inline element loose in <main>: part of a broken-up paragraph.
            blocks.append(Block("para", _inline(el) + tail))
            continue
        elif el.tag in ("p", "quote"):
            text = _inline(el)
            if text.strip() in _END_MARKS:
                break
            if text.strip() == _CODE_MARKER:
                blocks.append(Block("para", CODE_NOTE))
            elif not (_link_only(el) and len(text.split()) <= 12):
                blocks.append(Block("para", text))
        if tail.strip():
            blocks.append(Block("para", tail))
    return _tidy(blocks, title)


def _tidy(blocks: list[Block], title: str) -> list[Block]:
    """Clean every block, drop furniture, rejoin split sentences."""
    out: list[Block] = []
    for b in blocks:
        text = speakable(b.text)
        if not text:
            continue
        if b.kind == "para":
            if _BOILERPLATE_RE.search(text) and (len(text.split()) <= 15 or ":" in text[:20]):
                continue
            if re.search(r"\bvisit:?$", text):
                continue  # "For more information, visit:" whose URL was dropped
            if text == CODE_NOTE and out and out[-1].text == CODE_NOTE:
                continue  # one note per run of code (line-number gutters, tabs)
            if out and out[-1].kind == "heading" and _norm(text) == _norm(out[-1].text):
                continue  # docs tab labels repeat the heading
            # trafilatura splits some paragraphs mid-sentence; a fragment
            # that starts lowercase belongs to the one before it. One-word
            # paragraphs are admonition labels ("Note"), not fragments.
            if (
                out
                and out[-1].kind == "para"
                and out[-1].text != CODE_NOTE
                and len(out[-1].text.split()) > 1
                and (text[0].islower() or text[0] in ",;:)")
                and not out[-1].text.endswith((".", "!", "?"))
            ):
                out[-1] = Block("para", f"{out[-1].text} {text}")
                continue
        out.append(Block(b.kind, text))
    # Every paragraph ends in punctuation so Kokoro lands it as a sentence.
    return [
        Block(b.kind, b.text + "." if b.kind == "para" and b.text[-1].isalnum() else b.text)
        for b in out
        if not (b.kind == "heading" and _norm(b.text) == _norm(title))
    ]


def _norm(text: str) -> str:
    return " ".join(re.sub(r"[^\w\s]", "", text.lower()).split())


# ── Speech cleanup ──────────────────────────────────────────────────────

_MD_IMAGE_RE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
_MD_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]*\)")
_FOOTNOTE_RE = re.compile(r"\[\^?\d+\]|\[citation needed\]", re.I)
_URL_RE = re.compile(r"(?:\bhttps?://|\bwww\.|\bmailto:)\S+", re.I)


def speakable(text: str) -> str:
    """One block of text, ready for Kokoro. Pure function, used by both paths."""
    text = text.replace(_CODE_MARKER, CODE_NOTE)
    text = _MD_IMAGE_RE.sub("", text)
    text = _MD_LINK_RE.sub(r"\1", text)  # [the docs](https://…) → the docs
    text = _FOOTNOTE_RE.sub("", text)
    text = _URL_RE.sub("", text)
    text = re.sub(r"[`*]+", "", text)  # inline code ticks, markdown emphasis
    text = re.sub(r"(?<!\w)_+|_+(?!\w)", "", text)  # __init__ → init
    text = re.sub(r"_+", " ", text)  # snake_case reads as words
    text = text.replace("[", "").replace("]", "")  # [tool.uv] → tool.uv
    text = _kokoro_fixes(text)
    text = " ".join(text.split())
    text = re.sub(r"\s+([,.;:!?])(?=\s|$)", r"\1", text)  # "visit :" left by a dropped URL
    text = re.sub(r"\(\s*\)", "", text).strip()
    return "" if re.fullmatch(r"[\W_]*", text) else text


# What Kokoro-FastAPI v0.9.2's own normalizer still gets wrong in the
# test articles, checked by running it on them (2026-11-06). Its number,
# unit, percent and acronym handling is good; these are the misses.
_FIXES: list[tuple[re.Pattern[str], str | Callable[[re.Match[str]], str]]] = [
    # "i.e." became "eye-ee"; a reader says what it means.
    (re.compile(r"\bi\.e\.,?", re.I), "that is,"),
    (re.compile(r"\be\.g\.,?", re.I), "for example,"),
    # "Mach .75" became "Mach zero point seven five"; pilots say "point
    # seven five". Digits are spaced so they are read one by one.
    (re.compile(r"(?<![\w.])\.(\d+)\b"), lambda m: "point " + " ".join(m.group(1))),
    # "v0.17.0" became "vzero point seventeen point zero".
    (re.compile(r"\bv(?=\d+\.\d)"), "version "),
    # "FIPS 140-3" became "one hundred and forty to three", a range.
    (re.compile(r"\b([A-Z]{2,}) (\d+)-(\d+)\b"), r"\1 \2 dash \3"),
    # "--upgrade-package" became an em-dash pause before the word.
    (re.compile(r"(?<!\w)--(?=\w)"), ""),
    # ".venv" kept a spoken-as-nothing dot; ".python-version" lost it.
    (re.compile(r"(?<![\w.])\.([A-Za-z][\w-]*)"), r"dot \1"),
    # "pyproject.toml", "uv.lock", "os.Root" mashed into one word. Two
    # letters minimum each side keeps "U.S." and "Ph.D." intact.
    (re.compile(r"\b(\w{2,})\.(?=[A-Za-z]{2,})"), r"\1 dot "),
    # What is left of "http" after URLs are gone is a name ("net/http").
    # Kokoro spells it either way; upper case says so to the next reader.
    (re.compile(r"\bhttps?\b"), lambda m: m.group(0).upper()),
    # "VS Code" became "vees code".
    (re.compile(r"\bVS Code\b"), "V S Code"),
]


def _kokoro_fixes(text: str) -> str:
    for pattern, replacement in _FIXES:
        text = pattern.sub(replacement, text)
    return text


# ── Synthesis plan ──────────────────────────────────────────────────────


def intro(article: Article) -> str:
    """'Title. By Author, from Site.' with whatever parts are known."""
    by = []
    if article.author:
        by.append(f"By {article.author}")
    if article.site and _norm(article.site) not in _norm(article.title):
        by.append(f"from {article.site}")
    line = speakable(article.title).rstrip(".") + "."
    if by:
        byline = ", ".join(by)
        line += f" {byline[0].upper()}{byline[1:]}."
    return line


def to_pieces(article: Article) -> list[tuple[str, float]]:
    """(text, pause after it in seconds) for each Kokoro request, in order."""
    pieces: list[tuple[str, float]] = [(intro(article), HEADING_PAUSE)]
    for b in article.blocks:
        if b.kind == "heading":
            pieces.append((b.text.rstrip(".:") + ".", HEADING_PAUSE))
        else:
            pieces.extend((chunk, 0.0) for chunk in _split(b.text))
            pieces[-1] = (pieces[-1][0], PARAGRAPH_PAUSE)
    return pieces


_SENTENCE_END_RE = re.compile(r"(?:(?<=[.!?])|(?<=[.!?][\"”’)]))\s+(?=[\"“(]?[A-Z0-9])")


def _split(text: str, limit: int = MAX_PIECE_CHARS) -> list[str]:
    """Split a paragraph at sentence boundaries into pieces of <= limit chars."""
    if len(text) <= limit:
        return [text]
    pieces: list[str] = []
    current = ""
    for sentence in _SENTENCE_END_RE.split(text):
        while len(sentence) > limit:  # one runaway sentence: break at a space
            cut = sentence.rfind(" ", 0, limit)
            cut = cut if cut > 0 else limit
            pieces.append(sentence[:cut])
            sentence = sentence[cut:].strip()
        if current and len(current) + 1 + len(sentence) > limit:
            pieces.append(current)
            current = sentence
        else:
            current = f"{current} {sentence}".strip()
    if current:
        pieces.append(current)
    return pieces
