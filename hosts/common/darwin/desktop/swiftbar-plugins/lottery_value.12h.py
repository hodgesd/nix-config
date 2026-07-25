#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "aiohttp>=3.8.0",
#   "beautifulsoup4>=4.9.0",
# ]
# ///
"""
Lottery Value — SwiftBar plugin
Compares Powerball and Mega Millions jackpot value per dollar and shows
WAIT/BUY against a conservative rare-purchase trigger.

Data source: public Illinois Lottery result pages. If parsing fails, the
last successful values are shown and marked stale. Parsed values are
sanity-checked (cash must be 30-75% of the advertised annuity) so a markup
change cannot silently produce plausible garbage.

Rename to control the refresh cadence (SwiftBar filename convention), e.g.
lottery_value.12h.py or lottery_value.1d.py, and chmod +x it.

This is entertainment budgeting software, not investment advice.
"""
# <bitbar.title>Lottery Value</bitbar.title>
# <bitbar.author>hodgesd</bitbar.author>
# <bitbar.desc>Powerball vs Mega Millions jackpot value with a rare-buy trigger</bitbar.desc>
# <bitbar.dependencies>python,aiohttp</bitbar.dependencies>
# <bitbar.version>2.0</bitbar.version>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>false</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

from __future__ import annotations

import asyncio
import json
import re
import subprocess
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import aiohttp
from bs4 import BeautifulSoup

# --- CONFIGURATION ---

APP_NAME = "Lottery Value"
CONFIG_DIR = Path.home() / "Library" / "Application Support" / "LotteryValueMenu"
CONFIG_FILE = CONFIG_DIR / "config.json"
CACHE_FILE = CONFIG_DIR / "cache.json"
STATE_FILE = CONFIG_DIR / "state.json"

POWERBALL_URL = "https://www.illinoislottery.com/dbg/results/powerball"
MEGA_URL = "https://www.illinoislottery.com/dbg/results/mega-millions"

FETCH_TIMEOUT_SECONDS = 20
FETCH_RETRY_COUNT = 1

DEFAULT_CONFIG = {
    "buy_trigger_score": 0.70,
    "minimum_advertised_jackpot_millions": 900,
    "daily_budget_cap": 10,
    "notify_when_triggered": True,
}

# Real cash options historically run ~45-52% of the advertised annuity.
# Anything outside this band almost certainly means the parser grabbed the
# wrong number, so we reject it rather than display it.
CASH_RATIO_MIN = 0.30
CASH_RATIO_MAX = 0.75

# lower_tier_ev: approximate pre-tax EV of all NON-jackpot prizes per ticket.
# An estimate, used only so the cross-game ranking is fair to Mega Millions
# (whose $5 price includes a built-in multiplier that pays off on lower
# tiers). The BUY trigger itself stays jackpot-only and conservative.
GAME_RULES = {
    "Powerball": {
        "ticket_price": 2.0,
        "jackpot_odds": 292_201_338,
        "lower_tier_ev": 0.32,
        "url": POWERBALL_URL,
    },
    "Mega Millions": {
        "ticket_price": 5.0,
        "jackpot_odds": 290_472_336,
        "lower_tier_ev": 0.90,
        "url": MEGA_URL,
    },
}


@dataclass
class GameData:
    name: str
    advertised_millions: float
    cash_millions: float
    ticket_price: float
    jackpot_odds: int
    fetched_at: str
    source_url: str
    lower_tier_ev: float = 0.0
    stale: bool = False
    fetch_error: Optional[str] = None

    @property
    def cash_ratio(self) -> float:
        if self.advertised_millions <= 0:
            return 0.0
        return self.cash_millions / self.advertised_millions

    @property
    def jackpot_ev_dollars(self) -> float:
        """Pre-tax jackpot-only expected value, ignoring split risk."""
        return self.cash_millions * 1_000_000 / self.jackpot_odds

    @property
    def score(self) -> float:
        """Jackpot-only value score used for the BUY trigger. 1.00 means the
        pre-tax jackpot EV equals the ticket cost."""
        return self.jackpot_ev_dollars / self.ticket_price

    @property
    def total_score(self) -> float:
        """Jackpot + estimated lower-tier EV per dollar. Used only for
        ranking the two games fairly against each other."""
        return (self.jackpot_ev_dollars + self.lower_tier_ev) / self.ticket_price


# --- PERSISTENCE HELPERS ---


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def save_json(path: Path, value) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2))


def cached_games() -> dict[str, GameData]:
    raw = load_json(CACHE_FILE, {})
    games = {}
    for name, item in raw.items():
        try:
            item["stale"] = True
            item.pop("fetch_error", None)
            games[name] = GameData(**item)
        except (TypeError, KeyError):
            pass
    return games


def save_games(games: dict[str, GameData]) -> None:
    save_json(
        CACHE_FILE,
        {
            name: {k: v for k, v in asdict(g).items() if k != "fetch_error"}
            for name, g in games.items()
        },
    )


# --- PARSING ---


def money_millions(value: float) -> str:
    if value >= 1000:
        return f"${value / 1000:.2f}B"
    return f"${value:,.0f}M"


def parse_money_millions(text: str) -> Optional[float]:
    """Accepts "$707 Million", "$1.05 Billion", "$1,050 Million", "$307.7 MILLION"."""
    clean = text.replace(",", "")  # "$1,050 Million" -> "$1050 Million"
    match = re.search(
        r"\$\s*([0-9]+(?:\.[0-9]+)?)\s*(BILLION|MILLION|B|M)\b",
        clean,
        flags=re.IGNORECASE,
    )
    if not match:
        return None
    amount = float(match.group(1))
    unit = match.group(2).upper()
    return amount * 1000 if unit in {"BILLION", "B"} else amount


def validate_jackpot_pair(advertised: float, cash: float) -> None:
    """Reject parses that cannot be a real annuity/cash pair."""
    if cash >= advertised:
        raise ValueError(
            f"Cash ({cash}M) is not below advertised jackpot ({advertised}M)"
        )
    ratio = cash / advertised
    if not (CASH_RATIO_MIN <= ratio <= CASH_RATIO_MAX):
        raise ValueError(
            f"Cash/annuity ratio {ratio:.2f} outside plausible range; "
            f"likely a parsing error"
        )


def extract_jackpots(html: str) -> tuple[float, float]:
    """Parse advertised + cash jackpots from visible page text, then validate
    that the pair is plausible before returning it."""
    text = BeautifulSoup(html, "html.parser").get_text(" ", strip=True)
    normalized = re.sub(r"\s+", " ", text)

    advertised_patterns = [
        r"JACKPOT\s+IS\s+CURRENTLY(?:\s+JACKPOT)?\s+(\$[\d.,]+\s*(?:MILLION|BILLION|M|B))",
        r"NEXT\s+JACKPOT[^$]{0,80}(\$[\d.,]+\s*(?:MILLION|BILLION|M|B))",
        r"ESTIMATED\s+JACKPOT[^$]{0,80}(\$[\d.,]+\s*(?:MILLION|BILLION|M|B))",
    ]
    cash_patterns = [
        r"CASH\s+(?:VALUE|OPTION|JACKPOT)[^$]{0,80}(\$[\d.,]+\s*(?:MILLION|BILLION|M|B))",
        r"JACKPOT\s*/\s*CASH\s+VALUE[^$]{0,120}\$[\d.,]+\s*(?:MILLION|BILLION|M|B)\s*/\s*(\$[\d.,]+\s*(?:MILLION|BILLION|M|B))",
    ]

    advertised = None
    for pattern in advertised_patterns:
        m = re.search(pattern, normalized, flags=re.IGNORECASE)
        if m:
            advertised = parse_money_millions(m.group(1))
            if advertised:
                break

    cash = None
    for pattern in cash_patterns:
        m = re.search(pattern, normalized, flags=re.IGNORECASE)
        if m:
            cash = parse_money_millions(m.group(1))
            if cash:
                break

    # Flexible fallback: locate all dollar amounts and choose plausible values.
    amounts = [parse_money_millions(m.group(0)) for m in re.finditer(
        r"\$[\d.,]+\s*(?:MILLION|BILLION|M|B)\b", normalized, flags=re.IGNORECASE
    )]
    amounts = [x for x in amounts if x is not None and x >= 10]

    if advertised is None and amounts:
        advertised = max(amounts)
    if cash is None and advertised is not None:
        # Cash must sit inside the plausible ratio band; take the largest
        # candidate that does. This prevents grabbing a historical jackpot
        # or another game's figure from elsewhere on the page.
        candidates = [
            x for x in amounts
            if x < advertised
            and CASH_RATIO_MIN <= (x / advertised) <= CASH_RATIO_MAX
        ]
        if candidates:
            cash = max(candidates)

    if advertised is None or cash is None:
        raise ValueError("Could not identify both advertised and cash jackpot values")

    validate_jackpot_pair(advertised, cash)
    return advertised, cash


# --- FETCHING ---


async def fetch_html(session: aiohttp.ClientSession, url: str) -> tuple[str, Optional[str]]:
    """Fetch HTML with retry logic. Returns (html, error_message)."""
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 LotteryValueMenu/2.0"
        )
    }
    for attempt in range(FETCH_RETRY_COUNT + 1):
        try:
            async with session.get(
                url,
                headers=headers,
                timeout=aiohttp.ClientTimeout(total=FETCH_TIMEOUT_SECONDS),
            ) as response:
                if response.status == 200:
                    return await response.text(), None
                error_msg = f"HTTP {response.status}"
                if attempt < FETCH_RETRY_COUNT:
                    backoff = 2.0 if response.status == 429 else 0.5 * (attempt + 1)
                    await asyncio.sleep(backoff)
                    continue
                return "", error_msg
        except asyncio.TimeoutError:
            if attempt < FETCH_RETRY_COUNT:
                await asyncio.sleep(0.5 * (attempt + 1))
                continue
            return "", "Timeout"
        except Exception as e:
            if attempt < FETCH_RETRY_COUNT:
                await asyncio.sleep(0.5 * (attempt + 1))
                continue
            return "", f"Error: {type(e).__name__}"
    return "", "Unknown error"


async def fetch_game(session: aiohttp.ClientSession, name: str) -> GameData:
    rules = GAME_RULES[name]
    html, error = await fetch_html(session, rules["url"])
    if error:
        raise ValueError(error)
    advertised, cash = extract_jackpots(html)
    return GameData(
        name=name,
        advertised_millions=advertised,
        cash_millions=cash,
        ticket_price=rules["ticket_price"],
        jackpot_odds=rules["jackpot_odds"],
        lower_tier_ev=rules["lower_tier_ev"],
        fetched_at=datetime.now(timezone.utc).isoformat(),
        source_url=rules["url"],
    )


async def fetch_all_games() -> dict[str, GameData]:
    """Fetch both games in parallel; fall back to cache (marked stale) on failure."""
    old = cached_games()
    async with aiohttp.ClientSession() as session:
        results = await asyncio.gather(
            *(fetch_game(session, name) for name in GAME_RULES),
            return_exceptions=True,
        )
    games: dict[str, GameData] = {}
    for name, result in zip(GAME_RULES, results):
        if isinstance(result, GameData):
            games[name] = result
        else:
            error = str(result)
            if name in old:
                games[name] = old[name]
                games[name].fetch_error = error
            else:
                games[name] = GameData(
                    name=name,
                    advertised_millions=0,
                    cash_millions=0,
                    ticket_price=GAME_RULES[name]["ticket_price"],
                    jackpot_odds=GAME_RULES[name]["jackpot_odds"],
                    lower_tier_ev=GAME_RULES[name]["lower_tier_ev"],
                    fetched_at=datetime.now(timezone.utc).isoformat(),
                    source_url=GAME_RULES[name]["url"],
                    stale=True,
                    fetch_error=error,
                )
    if any(not g.stale for g in games.values()):
        save_games({n: g for n, g in games.items() if g.advertised_millions > 0})
    return games


# --- RECOMMENDATION ---


def recommendation(game: GameData, config: dict) -> tuple[bool, str]:
    score_ok = game.score >= float(config["buy_trigger_score"])
    jackpot_ok = game.advertised_millions >= float(
        config["minimum_advertised_jackpot_millions"]
    )
    if score_ok and jackpot_ok:
        return True, "Rare-buy trigger met"
    reasons = []
    if not jackpot_ok:
        reasons.append(
            f"below {money_millions(config['minimum_advertised_jackpot_millions'])}"
        )
    if not score_ok:
        reasons.append(f"value score below {config['buy_trigger_score']:.0%}")
    text = "; ".join(reasons)
    return False, text[0].upper() + text[1:]  # capitalize first letter only


def maybe_notify(games: dict[str, GameData], config: dict) -> None:
    """Send a macOS notification when the trigger is newly met. The signature
    is persisted so repeated SwiftBar runs don't re-alert for the same
    jackpot."""
    if not config.get("notify_when_triggered", True):
        return
    triggered = [g for g in games.values() if recommendation(g, config)[0]]
    if not triggered:
        return
    signature = sorted(
        [g.name, g.advertised_millions, g.cash_millions] for g in triggered
    )
    state = load_json(STATE_FILE, {})
    if signature == state.get("last_notification_signature"):
        return
    state["last_notification_signature"] = signature
    save_json(STATE_FILE, state)
    best = max(triggered, key=lambda g: g.score)
    message = (
        f"{money_millions(best.advertised_millions)} advertised; "
        f"{money_millions(best.cash_millions)} cash; "
        f"{best.score:.0%} jackpot-value score."
    )
    script = (
        f"display notification {json.dumps(message)} "
        f"with title {json.dumps(APP_NAME)} "
        f"subtitle {json.dumps(best.name + ' rare-buy trigger met')} "
        f'sound name "Glass"'
    )
    subprocess.run(["osascript", "-e", script], check=False)


# --- DISPLAY ---


def generate_swiftbar_menu(games: dict[str, GameData], config: dict) -> None:
    valid = [g for g in games.values() if g.advertised_millions > 0]
    any_error = any(g.fetch_error for g in games.values())

    # -- MENU BAR LINE --
    if not valid:
        print("🎟 ⚠️")
        print("---")
        print("No jackpot data | color=#888888")
        for g in games.values():
            if g.fetch_error:
                print(f"⚠️ {g.name}: {g.fetch_error} | color=#cc4444 size=11")
        print("Refresh now | refresh=true")
        return

    # Rank by TOTAL value (jackpot + estimated lower-tier EV) per dollar so
    # the comparison is fair to both games' price structures.
    ordered = sorted(valid, key=lambda g: g.total_score, reverse=True)
    best = ordered[0]
    best_buy, _ = recommendation(best, config)
    error_flag = " ⚠️" if any_error else ""
    print(f"{'✅' if best_buy else '🎟'} {best.name.split()[0]}{error_flag}")

    print("---")
    now = datetime.now(timezone.utc)

    for game in ordered:
        triggered, reason = recommendation(game, config)
        try:
            age = now - datetime.fromisoformat(game.fetched_at)
        except ValueError:
            age = timedelta(0)
        is_stale = game.stale or age > timedelta(hours=30)
        stale_note = " • stale" if is_stale else ""
        error_icon = "⚠️ " if game.fetch_error else ""

        verdict = "BUY ✅" if triggered else "WAIT"
        header = (
            f"{error_icon}{verdict} — {game.name}: "
            f"{money_millions(game.advertised_millions)}{stale_note}"
        )
        tooltip_parts = [reason]
        if game.fetch_error:
            tooltip_parts.append(f"Error: {game.fetch_error}")
        tooltip = " | ".join(tooltip_parts).replace('"', "'")
        color = " color=#33aa55" if triggered else ""
        print(
            f'{header} | href={game.source_url} font=Menlo-Bold '
            f'tooltip="{tooltip}"{color}'
        )
        print(f"--Cash value: {money_millions(game.cash_millions)} "
              f"({game.cash_ratio:.0%} of annuity) | font=Menlo size=12")
        print(f"--Jackpot EV: ${game.jackpot_ev_dollars:.2f} per "
              f"${game.ticket_price:.0f} ticket | font=Menlo size=12")
        print(f"--Jackpot-only score: {game.score:.0%} of ticket price | "
              f"font=Menlo size=12")
        print(f"--Total value score: {game.total_score:.0%} "
              f"(incl. est. small prizes) | font=Menlo size=12")
        print(f"--{reason} | size=12 color={'#33aa55' if triggered else '#888888'}")
        if game.fetch_error:
            print(f"--⚠️ {game.fetch_error} (showing cached values) | "
                  f"size=11 color=#cc4444")
        print(f"--Open official page | href={game.source_url}")

    # -- FOOTER --
    print("---")
    print(
        f"Trigger: ≥ {money_millions(config['minimum_advertised_jackpot_millions'])} "
        f"and ≥ {config['buy_trigger_score']:.0%} jackpot-only score | "
        f"size=11 color=#888888"
    )
    print(
        f"Budget ceiling (advisory): ${config['daily_budget_cap']:.0f} "
        f"per drawing day | size=11 color=#888888"
    )
    print("Rationale | size=11 color=#888888")
    for line in (
        "The jackpot-only score is cash jackpot ÷ odds ÷ ticket price.",
        "It is pre-tax and ignores lower tiers and split risk, so the",
        "70% trigger stays conservative — never a claim the ticket is",
        "a good investment. The total score adds estimated small-prize",
        "EV only to rank the two games fairly (MM's $5 includes a",
        "multiplier that pays off on lower tiers). The $900M floor",
        "preserves the near-$1B habit. The budget cap is the most",
        "important rule: entertainment only, never chase losses.",
    ):
        print(f"--{line} | size=12 color=#888888")
    print("---")
    print("Refresh now | refresh=true")
    print(
        f'Edit settings | bash=/usr/bin/open param0=-t '
        f'param1="{CONFIG_FILE}" terminal=false'
    )


# --- MAIN ---


def main() -> None:
    config = {**DEFAULT_CONFIG, **load_json(CONFIG_FILE, {})}
    save_json(CONFIG_FILE, config)
    games = asyncio.run(fetch_all_games())
    maybe_notify(games, config)
    generate_swiftbar_menu(games, config)


if __name__ == "__main__":
    main()
