"""File Gulfstream AFMs and OMs dropped into "New Pubs".

Run by the gulfstream-pubs launchd agent (../gulfstream-pubs.nix) whenever
the folder changes:  python3 file_new_pubs.py <Pubs/Gulfstream root>

Each PDF is identified from its own front matter and renamed
<Model>_<Pub>[_I<issue>]_Rev<N>_<YYYY-MM-DD>.pdf, the gulfstream-pdf-splitter
skill's scheme. Then:
  - identical bytes to a filed copy of that revision -> to_delete/<name>_dup
  - same revision, different bytes                   -> to_delete/<name>_copyN
  - newer than the model folder's current copy       -> model folder; the old
    current copy moves to Archive/
  - older revision                                   -> model folder Archive/
Anything it can't identify with certainty, or that looks like an excerpt,
goes to "New Pubs/Needs Review" untouched. Every move is appended to
_filing_log.tsv in the root, and each outcome raises a notification.
"""

from __future__ import annotations

import hashlib
import re
import shlex
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

INBOX = "New Pubs"
REVIEW = "Needs Review"
EXCERPT_RATIO = 0.8  # fewer pages than this share of the current copy -> review
SETTLE_SECONDS = 600  # how long to wait for a file that is still being written
PARTIAL = {".crdownload", ".part", ".download", ".tmp"}

MONTHS = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}
MONTH_RE = r"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sept?|Oct|Nov|Dec)[a-z]*\.?"
DATE_RE = rf"({MONTH_RE}\s+\d{{1,2}},?\s+\d{{4}})"


@dataclass(frozen=True)
class Pub:
    model: str  # G500
    pub: str  # AFM or OM
    issue: str | None  # "1" or None when the manual states no issue
    rev: int
    date: str  # ISO

    @property
    def series(self) -> str:
        return f"{self.model}_{self.pub}" + (f"_I{self.issue}" if self.issue else "")

    @property
    def base(self) -> str:
        return f"{self.series}_Rev{self.rev}_{self.date}"


class NeedsReview(Exception):
    pass


def iso(text: str) -> str:
    month, day, year = re.match(r"([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})", text).groups()
    return date(int(year), MONTHS[month[:3].lower()], int(day)).isoformat()


def clean(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("™", "")).strip()


def identify(keywords: str, pages: list[str]) -> Pub:
    """Work out the publication from PDF keywords and its first pages' text.

    Pure, so it can be tested on text alone. Raises NeedsReview when a field
    is missing or the metadata and the title page disagree.
    """
    front = clean(" ".join(p for p in pages if "Terms and Conditions" not in p))
    if not front:
        raise NeedsReview("no text on the first pages (scanned or odd font)")

    model = re.search(r"GVII\s*[-–]\s*G(\d{3})\b", front)
    if not model:
        raise NeedsReview("no GVII model on the title pages")

    # Running headers repeat the manual's own name on every page, while tab
    # indexes and letters mention the others once or twice, so the most
    # frequent name wins. Only AFMs and OMs are filed.
    upper = front.upper()
    names = {
        "AFMS": upper.count("MANUAL SUPPLEMENT") + upper.count("AFMS GVII"),
        "AFM": upper.count("AIRPLANE FLIGHT MANUAL") - upper.count("MANUAL SUPPLEMENT"),
        "OM": upper.count("OPERATING MANUAL"),
        "MEL": upper.count("MINIMUM EQUIPMENT LIST"),
        "PAS": upper.count("PRODUCTION AIRCRAFT SYSTEMS"),
    }
    pub, top = max(names.items(), key=lambda kv: kv[1])
    if top == 0 or list(names.values()).count(top) > 1:
        raise NeedsReview("can't tell which manual this is")
    if pub not in ("AFM", "OM"):
        raise NeedsReview(f"looks like {pub}, not an AFM or OM")

    # Not "BASIC ISSUE <date>" or a cover's "DATE OF ISSUE 07/29/2019".
    issue = re.search(r"(?<!BASIC )(?<!OF )\bISSUE\s+(\d+)\b(?!/)", upper)

    title = re.search(rf"\bREV(?:ISION|\.)?\s+(\d+)\s*,?\s*(?:DATED\s+)?{DATE_RE}", front, re.I)
    basic = re.search(rf"\bBASIC ISSUE\s*,?\s*{DATE_RE}", front, re.I)
    found = sorted((m.start(), m) for m in (title, basic) if m)
    if not found:
        raise NeedsReview("no revision and date on the title pages")
    first = found[0][1]
    rev, when = (int(first.group(1)), iso(first.group(2))) if first is title else (0, iso(first.group(1)))
    # The record of revisions lists every earlier revision; a higher one than
    # we picked means the cover's wording was missed.
    highest = max((int(n) for n in re.findall(r"\bREV(?:ISION|\.)?\s+(\d+)\b", front, re.I)), default=rev)
    if highest > rev:
        raise NeedsReview(f"picked Rev {rev} but the front pages mention Rev {highest}")

    meta = re.search(r"Revision (\d+) \1 .*?(\d{4}-\d{2}-\d{2})", keywords)
    if meta and (int(meta.group(1)), meta.group(2)) != (rev, when):
        raise NeedsReview(f"title page says Rev {rev} {when}, metadata says Rev {meta.group(1)} {meta.group(2)}")

    return Pub(f"G{model.group(1)}", pub, issue.group(1) if issue else None, rev, when)


def pdf_info(path: Path) -> dict[str, str]:
    out = subprocess.run(["pdfinfo", str(path)], capture_output=True, text=True, errors="replace")
    if out.returncode != 0:
        raise ValueError(out.stderr.strip())
    return {k.strip(): v.strip() for k, _, v in (ln.partition(":") for ln in out.stdout.splitlines())}


def first_pages(path: Path, n: int = 12) -> list[str]:
    out = subprocess.run(["pdftotext", "-layout", "-l", str(n), str(path), "-"],
                         capture_output=True, text=True, errors="replace").stdout
    return out.split("\f")


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def settled(path: Path) -> bool:
    """Wait until the file stops growing and parses (copies and iCloud downloads)."""
    deadline = time.time() + SETTLE_SECONDS
    last, failures = -1, 0
    while time.time() < deadline:
        size = path.stat().st_size
        if size == last:
            try:
                pdf_info(path)
                return True
            except ValueError:
                failures += 1
                if failures >= 3:  # same size and still broken: corrupt, not in flight
                    return False
        else:
            failures = 0
        last = size
        time.sleep(3)
    return False


def free(path: Path) -> Path:
    """path, or path with _2, _3 ... before the suffix if it's taken."""
    n, candidate = 2, path
    while candidate.exists():
        candidate = path.with_name(f"{path.stem}_{n}{path.suffix}")
        n += 1
    return candidate


class Filer:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.inbox = root / INBOX
        self.trash = root / "to_delete"
        self.log = root / "_filing_log.tsv"

    def move(self, src: Path, dest: Path) -> Path:
        dest = free(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(src, dest)
        with self.log.open("a") as f:
            f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S}\t{src}\t{dest}\n")
        return dest

    def review(self, src: Path, reason: str) -> None:
        dest = self.move(src, self.inbox / REVIEW / src.name)
        print(f"review: {src.name}: {reason}", file=sys.stderr)
        notify("Needs review", f"{src.name}: {reason}", dest)

    def file(self, src: Path) -> None:
        if src.suffix.lower() != ".pdf":
            return self.review(src, "not a PDF")
        if not settled(src):
            return self.review(src, "unreadable PDF")
        info = pdf_info(src)
        try:
            pub = identify(info.get("Keywords", ""), first_pages(src))
        except NeedsReview as e:
            return self.review(src, str(e))

        folder = self.root / pub.model
        if not folder.is_dir():
            return self.review(src, f"no {pub.model} folder yet")

        # Current copies of this manual, any issue. A different issue than the
        # one on top means the issue line was missed or the lineage changed.
        tops = {p: m for p in folder.glob(f"{pub.model}_{pub.pub}_*.pdf")
                if (m := re.fullmatch(rf"{pub.model}_{pub.pub}(_I\d+)?_Rev(\d+)_\d{{4}}-\d\d-\d\d\.pdf", p.name))}
        if other := [p.name for p, m in tops.items() if (m.group(1) or "") != pub.series[len(f"{pub.model}_{pub.pub}"):]]:
            return self.review(src, f"issue differs from current {other[0]}")
        current = {p: int(m.group(2)) for p, m in tops.items()}
        newest = max(current, key=current.get, default=None)
        newest_rev = current[newest] if newest else -1

        # Before the duplicate check, so an excerpt of the current revision
        # isn't mistaken for a re-export and sent to to_delete.
        if newest and int(info.get("Pages", 0)) < EXCERPT_RATIO * int(pdf_info(newest).get("Pages", 0)):
            return self.review(src, f"{info.get('Pages')} pages vs {newest.name}; excerpt?")

        same = [*folder.glob(f"{pub.base}*.pdf"), *folder.glob(f"Archive/{pub.base}*.pdf")]
        if same:
            digest = sha(src)
            if any(sha(p) == digest for p in same):
                dest = self.move(src, self.trash / f"{pub.base}_dup.pdf")
                return notify("Duplicate → to_delete", dest.name, dest)
            n = 2
            while list(self.trash.glob(f"{pub.base}_copy{n}*.pdf")):
                n += 1
            dest = self.move(src, self.trash / f"{pub.base}_copy{n}.pdf")
            return notify("Same revision, different file → to_delete", dest.name, dest)

        if pub.rev == newest_rev:
            return self.review(src, f"same revision as {newest.name} but dated {pub.date}")
        if pub.rev < newest_rev:
            dest = self.move(src, folder / "Archive" / f"{pub.base}.pdf")
            return notify(f"Filed older {pub.pub} → Archive", dest.name, dest)

        for old in current:
            self.move(old, folder / "Archive" / old.name)
        dest = self.move(src, folder / f"{pub.base}.pdf")
        archived = ", ".join(f"Rev {r}" for r in current.values())
        notify(f"Filed {pub.base.replace('_', ' ')}", f"→ {pub.model}/" + (f" · {archived} archived" if archived else ""), dest)


def notify(subtitle: str, message: str, reveal: Path) -> None:
    """Banner via terminal-notifier (click reveals the file); osascript if that fails."""
    try:
        subprocess.run(["terminal-notifier", "-title", "Gulfstream Pubs", "-subtitle", subtitle,
                        "-message", message, "-sound", "Glass", "-group", f"gulfstream-pubs-{reveal}",
                        # -execute goes through a shell; quote the path so a
                        # crafted filename can't run code when clicked.
                        "-execute", f"/usr/bin/open -R {shlex.quote(str(reveal))}"], check=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        script = ('display notification (item 3 of argv) with title "Gulfstream Pubs" '
                  'subtitle (item 2 of argv) sound name "Glass"')
        subprocess.run(["/usr/bin/osascript", "-e", f"on run argv\n{script}\nend run",
                        "_", subtitle, message], check=False, timeout=30)


def main() -> None:
    filer = Filer(Path(sys.argv[1]))
    for src in sorted(filer.inbox.iterdir()):
        # Skip hidden files and browser downloads still in progress; the
        # browser's final rename triggers another run.
        if not src.is_file() or src.name.startswith(".") or src.suffix in PARTIAL:
            continue
        try:
            filer.file(src)
        except Exception as e:  # one bad file must not block the rest of the inbox
            print(f"error: {src.name}: {e!r}", file=sys.stderr)
            if src.exists():
                filer.review(src, f"error: {e}")


if __name__ == "__main__":
    main()
