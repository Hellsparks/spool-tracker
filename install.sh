#!/bin/bash
# spool-tracker installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Hellsparks/spool-tracker/master/install.sh | bash

set -e

REPO_URL="https://github.com/Hellsparks/spool-tracker"
REPO_DIR="$HOME/spool-tracker"
KLIPPER_EXTRAS="$HOME/klipper/klippy/extras"
MAINSAIL_SRC="$HOME/mainsail-src"

# ── Colours ───────────────────────────────────────────────────────────────────
C_CYAN='\033[0;36m'; C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'; C_NC='\033[0m'

info() { echo -e "${C_CYAN}[spool-tracker]${C_NC} $*"; }
ok()   { echo -e "${C_GREEN}[spool-tracker]${C_NC} $*"; }
warn() { echo -e "${C_YELLOW}[spool-tracker]${C_NC} $*"; }
die()  { echo -e "${C_RED}[spool-tracker] ERROR:${C_NC} $*"; exit 1; }

# ── Find config files ─────────────────────────────────────────────────────────
find_file() {
    for f in "$@"; do [ -f "$f" ] && echo "$f" && return; done; echo ""
}

MOONRAKER_CONF=$(find_file \
    "$HOME/printer_data/config/moonraker.conf" \
    "$HOME/klipper_config/moonraker.conf")

MAINSAIL_WEB=$(find_file \
    "/var/www/mainsail/index.html" \
    "/home/pi/mainsail/index.html" \
    "/var/www/html/index.html" \
    | sed 's|/index.html||')

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${C_CYAN}╔══════════════════════════════════════╗${C_NC}"
echo -e "${C_CYAN}║        spool-tracker installer       ║${C_NC}"
echo -e "${C_CYAN}╚══════════════════════════════════════╝${C_NC}"
echo ""

# ── Preflight ─────────────────────────────────────────────────────────────────
command -v git    >/dev/null 2>&1 || die "git not found. Run: sudo apt install git"
command -v python3 >/dev/null 2>&1 || die "python3 not found. Run: sudo apt install python3"
[ -d "$HOME/klipper" ]   || die "Klipper not found at ~/klipper"
[ -d "$KLIPPER_EXTRAS" ] || die "Klipper extras dir not found"

# ── Phase 1: Clone / update this repo ────────────────────────────────────────
if [ -d "$REPO_DIR/.git" ]; then
    info "Updating spool-tracker repo..."
    git -C "$REPO_DIR" pull --ff-only
    ok "Repo updated"
else
    info "Cloning spool-tracker..."
    git clone "$REPO_URL" "$REPO_DIR"
    ok "Repo cloned to $REPO_DIR"
fi

# ── Phase 2: Klipper extra ────────────────────────────────────────────────────
info "Installing Klipper extra..."
ln -sf "$REPO_DIR/klipper/spool_tracker.py" "$KLIPPER_EXTRAS/spool_tracker.py"
ok "Klipper extra linked"

# ── Phase 3: Moonraker update_manager ────────────────────────────────────────
if [ -n "$MOONRAKER_CONF" ]; then
    if grep -q "\[update_manager spool-tracker\]" "$MOONRAKER_CONF"; then
        warn "Moonraker update_manager already present — skipping"
    else
        info "Adding update_manager entry to moonraker.conf..."
        cat >> "$MOONRAKER_CONF" << EOF

[update_manager spool-tracker]
type: git_repo
path: ~/spool-tracker
origin: ${REPO_URL}.git
primary_branch: master
install_script: install.sh
managed_services: klipper
EOF
        ok "Moonraker update_manager configured"
        warn "Restart Moonraker after install for the update panel to show up"
    fi
else
    warn "moonraker.conf not found — add [update_manager] block manually (see README)"
fi

# ── Phase 4: Mainsail source + build ─────────────────────────────────────────
info "Setting up Mainsail build..."

# Check/install Node.js
if ! command -v node >/dev/null 2>&1; then
    info "Node.js not found — installing via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

NODE_VER=$(node -v)
info "Using Node.js $NODE_VER"

# Clone Mainsail source if not present
if [ -d "$MAINSAIL_SRC/.git" ]; then
    info "Updating Mainsail source..."
    git -C "$MAINSAIL_SRC" pull --ff-only
else
    info "Cloning Mainsail source (this may take a moment)..."
    git clone https://github.com/mainsail-crew/mainsail.git "$MAINSAIL_SRC"
fi

# Copy panel component
info "Copying SpoolTrackerPanel into Mainsail source..."
cp "$REPO_DIR/mainsail/SpoolTrackerPanel.vue" \
   "$MAINSAIL_SRC/src/components/panels/SpoolTrackerPanel.vue"

# Patch Dashboard.vue and store via Python
info "Patching Mainsail source files..."
python3 << 'PYEOF'
import re, sys
from pathlib import Path

BASE = Path.home() / 'mainsail-src'

def patch(path, check, apply):
    text = path.read_text()
    if check in text:
        print(f'  skip (already patched): {path.relative_to(BASE)}')
        return
    result = apply(text)
    if result is None:
        print(f'  ERROR: could not patch {path.relative_to(BASE)}', file=sys.stderr)
        sys.exit(1)
    path.write_text(result)
    print(f'  ok: {path.relative_to(BASE)}')

# ── Dashboard.vue: add import + register component ───────────────────────────
def patch_dashboard(text):
    # 1. Insert import after the last panel import line
    import_line = "import SpoolTrackerPanel from '@/components/panels/SpoolTrackerPanel.vue'\n"
    matches = list(re.finditer(r"import \w+Panel from '@/components/panels/\w+\.vue'\n", text))
    if not matches:
        return None
    insert_at = matches[-1].end()
    text = text[:insert_at] + import_line + text[insert_at:]

    # 2. Add to components: { ... } — insert before the closing } of the decorator object
    text = re.sub(
        r'(    components: \{[^}]*?)(\n  \})',
        lambda m: m.group(1) + '\n    SpoolTrackerPanel,' + m.group(2),
        text, count=1, flags=re.DOTALL
    )
    return text

patch(BASE / 'src/pages/Dashboard.vue', 'SpoolTrackerPanel', patch_dashboard)

# ── store/gui/index.ts: add spool-tracker to every layout array ──────────────
def patch_store(text):
    entry = "        { name: 'spool-tracker', visible: true },\n"
    # Match the last { name: '...', visible: ... }, line before each array closing ],
    text = re.sub(
        r"(\s+\{ name: '[^']+', visible: (?:true|false) \},?\n)(\s+\],)",
        lambda m: m.group(1) + entry + m.group(2),
        text
    )
    return text

patch(BASE / 'src/store/gui/index.ts', 'spool-tracker', patch_store)
PYEOF

ok "Mainsail source patched"

# Build
info "Building Mainsail (npm install + npm run build)..."
cd "$MAINSAIL_SRC"
npm install --silent
npm run build

ok "Mainsail built"

# Deploy
if [ -n "$MAINSAIL_WEB" ]; then
    info "Deploying to $MAINSAIL_WEB ..."
    sudo cp -r dist/* "$MAINSAIL_WEB/"
    ok "Deployed to $MAINSAIL_WEB"
else
    warn "Could not detect Mainsail web root — copy $MAINSAIL_SRC/dist/ manually"
    warn "Common paths: /var/www/mainsail  or  ~/mainsail"
fi

# ── Phase 5: Restart services ─────────────────────────────────────────────────
info "Restarting Klipper..."
sudo systemctl restart klipper && ok "Klipper restarted" \
    || warn "Could not restart Klipper — restart manually"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
ok "Installation complete!"
echo ""
echo "  Remaining steps:"
echo "  1. Add [spool_tracker] to printer.cfg — see README for the config block"
echo "  2. Flash mcu/spool_tracker_mcu.ino to your Arduino/ESP32"
echo "  3. Restart Moonraker so the update panel entry takes effect"
echo "  4. Enable the 'Spool Tracker' panel in Mainsail → Settings → Dashboard"
echo ""
echo "  Repo: $REPO_URL"
echo ""
