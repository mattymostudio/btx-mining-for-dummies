#!/usr/bin/env bash
# BTX mining dashboard — sanity check accumulation vs spend.
#
# Usage:
#   bash dashboard.sh              # one-shot
#   watch -n 30 -c 'bash dashboard.sh'   # auto-refresh every 30s
#
# Reads config from $HOME/.btx-dashboard.conf if present, else uses defaults
# below. Edit the conf file when your cloud miner's host/port changes.

CONFIG="${HOME}/.btx-dashboard.conf"
if [[ -f "${CONFIG}" ]]; then
  source "${CONFIG}"
fi

# Defaults — REQUIRE override in ~/.btx-dashboard.conf
# Create that file with your own values; see README for example.
# VAST_* names are historical; the cloud miner is whatever provider VAST_PROVIDER names.
VAST_PROVIDER="${VAST_PROVIDER:-Cloud}"
VAST_HOST="${VAST_HOST:-PLACEHOLDER_VAST_IP}"
VAST_PORT="${VAST_PORT:-22}"
VAST_SSH_KEY="${VAST_SSH_KEY:-}"                     # path to identity file; empty = default agent
VAST_HOURLY_RATE="${VAST_HOURLY_RATE:-0.50}"
VAST_START_EPOCH="${VAST_START_EPOCH:-$(date +%s)}"

HETZNER_HOST="${HETZNER_HOST:-PLACEHOLDER_HETZNER_IP}"
HETZNER_MONTHLY_RATE="${HETZNER_MONTHLY_RATE:-46.49}"
HETZNER_START_EPOCH="${HETZNER_START_EPOCH:-$(date +%s)}"

BTX_BLOCK_REWARD="${BTX_BLOCK_REWARD:-20}"
NETWORK_TIP_HEIGHT="${NETWORK_TIP_HEIGHT:-110000}"   # update manually as chain grows

# Sanity check
if [[ "${VAST_HOST}" == "PLACEHOLDER_VAST_IP" ]] || [[ "${HETZNER_HOST}" == "PLACEHOLDER_HETZNER_IP" ]]; then
  echo "Error: dashboard.sh needs your VAST_HOST/PORT and HETZNER_HOST configured."
  echo "Create ~/.btx-dashboard.conf with your values. See README for example."
  exit 1
fi

# === SSH calls (with short timeout so dashboard never hangs) ===
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"

vast_query() {
  ssh ${SSH_OPTS} ${VAST_SSH_KEY:+-i "${VAST_SSH_KEY}"} -p "${VAST_PORT}" "root@${VAST_HOST}" "$1" 2>/dev/null
}

hetzner_query() {
  ssh ${SSH_OPTS} "root@${HETZNER_HOST}" "$1" 2>/dev/null
}

# === Fetch state ===
NOW_EPOCH=$(date +%s)
VAST_UPTIME_HRS=$(awk -v a="${NOW_EPOCH}" -v b="${VAST_START_EPOCH}" 'BEGIN{printf "%.2f", (a-b)/3600}')
HETZNER_UPTIME_HRS=$(awk -v a="${NOW_EPOCH}" -v b="${HETZNER_START_EPOCH}" 'BEGIN{printf "%.2f", (a-b)/3600}')

VAST_SPEND=$(awk -v h="${VAST_UPTIME_HRS}" -v r="${VAST_HOURLY_RATE}" 'BEGIN{printf "%.2f", h*r}')
HETZNER_SPEND=$(awk -v h="${HETZNER_UPTIME_HRS}" -v r="${HETZNER_MONTHLY_RATE}" 'BEGIN{printf "%.2f", (h/720)*r}')
TOTAL_SPEND=$(awk -v a="${VAST_SPEND}" -v b="${HETZNER_SPEND}" 'BEGIN{printf "%.2f", a+b}')

# Vast state
VAST_JSON=$(vast_query "/workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getblockchaininfo 2>/dev/null && /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getconnectioncount 2>/dev/null && nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw --format=csv,noheader,nounits 2>/dev/null")
VAST_BLOCKS=$(echo "${VAST_JSON}" | jq -r '.blocks // 0' 2>/dev/null | head -1)
VAST_HEADERS=$(echo "${VAST_JSON}" | jq -r '.headers // 0' 2>/dev/null | head -1)
VAST_IBD=$(echo "${VAST_JSON}" | jq -r 'if has("initialblockdownload") then (.initialblockdownload | tostring) else "true" end' 2>/dev/null | head -1)
VAST_PROGRESS=$(echo "${VAST_JSON}" | jq -r '.verificationprogress // 0' 2>/dev/null | head -1)
VAST_PEERS=$(echo "${VAST_JSON}" | grep -oE '^[0-9]+$' | head -1)
VAST_GPU=$(echo "${VAST_JSON}" | grep -E '^[0-9]+, [0-9]+, [0-9]+' | head -1)

# Hetzner state
HET_RESULT=$(hetzner_query "sudo -u btx /home/btx/btx/build/bin/btx-cli -datadir=/home/btx/.btx getblockchaininfo 2>/dev/null; sudo -u btx /home/btx/btx/build/bin/btx-cli -datadir=/home/btx/.btx getconnectioncount 2>/dev/null; sudo -u btx /home/btx/btx/build/bin/btx-cli -datadir=/home/btx/.btx -rpcwallet=miner-rewards getbalance 2>/dev/null")
HET_BLOCKS=$(echo "${HET_RESULT}" | jq -r '.blocks // 0' 2>/dev/null | head -1)
HET_HEADERS=$(echo "${HET_RESULT}" | jq -r '.headers // 0' 2>/dev/null | head -1)
HET_PROGRESS=$(echo "${HET_RESULT}" | jq -r '.verificationprogress // 0' 2>/dev/null | head -1)
HET_BALANCE=$(echo "${HET_RESULT}" | grep -E '^[0-9]+\.[0-9]+$' | head -1)
HET_PEERS=$(echo "${HET_RESULT}" | grep -oE '^[0-9]+$' | head -1)

# Derived
BLOCKS_FOUND=$(awk -v b="${HET_BALANCE:-0}" -v r="${BTX_BLOCK_REWARD}" 'BEGIN{printf "%d", b/r}')
IMPLIED_PRICE="—"
if [[ "${HET_BALANCE:-0}" != "0" ]] && [[ "${HET_BALANCE:-0}" != "0.00000000" ]]; then
  IMPLIED_PRICE=$(awk -v s="${TOTAL_SPEND}" -v b="${HET_BALANCE}" 'BEGIN{printf "$%.4f", s/b}')
fi

# === Fetch btxprice.com model price (5s timeout, fail silent) ===
PRICE_JSON=$(curl -sL --max-time 5 https://btxprice.com/api/current.json 2>/dev/null)
MODEL_SPOT=$(echo "${PRICE_JSON}" | jq -r '.forward[] | select(.months==0) | .usd' 2>/dev/null | awk '{printf "%.4f", $1}')
MODEL_12M=$(echo "${PRICE_JSON}" | jq -r '.forward[] | select(.months==12) | .usd' 2>/dev/null | awk '{printf "%.2f", $1}')
NETWORK_TIP=$(echo "${PRICE_JSON}" | jq -r '.inputs.btx_block_height' 2>/dev/null)
BTC_PRICE=$(echo "${PRICE_JSON}" | jq -r '.inputs.btc_price_usd' 2>/dev/null | awk '{printf "%.0f", $1}')
[[ -z "${MODEL_SPOT}" ]] && MODEL_SPOT="—" && MODEL_12M="—" && NETWORK_TIP="?"

# Implied USD values
if [[ "${HET_BALANCE:-0}" != "0" ]] && [[ "${HET_BALANCE:-0}" != "0.00000000" ]] && [[ "${MODEL_SPOT}" != "—" ]]; then
  WALLET_USD_NOW=$(awk -v b="${HET_BALANCE}" -v p="${MODEL_SPOT}" 'BEGIN{printf "$%.2f", b*p}')
  WALLET_USD_12M=$(awk -v b="${HET_BALANCE}" -v p="${MODEL_12M}" 'BEGIN{printf "$%.2f", b*p}')
else
  WALLET_USD_NOW="\$0.00"
  WALLET_USD_12M="\$0.00"
fi

# BTX needed to break even
if [[ "${MODEL_SPOT}" != "—" ]] && [[ "${MODEL_SPOT}" != "0.0000" ]]; then
  BTX_TO_BE_SPOT=$(awk -v s="${TOTAL_SPEND}" -v p="${MODEL_SPOT}" 'BEGIN{printf "%.2f", s/p}')
  BTX_TO_BE_12M=$(awk -v s="${TOTAL_SPEND}" -v p="${MODEL_12M}" 'BEGIN{printf "%.4f", s/p}')
else
  BTX_TO_BE_SPOT="—"
  BTX_TO_BE_12M="—"
fi

# === Render ===
clear 2>/dev/null
TS=$(date "+%Y-%m-%d %H:%M:%S %Z")

cat <<EOF
╔════════════════════════════════════════════════════════════════════╗
║                     BTX MINING DASHBOARD                           ║
║                     ${TS}                              ║
╠════════════════════════════════════════════════════════════════════╣
║ MINING (${VAST_PROVIDER} ${VAST_GPU_LABEL:-GPU}, ${VAST_HOST}:${VAST_PORT})
║   Sync          : ${VAST_BLOCKS:-?} / ${VAST_HEADERS:-?} blocks ($(awk -v p="${VAST_PROGRESS:-0}" 'BEGIN{printf "%.1f%%", p*100}'))
║   IBD active    : ${VAST_IBD}
║   Peers         : ${VAST_PEERS:-?}
║   GPU (util/MB/W): ${VAST_GPU:-no data}
╠════════════════════════════════════════════════════════════════════╣
║ WALLET (Hetzner, ${HETZNER_HOST})
║   Sync          : ${HET_BLOCKS:-?} / ${HET_HEADERS:-?} blocks ($(awk -v p="${HET_PROGRESS:-0}" 'BEGIN{printf "%.1f%%", p*100}'))
║   Balance       : ${HET_BALANCE:-not loaded} BTX
║   Blocks found  : ${BLOCKS_FOUND:-0}  (balance ÷ ${BTX_BLOCK_REWARD} BTX/block reward)
║   Peers         : ${HET_PEERS:-?}
╠════════════════════════════════════════════════════════════════════╣
║ SPEND (since ${VAST_START_EPOCH} / ${HETZNER_START_EPOCH})
║   ${VAST_PROVIDER} uptime : ${VAST_UPTIME_HRS} hrs  @ \$${VAST_HOURLY_RATE}/hr  →  \$${VAST_SPEND}
║   Hetzner       : ${HETZNER_UPTIME_HRS} hrs  @ \$${HETZNER_MONTHLY_RATE}/mo  →  \$${HETZNER_SPEND}
║   TOTAL SPEND   : \$${TOTAL_SPEND}
╠════════════════════════════════════════════════════════════════════╣
║ PRICE MODEL (btxprice.com — not market price)
║   Spot           : \$${MODEL_SPOT}/BTX
║   12-month proj  : \$${MODEL_12M}/BTX  (BTC ref: \$${BTC_PRICE})
║   Network tip    : ${NETWORK_TIP} blocks
║
║ WALLET VALUE (balance × model price)
║   Now            : ${WALLET_USD_NOW}
║   12-month       : ${WALLET_USD_12M}
║
║ BREAK-EVEN
║   To break even today    : ${BTX_TO_BE_SPOT} BTX  (at \$${MODEL_SPOT}/BTX)
║   To break even @ 12m    : ${BTX_TO_BE_12M} BTX  (at \$${MODEL_12M}/BTX)
║   Cost-per-BTX-mined     : ${IMPLIED_PRICE}
║   60-day cloud projection: \$$(awk -v vr="${VAST_HOURLY_RATE}" -v hm="${HETZNER_MONTHLY_RATE}" 'BEGIN{printf "%.0f", vr*24*60 + hm*2}')
╚════════════════════════════════════════════════════════════════════╝
EOF

# Status indicators
STATUS_LINE=""
[[ "${VAST_IBD}" == "false" ]] && STATUS_LINE="${STATUS_LINE}🟢 ${VAST_PROVIDER}: synced  " || STATUS_LINE="${STATUS_LINE}🟡 ${VAST_PROVIDER}: syncing  "
[[ "${HET_BALANCE:-0}" != "0.00000000" ]] && [[ -n "${HET_BALANCE}" ]] && STATUS_LINE="${STATUS_LINE}🟢 Earning  " || STATUS_LINE="${STATUS_LINE}⚪ No rewards yet  "

# CPU-vs-GPU mode badge — use GPU memory as the signal (binary, stable)
# When mining via CUDA: ~687 MB loaded. CPU mode: 0 MB. Power fluctuates between
# hash cycles so memory is the cleaner indicator. See retro for full context.
GPU_MEM=$(echo "${VAST_GPU:-0, 0, 0}" | awk -F', ' '{print $2+0}')
GPU_WATTS=$(echo "${VAST_GPU:-0, 0, 0}" | awk -F', ' '{print $3+0}')
if [[ "${VAST_IBD}" == "true" ]]; then
  STATUS_LINE="${STATUS_LINE}⏳ Mode: IBD (idle expected)  "
elif (( $(awk -v m="${GPU_MEM:-0}" 'BEGIN{print (m>100)}') )); then
  STATUS_LINE="${STATUS_LINE}🟢 Mode: GPU (${GPU_MEM}MB / ${GPU_WATTS}W)  "
elif [[ -n "${VAST_GPU}" ]]; then
  STATUS_LINE="${STATUS_LINE}🔴 Mode: CPU-FALLBACK? (mem=${GPU_MEM}MB) — see retro  "
fi

echo
echo "Status: ${STATUS_LINE}"
echo "Refresh: bash ${0}    Auto: watch -n 30 -c 'bash ${0}'"
