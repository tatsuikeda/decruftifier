#!/bin/bash
# decruftifier.sh — The macOS Decruftifier
# Finds and removes decades of accumulated system cruft.
# Works on any Mac (Intel or Apple Silicon, any macOS version)
#
# Usage:
#   bash decruftifier.sh              # Interactive mode (prompts before each phase)
#   bash decruftifier.sh --audit      # Audit only, no changes
#   bash decruftifier.sh --auto       # Run all phases without prompting
#   bash decruftifier.sh --phase 3    # Run specific phase only
#
# Requires sudo for some operations. Will prompt when needed.

set -uo pipefail

VERSION="1.0.0"
LOGFILE="$HOME/Desktop/decruftifier-$(date +%Y%m%d-%H%M%S).log"
AUDIT_ONLY=false
AUTO_MODE=false
SINGLE_PHASE=0
REMOVED=0
FLAGGED=0
SKIPPED=0

# ──────────────────────────────────────────────
# Colors & helpers
# ──────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
BLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

log()  { echo -e "$1" | tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOGFILE"); }
info() { log "${BLU}[INFO]${RST} $1"; }
ok()   { log "${GRN}[OK]${RST}   $1"; }
warn() { log "${YLW}[WARN]${RST} $1"; }
bad()  { log "${RED}[!!]${RST}   $1"; }
hdr()  { log ""; log "${BLD}═══════════════════════════════════════════${RST}"; log "${BLD}  $1${RST}"; log "${BLD}═══════════════════════════════════════════${RST}"; }

confirm() {
    if $AUTO_MODE; then return 0; fi
    if $AUDIT_ONLY; then return 1; fi
    echo -ne "${YLW}  Run this phase? [y/N] ${RST}"
    read -r ans
    [[ "$ans" =~ ^[Yy] ]]
}

# ──────────────────────────────────────────────
# Parse args
# ──────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --audit) AUDIT_ONLY=true; shift ;;
        --auto)  AUTO_MODE=true; shift ;;
        --phase) SINGLE_PHASE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash decruftifier.sh [--audit|--auto|--phase N]"
            echo "  --audit   Scan and report only, make no changes"
            echo "  --auto    Run all phases without prompting"
            echo "  --phase N Run only phase N (1-8)"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

should_run() {
    [[ $SINGLE_PHASE -eq 0 || $SINGLE_PHASE -eq $1 ]]
}

# ──────────────────────────────────────────────
# Detect system
# ──────────────────────────────────────────────
ARCH=$(uname -m)
OS_VER=$(sw_vers -productVersion)
OS_BUILD=$(sw_vers -buildVersion)
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname -s)
UID_NUM=$(id -u)

hdr "decruftifier v${VERSION} — ${HOSTNAME}"
info "macOS $OS_VER ($OS_BUILD) on $ARCH"
info "User: $(whoami) (UID $UID_NUM)"
info "Date: $(date)"
info "Log:  $LOGFILE"
if $AUDIT_ONLY; then info "Mode: AUDIT ONLY (no changes)"; fi
if $AUTO_MODE; then info "Mode: AUTO (no prompts)"; fi

# ══════════════════════════════════════════════
# PHASE 1: SYSTEM HEALTH BASELINE
# ══════════════════════════════════════════════
if should_run 1; then
hdr "Phase 1: System Health Baseline"

info "Uptime & load"
uptime 2>&1 | tee -a "$LOGFILE"

info "Disk health"
SMART=$(diskutil info disk0 2>/dev/null | grep "SMART Status" | awk -F: '{print $2}' | xargs)
if [[ "$SMART" == "Verified" ]]; then
    ok "SMART: $SMART"
else
    bad "SMART: ${SMART:-Unknown} — investigate disk health"
fi

info "Disk usage"
df -h / 2>/dev/null | tee -a "$LOGFILE"
# Flag if boot volume is over 85%
DISK_PCT=$(df / | tail -1 | awk '{gsub(/%/,""); print $5}')
if [[ $DISK_PCT -gt 85 ]]; then
    warn "Boot volume is ${DISK_PCT}% full"
else
    ok "Boot volume: ${DISK_PCT}% used"
fi

info "Memory"
PHYS_MEM=$(($(sysctl -n hw.memsize) / 1073741824))
SWAP=$(sysctl vm.swapusage 2>/dev/null | awk '{print $7}')
ok "Physical: ${PHYS_MEM}GB | Swap used: ${SWAP}"

info "WindowServer"
WS_CPU=$(ps aux | grep '[W]indowServer' | grep -v distnoted | awk '{print $3}')
WS_MEM_KB=$(ps aux | grep '[W]indowServer' | grep -v distnoted | awk '{print $6}')
WS_MEM_MB=$((${WS_MEM_KB:-0} / 1024))
WS_CPU_INT=${WS_CPU%%.*}
if [[ ${WS_CPU_INT:-0} -gt 25 ]]; then
    warn "WindowServer CPU: ${WS_CPU}% (elevated)"
else
    ok "WindowServer CPU: ${WS_CPU}% | Memory: ${WS_MEM_MB}MB"
fi

info "Kernel panics"
PANICS=$(find /Library/Logs/DiagnosticReports -name "*.panic" 2>/dev/null | wc -l | xargs)
USER_PANICS=$(find ~/Library/Logs/DiagnosticReports -name "*.panic" 2>/dev/null | wc -l | xargs)
TOTAL_PANICS=$(( ${PANICS:-0} + ${USER_PANICS:-0} ))
if [[ $TOTAL_PANICS -gt 0 ]]; then
    warn "$TOTAL_PANICS kernel panic logs found"
else
    ok "No kernel panics"
fi
fi

# ══════════════════════════════════════════════
# PHASE 2: MALWARE / SUSPICIOUS ITEMS
# ══════════════════════════════════════════════
if should_run 2; then
hdr "Phase 2: Malware & Suspicious Items Scan"

info "Scanning user LaunchAgents for suspicious items..."

# Known malware/adware identifiers (add to this list as needed)
SUSPECT_PATTERNS=(
    "ralimacit"
    "sinosonet"
    "riselisat"
    "corifana"
    "netifof"
    "shlayer"
    "pirrit"
    "bundlore"
    "genieo"
    "vsearch"
    "varenyky"
    "crossrider"
    "conduit"
    "mackeeper"
    "zeobit"
    "pcvark"
    "spigot"
    "operatorMac"
    "mughthesec"
    "SearchPageInjector"
)

MALWARE_DIRS=(
    "$HOME/Library/Application Support/netifof"
    "$HOME/Library/Application Support/.coreservices"
    "$HOME/Library/Application Support/com.pcv"
    "$HOME/Library/Application Support/spigot"
)

FOUND_MALWARE=false

# Check launch agents
for dir in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
    [[ -d "$dir" ]] || continue
    for plist in "$dir"/*.plist; do
        [[ -f "$plist" ]] || continue
        plist_lower=$(echo "$plist" | tr '[:upper:]' '[:lower:]')
        for pattern in "${SUSPECT_PATTERNS[@]}"; do
            if echo "$plist_lower" | grep -qi "$pattern"; then
                bad "SUSPICIOUS: $(basename "$plist") matches pattern '$pattern'"
                log "    Path: $plist"
                FOUND_MALWARE=true
                ((FLAGGED++))
            fi
        done
    done
done

# Check suspicious directories
for dir in "${MALWARE_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        bad "SUSPICIOUS DIRECTORY: $dir"
        ls -la "$dir" 2>/dev/null | tee -a "$LOGFILE"
        FOUND_MALWARE=true
        ((FLAGGED++))
    fi
done

# Check for agents from "Unknown Developer" running executables from ~/Library
while IFS= read -r plist; do
    [[ -f "$plist" ]] || continue
    exec_path=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null || \
                /usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null || echo "")
    if echo "$exec_path" | grep -q "$HOME/Library/Application Support/"; then
        label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null || basename "$plist")
        # Skip known legitimate apps
        if echo "$exec_path" | grep -qiE "(dropbox|google|adobe|backblaze|1password|zoom)"; then
            continue
        fi
        warn "User agent runs from ~/Library: $(basename "$plist")"
        log "    Exec: $exec_path"
        if [[ ! -e "$exec_path" ]]; then
            log "    ${RED}Executable MISSING${RST}"
        fi
        ((FLAGGED++))
    fi
done < <(find "$HOME/Library/LaunchAgents" -name "*.plist" 2>/dev/null)

if ! $FOUND_MALWARE && [[ $FLAGGED -eq 0 ]]; then
    ok "No known malware patterns found"
fi

if $FOUND_MALWARE && ! $AUDIT_ONLY; then
    echo ""
    warn "Malware found. Remove flagged items? (Review list above)"
    if confirm; then
        for dir in "${MALWARE_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                rm -rf "$dir"
                ok "Removed $dir"
            fi
        done
        for dir in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
            for plist in "$dir"/*.plist; do
                [[ -f "$plist" ]] || continue
                plist_lower=$(echo "$plist" | tr '[:upper:]' '[:lower:]')
                for pattern in "${SUSPECT_PATTERNS[@]}"; do
                    if echo "$plist_lower" | grep -qi "$pattern"; then
                        label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null || basename "$plist" .plist)
                        launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || \
                            launchctl unload "$plist" 2>/dev/null || true
                        if [[ "$dir" == "$HOME/"* ]]; then
                            rm -f "$plist"
                        else
                            sudo rm -f "$plist"
                        fi
                        ok "Removed $(basename "$plist")"
                        ((REMOVED++))
                    fi
                done
            done
        done
    fi
fi
fi

# ══════════════════════════════════════════════
# PHASE 3: ORPHANED LAUNCH AGENTS & DAEMONS
# ══════════════════════════════════════════════
if should_run 3; then
hdr "Phase 3: Orphaned Launch Agents & Daemons"
info "Finding agents/daemons whose executables no longer exist..."

ORPHANS=()

scan_orphans() {
    local dir="$1"
    local location="$2"
    [[ -d "$dir" ]] || return

    for plist in "$dir"/*.plist; do
        [[ -f "$plist" ]] || continue
        local exec_path
        exec_path=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null || echo "")
        if [[ -z "$exec_path" ]]; then
            exec_path=$(/usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null || echo "")
        fi

        # Skip if we can't determine executable or it's a symlink target check
        [[ -z "$exec_path" ]] && continue

        if [[ ! -e "$exec_path" ]]; then
            bad "ORPHAN ($location): $(basename "$plist")"
            log "    Missing: $exec_path"
            ORPHANS+=("$plist")
            ((FLAGGED++))
        fi
    done
}

scan_orphans "$HOME/Library/LaunchAgents" "user"
scan_orphans "/Library/LaunchAgents" "system"
scan_orphans "/Library/LaunchDaemons" "system"

if [[ ${#ORPHANS[@]} -eq 0 ]]; then
    ok "No orphaned agents/daemons found"
else
    warn "${#ORPHANS[@]} orphaned agent(s) found"
    if ! $AUDIT_ONLY; then
        echo ""
        info "Remove all orphaned agents?"
        if confirm; then
            for plist in "${ORPHANS[@]}"; do
                label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null || basename "$plist" .plist)
                if [[ "$plist" == "$HOME/"* ]]; then
                    launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || true
                    rm -f "$plist"
                else
                    sudo launchctl bootout "system/$label" 2>/dev/null || true
                    [[ "$plist" == *"/LaunchAgents/"* ]] && \
                        launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || true
                    sudo rm -f "$plist"
                fi
                ok "Removed $(basename "$plist")"
                ((REMOVED++))
            done
        fi
    fi
fi
fi

# ══════════════════════════════════════════════
# PHASE 4: KNOWN OBSOLETE SOFTWARE
# ══════════════════════════════════════════════
if should_run 4; then
hdr "Phase 4: Known Obsolete Launch Items"
info "Checking for software that is discontinued, ancient, or superseded..."

# Format: "identifier|description|location"
# location: user, system-agent, system-daemon
OBSOLETE_ITEMS=(
    # Apple legacy
    "com.apple.MobileMeSyncClientAgent|MobileMe Sync (discontinued 2012)|user"
    "com.apple.SafariBookmarksSyncer|Safari Bookmarks Syncer (MobileMe era)|user"
    # Adobe legacy
    "com.adobe.CS4ServiceManager|Adobe CS4 Service Manager (2008)|system-agent"
    "com.adobe.CS5ServiceManager|Adobe CS5 Service Manager (2010)|system-agent"
    "com.adobe.AAM.Updater-1.0|Adobe Application Manager (replaced by CC)|any"
    "com.adobe.SwitchBoard|Adobe SwitchBoard (CS-era debug tool)|system-daemon"
    "com.adobe.GC.Invoker-1.0|Adobe GC Invoker (superseded by GC.AGM)|any"
    # Citrix legacy
    "com.citrix.AuthManager_Mac|Citrix Auth Manager (legacy client)|system-agent"
    "com.citrix.ReceiverHelper|Citrix Receiver Helper (legacy client)|system-agent"
    "com.citrix.ServiceRecords|Citrix Service Records (legacy client)|system-agent"
    # Discontinued products
    "com.fitbit.galileod|Fitbit Connect (discontinued 2019)|system-daemon"
    "com.jdibackup.ZipCloud|ZipCloud (PUP)|user"
    # Java
    "com.oracle.java.Helper-Tool|Oracle Java Helper (plugins deprecated)|system-daemon"
    "com.oracle.java.Java-Updater|Oracle Java Updater (plugins deprecated)|system-agent"
    # DRM
    "com.nalpeiron.netpro|Nalpeiron DRM daemon (typically orphaned)|system-daemon"
    # Old updaters superseded by newer versions
    "com.google.keystone.agent|Google Keystone (superseded by GoogleUpdater)|user"
    "com.google.keystone.xpcservice|Google Keystone XPC (superseded by GoogleUpdater)|user"
    # Legacy Logitech
    "com.Logitech.Control Center.Daemon|Logitech Control Center (superseded by Logi Options)|system-agent"
    # EaseUS
    "com.easeus.EaseUSNotify|EaseUS notification nagware|system-agent"
    "com.easeus.ensdaemon|EaseUS notification daemon|system-daemon"
    # Old Epson
    "com.epson.epw.agent|Epson print watch agent (2009 era)|system-agent"
    "com.epson.epsvcp|Epson service plan upsell|user"
    # GoToMeeting
    "com.logmein.GoToMeeting|GoToMeeting legacy uploader|user"
)

OBSOLETE_FOUND=()

for entry in "${OBSOLETE_ITEMS[@]}"; do
    IFS='|' read -r ident desc loc <<< "$entry"

    found=false
    found_path=""

    check_dir() {
        local dir="$1"
        for plist in "$dir"/*.plist; do
            [[ -f "$plist" ]] || continue
            if basename "$plist" | grep -qi "^${ident}"; then
                found=true
                found_path="$plist"
                return
            fi
        done
    }

    case "$loc" in
        user)         check_dir "$HOME/Library/LaunchAgents" ;;
        system-agent) check_dir "/Library/LaunchAgents" ;;
        system-daemon) check_dir "/Library/LaunchDaemons" ;;
        any)
            check_dir "$HOME/Library/LaunchAgents"
            $found || check_dir "/Library/LaunchAgents"
            $found || check_dir "/Library/LaunchDaemons"
            ;;
    esac

    if $found; then
        warn "OBSOLETE: $desc"
        log "    File: $found_path"
        OBSOLETE_FOUND+=("$found_path")
        ((FLAGGED++))
    fi
done

if [[ ${#OBSOLETE_FOUND[@]} -eq 0 ]]; then
    ok "No known obsolete items found"
else
    warn "${#OBSOLETE_FOUND[@]} obsolete item(s) found"
    if ! $AUDIT_ONLY; then
        echo ""
        info "Remove all obsolete items?"
        if confirm; then
            for plist in "${OBSOLETE_FOUND[@]}"; do
                label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null || basename "$plist" .plist)
                if [[ "$plist" == "$HOME/"* ]]; then
                    launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || true
                    rm -f "$plist"
                else
                    [[ "$plist" == *"/LaunchAgents/"* ]] && \
                        launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || true
                    sudo launchctl bootout "system/$label" 2>/dev/null || true
                    sudo rm -f "$plist"
                fi
                ok "Removed $(basename "$plist")"
                ((REMOVED++))
            done
        fi
    fi
fi
fi

# ══════════════════════════════════════════════
# PHASE 5: SPOTLIGHT AUDIT
# ══════════════════════════════════════════════
if should_run 5; then
hdr "Phase 5: Spotlight Indexing Audit"
info "Checking what volumes Spotlight is indexing..."

# Get all volumes with indexing enabled
while IFS= read -r line; do
    if echo "$line" | grep -q "^/"; then
        current_vol="$line"
        current_vol="${current_vol%:}"  # Remove trailing colon
    fi
    if echo "$line" | grep -qi "Indexing enabled"; then
        # Flag Time Machine backup volumes
        if echo "$current_vol" | grep -qiE "(backupdb|Backups\.backupdb|timemachine)"; then
            bad "Spotlight indexing Time Machine backups: $current_vol"
            warn "  This causes heavy I/O and is almost never useful"
            ((FLAGGED++))
            if ! $AUDIT_ONLY; then
                echo ""
                info "Disable Spotlight on $current_vol?"
                if confirm; then
                    sudo mdutil -i off "$current_vol"
                    ok "Disabled Spotlight on $current_vol"
                fi
            fi
        else
            ok "Indexing: $current_vol"
        fi
    fi
    if echo "$line" | grep -qi "disabled"; then
        info "Disabled: $current_vol"
    fi
done < <(mdutil -a -s 2>/dev/null)

info "Spotlight workers"
MDS_CPU=$(ps aux 2>/dev/null | grep '[m]ds_stores' | awk '{total += $3} END {print total+0}')
MDW_CPU=$(ps aux 2>/dev/null | grep '[m]dworker' | awk '{total += $3} END {print total+0}')
MDS_CPU_INT=${MDS_CPU%%.*}
if [[ ${MDS_CPU_INT:-0} -gt 30 ]]; then
    warn "mds_stores CPU: ${MDS_CPU}% (actively indexing)"
else
    ok "mds_stores: ${MDS_CPU}% | mdworker: ${MDW_CPU}%"
fi
fi

# ══════════════════════════════════════════════
# PHASE 6: CACHES & TEMP FILES
# ══════════════════════════════════════════════
if should_run 6; then
hdr "Phase 6: Caches & Temp Files"

info "Calculating cache sizes..."

USER_CACHE=$(du -sh "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
info "User caches: $USER_CACHE"

SYS_CACHE=$(sudo du -sh /Library/Caches 2>/dev/null | awk '{print $1}')
info "System caches: $SYS_CACHE"

SYS_LOGS=$(sudo du -sh /private/var/log 2>/dev/null | awk '{print $1}')
info "System logs: $SYS_LOGS"

TMP_SIZE=$(sudo du -sh /private/tmp 2>/dev/null | awk '{print $1}')
info "Temp files: $TMP_SIZE"

# Find large log files
info "Large log files (>100MB):"
FOUND_LARGE=false
while IFS= read -r logfile; do
    [[ -n "$logfile" ]] || continue
    size=$(du -sh "$logfile" 2>/dev/null | awk '{print $1}')
    warn "  $size  $logfile"
    FOUND_LARGE=true
done < <(sudo find /private/var/log /Library/Logs -type f -size +100M 2>/dev/null)
if ! $FOUND_LARGE; then ok "No oversized log files"; fi

# Old iOS backups
if [[ -d "$HOME/Library/Application Support/MobileSync/Backup" ]]; then
    BACKUP_SIZE=$(du -sh "$HOME/Library/Application Support/MobileSync/Backup" 2>/dev/null | awk '{print $1}')
    BACKUP_COUNT=$(ls -1 "$HOME/Library/Application Support/MobileSync/Backup" 2>/dev/null | wc -l | xargs)
    if [[ $BACKUP_COUNT -gt 0 ]]; then
        warn "iOS device backups: $BACKUP_SIZE ($BACKUP_COUNT backup(s))"
        log "    Path: ~/Library/Application Support/MobileSync/Backup"
        log "    Manage in Finder > [device] or delete old backups manually"
    fi
fi

# Xcode derived data
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
    XCODE_SIZE=$(du -sh "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | awk '{print $1}')
    warn "Xcode DerivedData: $XCODE_SIZE"
    log "    Safe to delete: rm -rf ~/Library/Developer/Xcode/DerivedData"
fi

if ! $AUDIT_ONLY; then
    echo ""
    info "Flush system caches and purge temp files?"
    if confirm; then
        sudo periodic daily weekly monthly 2>/dev/null
        ok "Ran periodic maintenance scripts"

        # Clear user cache of known safe-to-delete items
        rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null
        ok "Cleared icon services cache"

        sudo rm -rf /private/tmp/com.apple.installer* 2>/dev/null
        ok "Cleared stale installer temp files"
    fi
fi
fi

# ══════════════════════════════════════════════
# PHASE 7: LOGIN ITEMS AUDIT
# ══════════════════════════════════════════════
if should_run 7; then
hdr "Phase 7: Login Items & Startup Programs"

info "Listing all enabled login items..."

# Modern approach: sfltool
if command -v sfltool &>/dev/null; then
    # Count enabled items for current user
    ENABLED_COUNT=$(sfltool dumpbtm 2>/dev/null | grep -c "disposition: \[enabled" || echo 0)
    info "Total enabled background items: $ENABLED_COUNT"

    # Flag items from unknown developers
    UNKNOWN_COUNT=$(sfltool dumpbtm 2>/dev/null | grep -B5 "Unknown Developer" | grep -c "Name:" || echo 0)
    if [[ $UNKNOWN_COUNT -gt 0 ]]; then
        warn "$UNKNOWN_COUNT item(s) from 'Unknown Developer'"
        info "Review in: System Settings > General > Login Items"
    else
        ok "All items from identified developers"
    fi
else
    info "sfltool not available — check Login Items in System Settings manually"
fi

# Count items in each location
USER_AGENTS=$(find "$HOME/Library/LaunchAgents" -name "*.plist" 2>/dev/null | wc -l | xargs)
SYS_AGENTS=$(find /Library/LaunchAgents -name "*.plist" 2>/dev/null | wc -l | xargs)
SYS_DAEMONS=$(find /Library/LaunchDaemons -name "*.plist" 2>/dev/null | wc -l | xargs)

info "Launch items count:"
log "    User agents:    $USER_AGENTS  (~/Library/LaunchAgents)"
log "    System agents:  $SYS_AGENTS  (/Library/LaunchAgents)"
log "    System daemons: $SYS_DAEMONS (/Library/LaunchDaemons)"
fi

# ══════════════════════════════════════════════
# PHASE 8: TOP RESOURCE CONSUMERS
# ══════════════════════════════════════════════
if should_run 8; then
hdr "Phase 8: Resource Consumers"

info "Top 10 CPU consumers:"
ps -eo pid,pcpu,pmem,comm -rc 2>/dev/null | head -11 | tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOGFILE")

echo "" | tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOGFILE")
info "Top 10 memory consumers:"
ps -eo pid,pcpu,pmem,rss,comm -rm 2>/dev/null | head -11 | tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOGFILE")

echo "" | tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOGFILE")
info "Disk I/O summary:"
iostat -c 2 -w 1 2>/dev/null | tail -1 | tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOGFILE")
fi

# ══════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════
hdr "Summary"
log ""
if $AUDIT_ONLY; then
    log "  Mode:    Audit only (no changes made)"
fi
log "  Flagged: $FLAGGED issue(s) found"
log "  Removed: $REMOVED item(s) cleaned up"
log ""
log "  Full log saved to: $LOGFILE"
log ""
if [[ $FLAGGED -gt 0 ]] && $AUDIT_ONLY; then
    log "  Run without --audit to fix flagged issues."
fi
