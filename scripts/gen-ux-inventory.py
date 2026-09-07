#!/usr/bin/env python3
"""Regenerate docs/ux-inventory.md, the player-facing surface implied by DESIGN.md.

The design never designed a UI, but it imposes display, disclosure and
notification requirements in most of its sections. This collects them, assigns
each to the screen that must carry it, and measures the result against the
session length section 1 promises. DESIGN.md remains the authority; every
requirement here is quoted from it verbatim so the checker can prove it.
"""
import io
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRIPWIRE = 62

SCREENS = [
    ("World map", "The shared ocean: ship positions, routes and ports, on Equal Earth."),
    ("Ship inspector", "What another company's ship reveals when selected."),
    ("Port panel", "The hub for one port: markets, auctions, storage and congestion."),
    ("Market", "One port's order books for a good, with depth rather than a headline quote."),
    ("Auction house", "Scheduled consignment, asset and liquidation auctions at a port."),
    ("Procurement board", "System-originated delivery contracts open for supplier bids."),
    ("Cargo and storage", "Owned cargo and leased warehouse space, with freshness and rent."),
    ("Fleet and ship detail", "One ship: cargo, instructions, dispatch estimate and delays."),
    ("Route planner", "Stops, targets, budgets and repeatable circuits."),
    ("Finance", "Loans, arrears, profit, ROI and the leaderboards."),
    ("Company and account", "Identity, invitations, bankruptcy history and onboarding."),
    ("Notifications", "The out-of-band and in-app stream of completed actions."),
]

# (id, verbatim quote from DESIGN.md, section, kind, screen)
REQUIREMENTS = [
    (1, "Show ship positions and routes visually.", 4, "display", "World map"),
    (2, "Pacific crossings must display continuously across the map seam rather than as false cross-world lines.", 4, "display", "World map"),
    (3, "Use one representative harbor marker per roster entry, located at the actual harbor, and show both city and port names where they differ.", 4, "display", "World map"),
    (4, "Selecting another ship shows its company and ship class, but never its cargo manifest.", 4, "disclosure", "Ship inspector"),
    (5, "Ships owned by a company undergoing bankruptcy display a clear public", 4, "display", "Ship inspector"),
    (6, "Keep that status visible while the estate owns the ship, including during voyage completion and liquidation", 4, "display", "Ship inspector"),
    (7, "Liquidation lots are an explicit exception: offered cargo's quantity, location, and freshness become visible to potential buyers.", 4, "disclosure", "Auction house"),
    (8, "Public market orders show prices and quantities without identifying their companies.", 4, "disclosure", "Market"),
    (9, "Market depth must reveal how much can trade at a price rather than imply unlimited liquidity at the headline quote.", 7, "display", "Market"),
    (10, "Always show estimated real time remaining under current storage conditions as well", 6, "display", "Cargo and storage"),
    (11, "show projected freshness after handling before commitment as an estimate, not a", 7, "disclosure", "Cargo and storage"),
    (12, "Show estimated freshness both at arrival and after unloading, including expected queue and handling time.", 7, "display", "Fleet and ship detail"),
    (13, "expose the cargo's actual current grade", 7, "display", "Market"),
    (14, "Show", 7, "disclosure", "Auction house"),
    (15, "Show opening and closing times in the player's local time with countdowns.", 7, "display", "Auction house"),
    (16, "Perishable lots keep aging and show projected freshness at closing.", 7, "display", "Auction house"),
    (17, "Preserve separate entries for equal amounts, but expose no company names or persistent bidder identifiers.", 7, "disclosure", "Auction house"),
    (18, "Show the required coverage before posting.", 7, "disclosure", "Procurement board"),
    (19, "Notify the player of any remaining shortfall.", 8, "notification", "Notifications"),
    (20, "notify the player that the affected cargo is entering liquidation and is no longer earmarked for the ship", 8, "notification", "Notifications"),
    (21, "Notify once when a ship becomes blocked and once when it resumes, without repeated alerts for an unchanged blocked state.", 8, "notification", "Notifications"),
    (22, "Notify the player when accumulation times out.", 8, "notification", "Notifications"),
    (23, "identifying the ship, port, good, cancelled quantity, released reservations, and any already-purchased cargo still stored there", 8, "notification", "Notifications"),
    (24, "The notification reports the completed action and does not require approval to carry it out.", 8, "notification", "Notifications"),
    (25, "Finish committed handling and notify the loading shortfall before continuing under the departure funding rules.", 8, "notification", "Notifications"),
    (26, "Before confirmation, show the revised route, arrival estimate, and additional fuel requirement.", 8, "disclosure", "Route planner"),
    (27, "Show local trading opportunities before the player confirms their selection.", 9, "disclosure", "Company and account"),
    (28, "Show known delays before dispatch and revised arrival estimates underway.", 10, "display", "Fleet and ship detail"),
    (29, "Show the estimate and reserve the necessary cash before dispatch", 10, "disclosure", "Fleet and ship detail"),
    (30, "show projected maintenance for coming periods", 10, "display", "Fleet and ship detail"),
    (31, "Show one total quote before purchase; do not price the entire request at its starting utilization.", 11, "disclosure", "Cargo and storage"),
    (32, "show both rates in expiry warnings", 11, "display", "Cargo and storage"),
    (33, "a visible repayment schedule", 12, "display", "Finance"),
    (34, "Show the arrears, deadline, and warnings.", 12, "display", "Finance"),
    (35, "Show the remaining time; inspecting the world remains available.", 12, "display", "Company and account"),
    (36, "the lifetime count remains permanently visible on the account and in the rankings", 12, "display", "Company and account"),
    (37, "Rankings show the player's lifetime bankruptcy count.", 3, "display", "Finance"),
    (38, "partial-period company results are labelled provisional and unranked", 13, "display", "Finance"),
    (39, "display ROI as unavailable, never infinite or ranked", 13, "display", "Finance"),
    (40, "display the game period and the corresponding real interval together", 3, "display", "Finance"),
    (41, "port panels for markets, auctions, storage,", 16, "display", "Port panel"),
]

# Every mechanically deep feature in sections 7 and 8 is opt-in with a stated
# default. The defaults are scattered; collecting them is the point.
DEFAULTS = [
    ("Arrival purchase funding", "Available unreserved cash at berth, up to the stop's spending cap. An earmarked advance budget is optional.", 8),
    ("Owned stock collection", "Ships claim available owned stock when berthed. Reserving specific stock in advance for one ship is optional.", 8),
    ("Insufficient funds at departure", "Wait and notify. Sail with a reduced budget and Skip purchases are alternatives, set once globally.", 8),
    ("Perishable sell pricing", "The order's existing minimum price. Automatic markdown schedules are optional and saved as reusable presets.", 7),
    ("Stop completion", "Wait for configured targets. A maximum wait is optional.", 8),
    ("Remote buy orders", "Independent of any ship. Linking one to a collection stop is optional.", 7),
    ("Standing order lifetime", "Active until cancelled. An expiration is optional and player-set.", 7),
    ("Buyer freshness terms", "None. A minimum remaining shelf life is something buyers can require, not must.", 6),
]

SESSION = [
    ("Choose a destination", "World map, Port panel", "1", "Compare prices already visible worldwide; no configuration required."),
    ("Buy cargo", "Market", "2", "Good and quantity, against a price limit. Spending cap and freshness terms default."),
    ("Dispatch", "Fleet and ship detail", "1", "Confirm the dispatch estimate. Fuel is reserved automatically; bunkering is not managed."),
    ("Sail", "none", "0", "Unattended. Delays and revised estimates are pushed, not polled."),
    ("Sell", "Market", "1", "Confirm or adjust the standing minimum price."),
    ("Reinvest", "Market, Fleet and ship detail", "1", "Repeat, or buy a ship at a fixed shipyard price."),
]

FINDINGS = [
    "Sections 3 and 7 both govern how time is shown, without referencing each "
    "other. Section 3 requires a game period and its real interval together "
    "wherever a player commits; section 7 requires auction opening and closing "
    "times in the player's local time with countdowns. An auction window is one "
    "place a player commits, so both apply and neither says how they combine.",
]

RESOLVED = [
    "Progressive disclosure was absent as a principle, so nothing prevented an "
    "implementation surfacing earmarked budgets or markdown schedules on the "
    "path to a first purchase. Section 1 now states it, bounded so that it never "
    "defers a required pre-commitment disclosure, and decision group 24 records "
    "it.",
    "Requirement 4 was permissive where its neighbours are imperative, leaving "
    "the floor unstated even though the privacy ceiling was clear. Section 4 now "
    "requires company and ship class on inspection.",
]


def para(text, width=80, indent=""):
    return textwrap.fill(" ".join(text.split()), width=width,
                         initial_indent=indent, subsequent_indent=indent,
                         break_long_words=False, break_on_hyphens=False)


def table(header, rows):
    out = ["| " + " | ".join(header) + " |",
           "|" + "|".join("-" * (len(h) + 2) for h in header) + "|"]
    return out + ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]


o = ["# Tijara Tides — Player-Facing Surface\n"]
o.append(para("""
Derived from [the game design](DESIGN.md), which remains the authority. The
design never designed a user interface, but it imposes display, disclosure and
notification requirements in most of its sections. This collects them, assigns
each to the screen that must carry it, and measures the result against the
session length section 1 promises."""))
o.append("")
o.append(para("""
This file is generated by `scripts/gen-ux-inventory.py`. Every requirement below
is quoted verbatim from DESIGN.md, and `test/docs/ux_inventory_test.exs` proves
each quote still appears there, that every requirement lands on a declared
screen, and that no declared screen carries nothing."""))
o.append("")
o.append(para("""
One limitation is worth stating plainly: verbatim quoting proves a requirement
has not been reworded or deleted, but it cannot notice one **added** to DESIGN.md
later. Detecting additions needs a keyword heuristic with both false positives
and false negatives, and a checker built on that would grant false confidence.
Instead the count below is a tripwire. When it moves, look at what changed,
confirm nothing was added, and regenerate. The keyword list covers inflected
forms deliberately: an earlier version matched `show` but not `shows`, so
rewording a requirement to be more imperative silently reduced the count."""))
o.append("")
o.append("Heuristic requirement sentences in DESIGN.md at generation: %d\n" % TRIPWIRE)

o.append("## Screens\n")
o.append(para("""
Section 4 already fixes the map and the port panel; section 7 fixes what a
market must reveal. The rest are implied by where requirements land."""))
o.append("")
o += table(["Screen", "Purpose"], SCREENS)
o.append("")

o.append("## Requirements\n")
o.append(para("""
`display` means something must be shown; `disclosure` means it must be shown
*before* the player commits to something; `notification` means the player is
told after the fact, without being asked to approve it."""))
o.append("")
o += table(["#", "Requirement", "Section", "Kind", "Screen"],
           [(i, q, s, k, scr) for i, q, s, k, scr in REQUIREMENTS])
o.append("")

o.append("## Defaults that keep the depth optional\n")
o.append(para("""
Sections 6 to 8 specify a great deal of machinery, and every piece of it is
opt-in behind a stated default. Those defaults are scattered across three
sections and are collected here. Section 1 makes progressive disclosure a design
principle and names this set explicitly, so these defaults are load-bearing:
each one is what keeps its mechanic off the path to a first purchase."""))
o.append("")
o += table(["Mechanic", "Default when the player configures nothing", "§"], DEFAULTS)
o.append("")

o.append("## Session budget\n")
o.append(para("""
Section 1 promises check-ins through the day and engaged sessions of up to
roughly twenty minutes, against a core loop of buy cargo, choose a destination,
sail, sell, reinvest. Minutes cannot be measured from a document; decisions and
screens can. This counts only what a player must do when every optional
mechanic is left at its default."""))
o.append("")
o += table(["Step", "Screens", "Required decisions", "Notes"], SESSION)
o.append("")
o.append(para("""
Six decisions across four screens for a complete circuit, with the voyage itself
unattended. Each optional mechanic a player adopts adds configuration to one
stop or one order, not to every visit."""))
o.append("")

o.append("## Findings\n")
o.append(para("""
Still open. These are recorded rather than resolved, because DESIGN.md is the
authority and a derived document should not invent rules."""))
o.append("")
for finding in FINDINGS:
    o.append(para("- " + finding).replace("\n", "\n  "))
    o.append("")
o.append(para("""
Resolved in DESIGN.md since this inventory was first collected:"""))
o.append("")
for finding in RESOLVED:
    o.append(para("- " + finding).replace("\n", "\n  "))
    o.append("")

io.open(ROOT / "docs/ux-inventory.md", "w", encoding="utf-8").write("\n".join(o))
print("wrote docs/ux-inventory.md")
