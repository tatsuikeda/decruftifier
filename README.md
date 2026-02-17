# The macOS Decruftifier

**Your Mac has been accumulating cruft since the day you unboxed it.**

Every app you ever installed — then deleted — left behind launch agents, daemons, and preference files. That copy of Adobe CS4 from 2008? Its background updater is still trying to phone home. The printer you threw away in 2015? Its driver daemon fires up every boot. Skype, Fitbit, MobileMe, Citrix — ghosts of software past, all loading silently at login, burning CPU cycles and cluttering your system for years.

Commercial "Mac cleaners" show you a pretty pie chart of your cache folder and charge $40/year. **The Decruftifier actually finds the stuff that matters** — orphaned launch agents with missing executables, known malware patterns, obsolete daemons from discontinued software, Spotlight indexing your Time Machine backups for no reason — and lets you remove it safely.

## What it finds

- **Malware & adware** — 20+ known patterns (Genieo, VSearch, Conduit, MacKeeper, and more)
- **Orphaned launch agents/daemons** — executables that no longer exist but still try to load at boot
- **Obsolete software** — Adobe CS4/CS5 updaters, MobileMe sync, Fitbit Connect, Flash Player, Java browser plugins, and other relics
- **Spotlight waste** — indexing Time Machine backups, external drives you don't need searched
- **Resource hogs** — processes silently eating CPU and memory in the background
- **Cache bloat** — iOS device backups, Xcode DerivedData, oversized logs

## Usage

```bash
# Audit only — scan and report, change nothing
bash decruftifier.sh --audit

# Interactive — prompts before each removal
bash decruftifier.sh

# Full auto — run everything without prompting
bash decruftifier.sh --auto

# Single phase
bash decruftifier.sh --phase 3
```

Requires sudo for system-level agents and daemons. Will prompt when needed.

## Phases

| # | Phase | What it does |
|---|-------|-------------|
| 1 | System Health | SMART status, disk usage, memory, swap, WindowServer CPU, kernel panics |
| 2 | Malware Scan | Known adware/malware signatures in launch agents and ~/Library |
| 3 | Orphan Scan | Launch agents and daemons whose executables no longer exist |
| 4 | Obsolete Items | Discontinued or superseded software still loading at boot |
| 5 | Spotlight Audit | Flags wasteful indexing (Time Machine volumes, external media) |
| 6 | Caches & Temp | Cache sizes, large logs, iOS backups, Xcode DerivedData |
| 7 | Login Items | Counts and audits all startup programs and background tasks |
| 8 | Resource Hogs | Top CPU and memory consumers right now |

## Output

- Color-coded console output (`[OK]`, `[WARN]`, `[!!]`)
- Full log saved to `~/Desktop/decruftifier-YYYYMMDD-HHMMSS.log` (ANSI stripped)

## Extending

**Add malware signatures:** Edit the `SUSPECT_PATTERNS` array in `decruftifier.sh`.

**Add obsolete software:** Edit the `OBSOLETE_ITEMS` array. Format: `"identifier|description|location"` where location is `user`, `system-agent`, `system-daemon`, or `any`.

## Bonus: Spotlight Rebuild

```bash
# Rebuild Spotlight index with live progress monitoring
sudo bash spotlight-rebuild.sh [volume]
```

Shows elapsed time, index size, worker CPU usage, and auto-detects completion.

## Compatibility

- Intel and Apple Silicon Macs
- macOS 12 Monterey through macOS 26 Tahoe (and probably older)
- No dependencies beyond what ships with macOS
