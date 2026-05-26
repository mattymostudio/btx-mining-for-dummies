#!/usr/bin/env bash
# Vast.ai BTX miner bootstrap — known-working version after multiple deployments.
#
# Architecture: local btxd with BTX_MATMUL_BACKEND=cuda + live-mining-supervisor.
# Mining rewards are paid to a Hetzner-controlled address so this Vast instance
# can die without losing mined BTX. Peers with Hetzner over the public internet
# (Vast Docker containers cannot run Tailscale).
#
# Required env vars (set before running):
#   BTX_REWARD_ADDRESS         — Hetzner-controlled BTX address (from cloud-node-setup.sh output)
#   BTX_HETZNER_PEER_IP        — Hetzner node's public IP (peer over port 19335)
#
# Optional env vars (with defaults):
#   BTX_CUDA_ARCH              — GPU SM arch (89=4090, 120=5090, 86=3090). Default: 89.
#   BTX_REF                    — git branch/tag. Default: main.
#
# Run inside tmux on a Vast.ai instance with:
#   - CUDA 12.4+ devel image (NVIDIA CUDA template recommended)
#   - 100 GB container disk minimum (script enforces 60 GB minimum)
#   - 5090 / 4090 / 3090 GPU
#
# Usage:
#   ssh -t -p <port> root@<vast-ip> "tmux attach -t btx || tmux new -s btx"
#   export BTX_REWARD_ADDRESS=<your-address>
#   export BTX_HETZNER_PEER_IP=<your-hetzner-public-ip>
#   bash /root/vast-miner-bootstrap.sh

set -e

: "${BTX_REWARD_ADDRESS:?must set BTX_REWARD_ADDRESS (from cloud-node-setup.sh output)}"
: "${BTX_HETZNER_PEER_IP:?must set BTX_HETZNER_PEER_IP (Hetzner node public IP)}"

BTX_CUDA_ARCH="${BTX_CUDA_ARCH:-89}"
BTX_REF="${BTX_REF:-main}"
BTX_REPO="${BTX_REPO:-https://github.com/btxchain/btx.git}"

export DEBIAN_FRONTEND=noninteractive

log() { printf '\n\033[1;36m[miner] %s\033[0m\n' "$*"; }

# === Sanity checks ===

log "CUDA toolchain check"
nvidia-smi | head -n 5 || true
nvcc --version > /dev/null 2>&1 || {
  echo "FATAL: nvcc missing. Pick a Vast template with 'cuda-devel' in name (NOT 'runtime')."
  exit 1
}
echo "nvcc: $(nvcc --version | grep -i release | head -1)"

log "Disk space guard (need 60+ GB)"
AVAIL_GB=$(df -BG /workspace 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ -z "${AVAIL_GB}" ]] || [[ "${AVAIL_GB}" -lt 60 ]]; then
  echo "FATAL: /workspace has ${AVAIL_GB:-unknown} GB free; need at least 60."
  echo "Destroy this instance and rent one with Container Size >= 100 GB."
  df -h /workspace || df -h
  exit 1
fi
echo "Disk OK: ${AVAIL_GB} GB free"

# === Build deps ===

log "Installing build deps"
apt-get update
apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config git curl ca-certificates jq \
  libboost-dev libevent-dev libsqlite3-dev \
  python3 python3-zmq

# === Build btxd with CUDA ===

log "Cloning + building btxd with CUDA backend (sm_${BTX_CUDA_ARCH})"
mkdir -p /workspace
cd /workspace
if [[ ! -d /workspace/btx ]]; then
  git clone --depth 1 --branch "${BTX_REF}" "${BTX_REPO}"
fi
cd /workspace/btx

# CUDA backend is OPT-IN — without these flags it falls back to CPU (much slower)
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DBTX_ENABLE_CUDA_EXPERIMENTAL=ON \
  -DBTX_CUDA_ARCHITECTURES="${BTX_CUDA_ARCH}" \
  -DBTX_CUDA_RUNTIME_LIBRARY=Shared
cmake --build build -j"$(nproc)"

log "Verifying CUDA backend compiled in"
/workspace/btx/build/bin/btx-matmul-backend-info --backend cuda | head -15
ldd /workspace/btx/build/bin/btxd | grep -iE 'cuda|cublas' | head -3 || {
  echo "WARNING: no CUDA libs linked into btxd. Mining will fall back to CPU."
  exit 1
}

# === Config ===

log "Writing btx.conf (peers with Hetzner + public seeds; listen=1 keeps peers stable)"
mkdir -p /workspace/.btx
cat > /workspace/.btx/btx.conf <<EOF
server=1
listen=1
dbcache=8192
maxmempool=300
maxconnections=64
addnode=${BTX_HETZNER_PEER_IP}:19335
addnode=node.btx.tools:19335
addnode=146.190.179.86:19335
addnode=164.90.246.229:19335
dnsseed=1
fixedseeds=1
EOF
chmod 600 /workspace/.btx/btx.conf

# === Start btxd ===

log "Installing btxd wrapper (CRITICAL — preserves BTX_MATMUL_BACKEND across restarts)"
# The mining supervisor STRIPS env vars when it restarts btxd. Without this
# wrapper, btxd silently falls back to CPU mining after the first chain_guard
# auto-recovery restart. See retro: see internal retrospective
mkdir -p /workspace/btx/build/bin-wrapped
cat > /workspace/btx/build/bin-wrapped/btxd <<'WRAPPER'
#!/bin/bash
# Auto-installed by vast-miner-bootstrap.sh — sets CUDA env vars then exec's real btxd.
# Supervisor points --daemon at this wrapper so restarts preserve env.
exec env BTX_MATMUL_BACKEND=cuda CUDA_VISIBLE_DEVICES=0 /workspace/btx/build/bin/btxd "$@"
WRAPPER
chmod +x /workspace/btx/build/bin-wrapped/btxd

log "Starting btxd via wrapper"
/workspace/btx/build/bin-wrapped/btxd -datadir=/workspace/.btx -daemon

log "Waiting for btxd to be RPC-ready"
for i in {1..30}; do
  if /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getblockchaininfo > /dev/null 2>&1; then
    break
  fi
  sleep 2
done
/workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getblockchaininfo | jq '.blocks, .headers'

log "Verifying CUDA env is set on running btxd"
BTXD_PID=$(pgrep btxd | head -1)
if [[ -n "$BTXD_PID" ]] && tr '\0' '\n' < /proc/$BTXD_PID/environ 2>/dev/null | grep -q '^BTX_MATMUL_BACKEND=cuda$'; then
  echo "  ✓ BTX_MATMUL_BACKEND=cuda confirmed in btxd env"
else
  echo "  ✗ FATAL: BTX_MATMUL_BACKEND not set on btxd. Wrapper failed."
  exit 1
fi

# === Mining supervisor ===

log "Launching mining supervisor (pays to ${BTX_REWARD_ADDRESS}) — --daemon=wrapper for restart-safety"
echo "${BTX_REWARD_ADDRESS}" > /workspace/.btx/reward-address.txt
export PATH=/workspace/btx/build/bin:$PATH

BTX_MINING_CLI=/workspace/btx/build/bin/btx-cli \
BTX_MINING_DAEMON=/workspace/btx/build/bin-wrapped/btxd \
nohup /workspace/btx/contrib/mining/start-live-mining.sh \
  --datadir=/workspace/.btx \
  --address-file=/workspace/.btx/reward-address.txt \
  > /workspace/.btx/mining.log 2>&1 &

MINER_PID=$!

cat <<EOF

============================================================
BTX miner setup complete.

Tail logs (will show waiting for sync, then mining attempts):
  tail -f /workspace/.btx/mining.log
  tail -f /workspace/.btx/debug.log

Live status:
  /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getmininginfo
  /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getblockchaininfo | jq '.blocks,.headers,.verificationprogress,.initialblockdownload'
  /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getconnectioncount

GPU activity (will spike when mining actually begins):
  nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw --format=csv

Mining auto-starts when:
  - Chain reaches near-tip (IBD done)
  - chain_guard.should_pause_mining becomes false
  - Peer count is sufficient

This typically takes 6-12 hours after first launch (initial chain sync).

Mining supervisor PID: ${MINER_PID}
Reward address:        ${BTX_REWARD_ADDRESS}
Hetzner peer:          ${BTX_HETZNER_PEER_IP}:19335
GPU SM arch:           sm_${BTX_CUDA_ARCH}
============================================================
EOF
