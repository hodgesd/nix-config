"""Ready alerts use the published feed and leave finished episodes intact."""

from __future__ import annotations

import importlib
import sys
import urllib.parse
import urllib.request
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def test_ready_alert_pings_overcast_then_notifies_iphone(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("PODCAST_PUBLIC_BASE", "https://podcast.example")
    monkeypatch.setenv("PODCAST_INTAKE_TOKEN", "test-intake")
    monkeypatch.setenv("PODCAST_FEED_TOKEN", "test-feed")
    server = importlib.import_module("server")
    monkeypatch.setattr(server, "NTFY_URL", "https://ntfy.example/podcast-ready")
    sent: list[tuple[str, bytes, dict[str, str], int]] = []

    class Response:
        def __enter__(self) -> Response:
            return self

        def __exit__(self, *_args: object) -> None:
            pass

    def urlopen(request: urllib.request.Request, timeout: int) -> Response:
        sent.append((request.full_url, request.data, dict(request.header_items()), timeout))
        return Response()

    monkeypatch.setattr(server.urllib.request, "urlopen", urlopen)
    server.announce_ready("A useful article", 169)

    assert [url for url, *_ in sent] == [
        "https://overcast.fm/ping",
        "https://ntfy.example/podcast-ready",
    ]
    assert urllib.parse.parse_qs(sent[0][1].decode()) == {
        "urlprefix": ["https://podcast.example/p/test-feed/feed.xml"]
    }
    assert sent[1][1].decode() == "A useful article\n2:49 in Overcast"
    assert sent[1][2]["Title"] == "Ready to listen"
    assert sent[1][2]["Priority"] == "default"
    assert sent[1][3] == 5

    sent.clear()

    def failing_ping(request: urllib.request.Request, timeout: int) -> Response:
        if request.full_url == "https://overcast.fm/ping":
            raise OSError("network unavailable")
        return urlopen(request, timeout)

    monkeypatch.setattr(server.urllib.request, "urlopen", failing_ping)
    server.announce_ready("A useful article", 169)
    assert [url for url, *_ in sent] == ["https://ntfy.example/podcast-ready"]
