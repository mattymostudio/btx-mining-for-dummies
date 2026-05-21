#!/usr/bin/env bash
# Hetzner CX42 (Ubuntu 24.04) — BTX validating node setup.
#
# Role: always-on validating peer + wallet host. Does NOT mine.
# The Vast.ai GPU miner peers with this node and pays rewards into the
# wallet created here.
#
# Run as a non-root user with sudo, on a fresh Ubuntu 24.04 box.
# Paste-in friendly: idempotent where it can be, errors out where it can't.

set -euo pipefail

BTX_USER="${BTX_USER:-btx}"
BTX_REPO="${BTX_REPO:-https://github.com/btxchain/btx.git}"
BTX_REF="${BTX_REF:-main}"
BTX_HOME="/home/${BTX_USER}"
BTX_DATA="${BTX_HOME}/.btx"
BTX_SRC="${BTX_HOME}/btx"
WALLET_NAME="${WALLET_NAME:-miner-rewards}"

log() { printf '\n\033[1;36m[setup] %s\033[0m\n' "$*"; }
need_root() { [[ $EUID -eq 0 ]] || { echo "run with sudo or as root"; exit 1; }; }

need_root

log "Updating apt + installing build deps"
apt-get update
apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config git curl ca-certificates ufw jq \
  libboost-dev libevent-dev libsqlite3-dev \
  python3 python3-zmq python3-pip

log "Installing Tailscale"
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
echo "==> Run 'tailscale up' interactively after this script finishes; need a browser to auth."

log "Configuring UFW (allow SSH + p2p only; RPC reachable via Tailscale only)"
ufw allow 22/tcp
ufw allow 19335/tcp   # p2p
ufw --force enable

log "Creating btx user"
if ! id "${BTX_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${BTX_USER}"
fi

log "Cloning + building btxd as ${BTX_USER}"
sudo -u "${BTX_USER}" -H bash -se <<EOF
  set -euo pipefail
  cd "${BTX_HOME}"
  if [[ ! -d "${BTX_SRC}" ]]; then
    git clone --depth 1 --branch "${BTX_REF}" "${BTX_REPO}" "${BTX_SRC}"
  fi
  cd "${BTX_SRC}"
  cmake -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j"\$(nproc)"
EOF

log "Generating btx.conf"
mkdir -p "${BTX_DATA}"
chown -R "${BTX_USER}:${BTX_USER}" "${BTX_DATA}"

RPC_USER="btxrpc"
RPC_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"

cat > "${BTX_DATA}/btx.conf" <<EOF
# BTX validating node — Hetzner cloud peer
server=1
listen=1
port=19335
rpcuser=${RPC_USER}
rpcpassword=${RPC_PASS}
rpcport=19334
# Bind RPC only to localhost + Tailscale interface (configure after tailscale up)
rpcbind=127.0.0.1
# rpcbind=<tailscale-ipv4>   # ADD this line AFTER running 'tailscale up'
rpcallowip=127.0.0.0/8
rpcallowip=100.64.0.0/10     # Tailscale CGNAT range
dbcache=4096
maxmempool=300
retainshieldedcommitmentindex=1
wallet=miner-rewards
dnsseed=1
fixedseeds=1
addnode=node.btx.tools:19335
addnode=146.190.179.86:19335
addnode=164.90.246.229:19335
EOF
chown "${BTX_USER}:${BTX_USER}" "${BTX_DATA}/btx.conf"
chmod 600 "${BTX_DATA}/btx.conf"

log "Running assumeutxo fast-start (may take a while)"
sudo -u "${BTX_USER}" -H bash -se <<EOF
  set -euo pipefail
  cd "${BTX_SRC}"
  python3 contrib/faststart/btx-agent-setup.py \
    --repo btxchain/btx \
    --release-tag "${BTX_REF}" \
    --preset service \
    --datadir="${BTX_DATA}" || {
      echo "faststart agent failed — falling back to plain start (full IBD)"
    }
EOF

log "Installing systemd unit"
cat > /etc/systemd/system/btxd.service <<EOF
[Unit]
Description=BTX daemon (validating node)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=${BTX_USER}
WorkingDirectory=${BTX_HOME}
ExecStart=${BTX_SRC}/build/bin/btxd -datadir=${BTX_DATA} -printtoconsole
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable btxd.service
systemctl start btxd.service

log "Waiting 20s for btxd to come up..."
sleep 20

log "Creating reward wallet '${WALLET_NAME}' and printing receive address"
sudo -u "${BTX_USER}" -H bash -se <<EOF
  set -euo pipefail
  cd "${BTX_SRC}"
  ./build/bin/btx-cli -datadir="${BTX_DATA}" createwallet "${WALLET_NAME}" false false "" false true >/dev/null 2>&1 || true
  ./build/bin/btx-cli -datadir="${BTX_DATA}" -rpcwallet="${WALLET_NAME}" getnewaddress "mining-rewards" >/tmp/btx-reward-address
EOF

REWARD_ADDR="$(cat /tmp/btx-reward-address)"
TS_IP="$(tailscale ip -4 2>/dev/null || echo '<run tailscale up first>')"

cat <<EOF

============================================================
BTX cloud node provisioned.

Next:
  1. Run 'tailscale up' to authenticate this node to your tailnet.
  2. Append to ${BTX_DATA}/btx.conf:
       rpcbind=\$(tailscale ip -4)
     then: sudo systemctl restart btxd
  3. Wait for chain sync to near-tip:
       sudo -u ${BTX_USER} ${BTX_SRC}/build/bin/btx-cli -datadir=${BTX_DATA} getblockchaininfo | jq '.headers, .blocks, .verificationprogress'
  4. On the Vast.ai miner, set these env vars when running vast-miner-bootstrap.sh:
       BTX_HETZNER_TAILSCALE_IP=${TS_IP}
       BTX_HETZNER_RPC_USER=${RPC_USER}
       BTX_HETZNER_RPC_PASS=${RPC_PASS}
       BTX_REWARD_ADDRESS=${REWARD_ADDR}

Reward address (mining payouts land here):
  ${REWARD_ADDR}

RPC creds (Tailscale-only):
  user: ${RPC_USER}
  pass: ${RPC_PASS}
============================================================
EOF
