"""The ready ping names only the published feed and never fails an episode."""

from __future__ import annotations

import importlib
import sys
import urllib.parse
import urllib.request
from pathlib import Path

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
