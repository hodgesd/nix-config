"""The ready ping names only the published feed and never fails an episode."""

from __future__ import annotations

import importlib
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from types import ModuleType

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def test_ready_ping_asks_overcast_to_refresh_the_feed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("PODCAST_PUBLIC_BASE", "https://podcast.example")
    monkeypatch.setenv("PODCAST_INTAKE_TOKEN", "test-intake")
    monkeypatch.setenv("PODCAST_FEED_TOKEN", "test-feed")
    server = importlib.import_module("server")
    sent: list[tuple[str, bytes, int]] = []

    class Response:
        def __enter__(self) -> Response:
            return self

        def __exit__(self, *_args: object) -> None:
            pass

    def urlopen(request: urllib.request.Request, timeout: int) -> Response:
        sent.append((request.full_url, request.data, timeout))
        return Response()

    monkeypatch.setattr(server.urllib.request, "urlopen", urlopen)
    server.ping_overcast()
    assert [(url, timeout) for url, _, timeout in sent] == [("https://overcast.fm/ping", 5)]
    assert urllib.parse.parse_qs(sent[0][1].decode()) == {
        "urlprefix": ["https://podcast.example/p/test-feed/feed.xml"]
    }

    def offline(request: urllib.request.Request, timeout: int) -> Response:
        raise OSError("network unavailable")

    monkeypatch.setattr(server.urllib.request, "urlopen", offline)
    server.ping_overcast()  # logged, not raised


ARTICLE = "https://www.nytimes.com/2026/11/13/technology/briefing.html"
SNAPSHOT = f"https://archive.ph/newest/{ARTICLE}"
TEASER_HEAD = (
    '<script type="application/ld+json">{"isAccessibleForFree":false,"wordCount":1115}</script>'
)


def page(words: int, title: str = "Briefing", head: str = "") -> str:
    para = "<p>" + " ".join(["The crew briefed the approach before descent."] * 5) + "</p>"
    return (
        f"<html><head><title>{title}</title>{head}</head><body><article><h1>{title}</h1>"
        + para * (words // 35)
        + "</article></body></html>"
    )


@pytest.fixture
def server(monkeypatch: pytest.MonkeyPatch) -> ModuleType:
    monkeypatch.setenv("PODCAST_PUBLIC_BASE", "https://podcast.example")
    monkeypatch.setenv("PODCAST_INTAKE_TOKEN", "test-intake")
    monkeypatch.setenv("PODCAST_FEED_TOKEN", "test-feed")
    return importlib.import_module("server")


def serve(
    monkeypatch: pytest.MonkeyPatch, server: ModuleType, pages: dict[str, object]
) -> list[str]:
    """Stub fetch with `pages` (url → HTML, or an exception to raise); returns the URLs asked."""
    asked: list[str] = []

    def fetch(url: str, context: object = None, timeout: float = 30) -> str:
        asked.append(url)
        if url == SNAPSHOT:
            assert context is server.TLS12  # archive.today hangs on TLS 1.3
            assert timeout == server.ARCHIVE_TIMEOUT
        result = pages[url]
        if isinstance(result, Exception):
            raise result
        return str(result)

    monkeypatch.setattr(server, "fetch", fetch)
    return asked


def test_free_article_never_asks_the_archive(
    monkeypatch: pytest.MonkeyPatch, server: ModuleType
) -> None:
    asked = serve(monkeypatch, server, {ARTICLE: page(700)})
    assert server.read_url(ARTICLE).words == 700
    assert asked == [ARTICLE]


def test_teaser_is_read_from_the_snapshot_under_the_original_byline(
    monkeypatch: pytest.MonkeyPatch, server: ModuleType
) -> None:
    serve(
        monkeypatch,
        server,
        {
            ARTICLE: page(350, head=TEASER_HEAD + '<meta name="author" content="Cory Weinberg">'),
            SNAPSHOT: page(1120, title="Briefing - The New York Times"),
        },
    )
    article = server.read_url(ARTICLE)
    assert article.words == 1120
    assert (article.title, article.author) == ("Briefing", "Cory Weinberg")


def test_paywall_without_a_snapshot_fails_before_any_speech(
    monkeypatch: pytest.MonkeyPatch, server: ModuleType
) -> None:
    serve(
        monkeypatch,
        server,
        {ARTICLE: page(350, head=TEASER_HEAD), SNAPSHOT: server.HTTPStatus(404, "Not Found")},
    )
    with pytest.raises(server.speech.ExtractionError) as caught:
        server.read_url(ARTICLE)
    assert str(caught.value) == (
        "paywalled: 350 of its 1115 words are free; archive.today has no snapshot"
    )


def test_hard_paywall_status_tries_the_snapshot_but_other_errors_do_not(
    monkeypatch: pytest.MonkeyPatch, server: ModuleType
) -> None:
    serve(
        monkeypatch,
        server,
        {ARTICLE: server.HTTPStatus(403, "Forbidden"), SNAPSHOT: page(700)},
    )
    assert server.read_url(ARTICLE).site == "nytimes.com"  # not archive.ph
    asked = serve(monkeypatch, server, {ARTICLE: server.HTTPStatus(500, "Server Error")})
    with pytest.raises(server.HTTPStatus):
        server.read_url(ARTICLE)
    assert asked == [ARTICLE]


def test_failed_job_alerts_ntfy_with_the_reason(
    monkeypatch: pytest.MonkeyPatch, server: ModuleType
) -> None:

    monkeypatch.setattr(server, "NTFY_URL", "https://ntfy.example")
    monkeypatch.setattr(server, "NTFY_TOPIC", "podcast")
    sent: list[urllib.request.Request] = []

    class Response:
        def __enter__(self) -> Response:
            return self

        def __exit__(self, *_args: object) -> None:
            pass

    def urlopen(request: urllib.request.Request, timeout: int) -> Response:
        sent.append(request)
        return Response()

    monkeypatch.setattr(server.urllib.request, "urlopen", urlopen)
    job = {"url": ARTICLE, "title": ""}
    server.alert_failure(
        job, "paywalled: 350 of its 1115 words are free; archive.today has no snapshot"
    )
    assert sent[0].full_url == "https://ntfy.example"
    assert json.loads(sent[0].data) == {
        "topic": "podcast",
        "title": "Not read aloud: nytimes.com",
        "message": "paywalled: 350 of its 1115 words are free; archive.today has no snapshot",
        "tags": ["warning"],
        "click": ARTICLE,
    }

    def offline(request: urllib.request.Request, timeout: int) -> Response:
        raise OSError("network unavailable")

    monkeypatch.setattr(server.urllib.request, "urlopen", offline)
    server.alert_failure(job, "x")  # logged, not raised
