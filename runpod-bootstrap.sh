#!/usr/bin/env bash
# RunPod BTX miner bootstrap.
#
# Built after burning 4 Vast instances on instability. RunPod Secure Cloud
# has 99% SLA on Tier 3/4 datacenter hosts. Use Secure Cloud, NOT Community
# Cloud (community = same P2P-rental problem as Vast).
#
# Required env vars (set before running):
#   BTX_REWARD_ADDRESS         — Hetzner-controlled BTX address (from cloud-node-setup.sh output)
#   BTX_HETZNER_PEER_IP        — Hetzner node's public IP (peer over port 19335)
#
# Optional env vars (with defaults):
#   BTX_CUDA_ARCH              — GPU SM arch (89=4090, 120=5090, 86=3090). Default: 89.
#   BTX_REF                    — git branch/tag. Default: main.
#   USE_PRESET_MINER           — Use pruned miner preset (default: 1 — saves ~80% disk)
#
# Run inside a RunPod pod with:
#   - "Secure Cloud" filter ON (NOT Community Cloud)
#   - Template: NVIDIA CUDA (any 12.4+ devel image)
#   - Container Disk: 50 GB (with --preset miner; 100 GB for full node)
#   - Network Volume: optional but recommended (survives pod restart)
#   - GPU: RTX 4090, 5090, or 3090
#
# Usage:
#   ssh root@<pod-ip> -p <port>
#   export BTX_REWARD_ADDRESS=<your-address>
#   export BTX_HETZNER_PEER_IP=<your-hetzner-public-ip>
#   bash /root/runpod-bootstrap.sh

set -e

: "${BTX_REWARD_ADDRESS:?must set BTX_REWARD_ADDRESS (from cloud-node-setup.sh output)}"
: "${BTX_HETZNER_PEER_IP:?must set BTX_HETZNER_PEER_IP (Hetzner node public IP)}"

BTX_CUDA_ARCH="${BTX_CUDA_ARCH:-89}"
BTX_REF="${BTX_REF:-main}"
BTX_REPO="${BTX_REPO:-https://github.com/btxchain/btx.git}"
USE_PRESET_MINER="${USE_PRESET_MINER:-1}"

export DEBIAN_FRONTEND=noninteractive

log() { printf '\n\033[1;36m[runpod] %s\033[0m\n' "$*"; }

log "CUDA toolchain check"
nvidia-smi | head -n 5 || true
nvcc --version > /dev/null 2>&1 || {
  echo "FATAL: nvcc missing. Pick a RunPod template with 'cuda-devel' in name."
  echo "Good options: 'PyTorch (cuda:12.4-cudnn-devel-ubuntu22.04)' or 'NVIDIA CUDA'"
  exit 1
}
echo "nvcc: $(nvcc --version | grep -i release | head -1)"

log "Disk space guard"
MIN_GB=20
if [[ "${USE_PRESET_MINER}" != "1" ]]; then
  MIN_GB=60
fi
AVAIL_GB=$(df -BG /workspace 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ -z "${AVAIL_GB}" ]] || [[ "${AVAIL_GB}" -lt "${MIN_GB}" ]]; then
  echo "FATAL: /workspace has ${AVAIL_GB:-unknown} GB free; need at least ${MIN_GB}."
  df -h /workspace || df -h
  exit 1
fi
echo "Disk OK: ${AVAIL_GB} GB free"

log "Installing build deps"
apt-get update
apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config git curl ca-certificates jq \
  libboost-dev libevent-dev libsqlite3-dev \
  python3 python3-zmq

log "Cloning + building btxd with CUDA backend (sm_${BTX_CUDA_ARCH})"
mkdir -p /workspace
cd /workspace
if [[ ! -d /workspace/btx ]]; then
  git clone --depth 1 --branch "${BTX_REF}" "${BTX_REPO}"
fi
cd /workspace/btx

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

if [[ "${USE_PRESET_MINER}" == "1" ]]; then
  log "Running faststart agent with --preset miner (pruned — saves ~80% disk)"
  mkdir -p /workspace/.btx
  if [[ -f /workspace/btx/contrib/faststart/btx-agent-setup.py ]]; then
    mkdir -p /root/.gnupg && chmod 700 /root/.gnupg
    curl -fsSL https://github.com/btxchain/btx/releases/download/v0.30.0/BTX-RELEASE-PUBKEY.asc -o /tmp/btx-pubkey.asc 2>/dev/null
    gpg --import /tmp/btx-pubkey.asc 2>/dev/null || true

    python3 /workspace/btx/contrib/faststart/btx-agent-setup.py \
      --repo btxchain/btx \
      --release-tag v0.30.0 \
      --preset miner \
      --datadir=/workspace/.btx 2>&1 | tail -20 || {
        echo "[runpod] Faststart failed — falling back to plain IBD with prune"
    }
  fi
fi

log "Writing btx.conf"
mkdir -p /workspace/.btx
cat > /workspace/.btx/btx.conf <<EOF
server=1
listen=1
dbcache=8192
maxmempool=300
maxconnections=64
$([[ "${USE_PRESET_MINER}" == "1" ]] && echo "prune=5000")
addnode=${BTX_HETZNER_PEER_IP}:19335
addnode=node.btx.tools:19335
addnode=146.190.179.86:19335
addnode=164.90.246.229:19335
dnsseed=1
fixedseeds=1
EOF
chmod 600 /workspace/.btx/btx.conf

log "Installing btxd wrapper (CRITICAL — preserves BTX_MATMUL_BACKEND across restarts)"
# The mining supervisor STRIPS env vars when it restarts btxd. Without this
# wrapper, btxd silently falls back to CPU mining after the first chain_guard
# auto-recovery restart. See internal retrospective for full incident timeline.
mkdir -p /workspace/btx/build/bin-wrapped
cat > /workspace/btx/build/bin-wrapped/btxd <<'WRAPPER'
#!/bin/bash
# Auto-installed by runpod-bootstrap.sh — sets CUDA env vars then exec's real btxd.
# Supervisor points --daemon at this wrapper so restarts preserve env.
exec env BTX_MATMUL_BACKEND=cuda CUDA_VISIBLE_DEVICES=0 /workspace/btx/build/bin/btxd "$@"
WRAPPER
chmod +x /workspace/btx/build/bin-wrapped/btxd

log "Starting btxd via wrapper"
/workspace/btx/build/bin-wrapped/btxd -datadir=/workspace/.btx -daemon

log "Waiting for btxd to be RPC-ready (up to 60s)"
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
  echo "  ✓ BTX_MATMUL_BACKEND=cuda confirmed in btxd env (PID $BTXD_PID)"
else
  echo "  ✗ FATAL: BTX_MATMUL_BACKEND not set on btxd. Wrapper failed."
  echo "  Manual recovery: kill btxd, then: /workspace/btx/build/bin-wrapped/btxd -daemon -datadir=/workspace/.btx"
  exit 1
fi

log "Launching live-mining-loop directly (skips wallet auto-provisioning) with --sleep=0.2"
# We call live-mining-loop.sh DIRECTLY instead of start-live-mining.sh because
# start-live-mining.sh provisions a local "miner" wallet on the pod and
# OVERWRITES reward-address.txt with that local address — defeating our goal of
# paying rewards to a Hetzner-controlled wallet. Calling the inner loop with an
# explicit --address lets us bypass that.
#
# --sleep=0.2 (vs the default --sleep=1.0) keeps GPU duty cycle near 100%.
# At sleep=1.0 the GPU spends ~80% of its time idle between hash batches,
# capping effective hashrate at ~17% of the card's benchmark capability.
echo "${BTX_REWARD_ADDRESS}" > /workspace/.btx/reward-address.txt
export PATH=/workspace/btx/build/bin:$PATH
mkdir -p /workspace/.btx/mining-ops

BTX_MATMUL_BACKEND=cuda \
CUDA_VISIBLE_DEVICES=0 \
nohup /workspace/btx/contrib/mining/live-mining-loop.sh \
  --datadir=/workspace/.btx \
  --cli=/workspace/btx/build/bin/btx-cli \
  --daemon=/workspace/btx/build/bin-wrapped/btxd \
  --results-dir=/workspace/.btx/mining-ops \
  --address="${BTX_REWARD_ADDRESS}" \
  --address-file=/workspace/.btx/reward-address.txt \
  --sleep=0.2 \
  > /workspace/.btx/mining.log 2>&1 &

MINER_PID=$!

cat <<EOF

============================================================
BTX miner setup complete on RunPod.

Tail logs:
  tail -f /workspace/.btx/mining.log
  tail -f /workspace/.btx/debug.log

Live status:
  /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getmininginfo
  /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getblockchaininfo | jq '.blocks,.headers,.verificationprogress,.initialblockdownload'
  /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getconnectioncount

GPU activity:
  nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw --format=csv

Mining supervisor PID: ${MINER_PID}
Reward address:        ${BTX_REWARD_ADDRESS}
Hetzner peer:          ${BTX_HETZNER_PEER_IP}:19335
GPU SM arch:           sm_${BTX_CUDA_ARCH}
Disk preset:           $([[ "${USE_PRESET_MINER}" == "1" ]] && echo "miner (pruned, ~5-10GB)" || echo "service (full, ~50GB)")
============================================================

RunPod-specific notes:
  - Network Volume = data survives pod stop/start (vs container disk = data dies on stop)
  - SSH port may change after pod restart — note new details from RunPod console
  - "Stop" pod pauses billing on GPU but keeps container; "Terminate" destroys everything
  - Secure Cloud is the reliable tier; Community Cloud is variable (avoid for sustained mining)

VERIFICATION CHECKLIST (run within 30 min after mining starts):

  # 1. GPU power must be sustained > 200W (idle is ~70W, mining is ~400-500W)
  nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv,noheader

  # 2. btxd env MUST include BTX_MATMUL_BACKEND=cuda
  tr '\\0' '\\n' < /proc/\$(pgrep btxd)/environ | grep BTX_MATMUL

  # 3. Supervisor's --daemon flag MUST point at the wrapper, not the bare btxd
  ps -o cmd= -p \$(pgrep -f live-mining-loop) | tr ' ' '\\n' | grep daemon=
  # Expected: --daemon=/workspace/btx/build/bin-wrapped/btxd

If GPU stays at ~70W for > 5 min after IBD completes:
  - btxd is running on CPU. Kill + restart via wrapper:
      /workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx stop
      sleep 3
      /workspace/btx/build/bin-wrapped/btxd -daemon -datadir=/workspace/.btx
  - Then verify step 2 again.
EOF
