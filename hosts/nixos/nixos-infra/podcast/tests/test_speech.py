"""Speech cleanup on three real saved pages (sources in fixtures/README.md).

Run from the podcast directory: uv run pytest
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import speech

FIXTURES = Path(__file__).parent / "fixtures"

PAGES = {
    "go-blog-sweet-16": "https://go.dev/blog/16years",
    "uv-docs-projects": "https://docs.astral.sh/uv/guides/projects/",
    "nasa-x70": "https://www.nasa.gov/news-release/nasa-announces-x-70-experimental-aircraft-to-advance-flight-research/",
}

# Lines from the uv page's code blocks. None of them may be spoken.
UV_CODE = [
    "uv init hello-world",
    "mkdir hello-world",
    "├──",
    'name = "hello-world"',
    "uv add requests",
    "requests==2.31.0",
    "uv lock --upgrade-package requests",
    "flask run -p 3000",
    "import flask",
    "source .venv/bin/activate",
    "hello_world-0.1.0-py3-none-any.whl",
]


def spoken(name: str) -> str:
    html = (FIXTURES / f"{name}.html").read_text(encoding="utf-8")
    article = speech.extract_html(html, PAGES[name])
    return "\n".join(text for text, _ in speech.to_pieces(article))


@pytest.mark.parametrize("name", PAGES)
def test_no_urls_brackets_or_code(name: str) -> None:
    text = spoken(name)
    assert "http" not in text
    assert "[" not in text
    for marker in ("`", "{", "}", "$ ", "├──", "def ", "import "):
        assert marker not in text, marker


def test_blog_post_keeps_link_text_and_drops_furniture() -> None:
    text = spoken("go-blog-sweet-16")
    assert text.startswith("Go’s Sweet 16. By Austin Clements, from Golang.")
    # Anchor text survives, with the space trafilatura would have trimmed.
    assert "the official Go SDK for the Model Context Protocol" in text
    assert "pitfalls of writing Go benchmarks" in text
    # The context.Context link that trafilatura used to move elsewhere.
    assert "in tests that use Context, and that make it easy to write" in text
    assert "The Go Blog" not in text  # nav crumb
    assert "Next article" not in text
    assert "Blog Index" not in text


def test_docs_page_replaces_code_with_a_note() -> None:
    text = spoken("uv-docs-projects")
    for line in UV_CODE:
        assert line not in text, line
    assert "using the uv init command:\nCode sample omitted." in text
    assert "Code sample omitted.\nCode sample omitted." not in text
    # Inline code is read as words.
    assert "define their dependencies in a pyproject dot toml file." in text
    assert "that is, uv run, uv sync, or uv lock" in text


def test_news_article_stops_at_the_end_mark() -> None:
    text = spoken("nasa-x70")
    assert text.startswith(
        "NASA Announces X-70 Experimental Aircraft to Advance Flight Research. By Cheryl Warner."
    )
    assert "cruise at Mach point 7 5," in text
    assert "visit" not in text  # its URL is gone, so the sentence goes too
    assert "-end-" not in text
    assert "202-358-1600" not in text  # media contact block


def test_pasted_markdown() -> None:
    article = speech.from_text(
        "# Notes on flaps\n\n"
        "Read [the docs](https://example.com/docs) first[^1], see https://example.com.\n\n"
        "![diagram](https://example.com/a.png)\n\n"
        "```python\nflaps = 15\n```\n\n"
        "- set `flaps_15` before v1.2.3\n",
        "",
    )
    text = "\n".join(t for t, _ in speech.to_pieces(article))
    assert text == (
        "Notes on flaps.\n"
        "Read the docs first, see.\n"
        "Code sample omitted.\n"
        "set flaps 15 before version 1.2.3."
    )


def test_short_page_is_rejected() -> None:
    with pytest.raises(speech.ExtractionError, match="words extracted"):
        speech.extract_html(
            "<html><body><article><h1>Subscribe to read</h1>"
            "<p>This story is for subscribers only. Log in to keep reading.</p>"
            "</article></body></html>"
        )


def test_long_paragraph_splits_at_sentences() -> None:
    sentence = "This sentence is exactly fifty characters long ok. "
    pieces = speech._split((sentence * 60).strip(), limit=500)
    assert all(len(p) <= 500 for p in pieces)
    assert all(p.endswith("ok.") for p in pieces)
    assert " ".join(pieces) == (sentence * 60).strip()


def test_furniture_labels_go_but_sentences_that_start_alike_stay() -> None:
    article = speech.from_text(
        "Share this\n\nShare prices fell sharply on Monday.\n\nComments (12)\n\n"
        "Subscribe to our newsletter\n\nNext article: Flaps",
        "Markets",
    )
    text = "\n".join(t for t, _ in speech.to_pieces(article))
    assert "Share prices fell sharply on Monday." in text
    for furniture in ("Share this", "Comments", "Subscribe", "Next article"):
        assert furniture not in text


def test_shared_link_with_a_headline_is_queued_as_the_link() -> None:
    # What a news app's Share Sheet hands the Shortcut: headline, then link.
    shared = "The incoming class of U.S. senators is full of historic firsts https://n.pr/4oQx1"
    assert speech.link_capture(shared) == "https://n.pr/4oQx1"
    assert speech.link_capture("https://go.dev/blog/16years") == "https://go.dev/blog/16years"
    assert speech.link_capture("https://en.wikipedia.org/wiki/Oliver!") == (
        "https://en.wikipedia.org/wiki/Oliver!"  # a bare URL is taken as is
    )
    assert speech.link_capture("word " * 41 + "https://example.com") is None
    assert speech.link_capture("no link here") is None
    assert (
        speech.link_capture("Read this: https://example.com/story.") == "https://example.com/story"
    )


def test_shared_url_followed_by_page_text_is_queued_as_the_link() -> None:
    # The observed Shortcut payload began with the URL, then page text.
    url = "https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra"
    shared = url + "\nAll posts\nRecent\n" + ("Page navigation and article text. " * 45)
    assert speech.link_capture(shared) == url


def test_pasted_text_without_a_title_is_titled_from_its_first_line() -> None:
    article = speech.from_text("Why flaps matter\n\nFlaps change the camber of the wing.", "")
    assert article.title == "Why flaps matter"
    assert [b.text for b in article.blocks] == ["Flaps change the camber of the wing."]
    long_first = speech.from_text("Flaps change the camber of the wing and lower the stall speed.")
    assert long_first.title == "Flaps change the camber of the wing and…"
    short = speech.from_text("Flaps lower the stall speed.")  # all of it is read, not just titled
    assert (short.title, short.words) == ("Flaps lower the stall speed.", 5)
    code_only = speech.from_text("Run this command:\n\n```\necho hi\n```")  # still has words
    assert code_only.words == 3
