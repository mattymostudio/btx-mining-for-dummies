#!/usr/bin/env bash
# Garage rig setup — owned 5090 (or 4090) running Ubuntu Server 24.04.
#
# Prereq: Ubuntu Server 24.04 LTS freshly installed, you're SSH'd in or at
# the console as a sudo-capable user (not root). The script will use sudo as
# needed.
#
# Pay-to-Hetzner pattern: by default the mined coinbase rewards are paid to the
# Hetzner-controlled address (consistent with Vast setup). To use a local wallet
# on this rig instead, see the "LOCAL WALLET" section near the bottom.
#
# Required env vars (or edit the defaults below):
#   BTX_REWARD_ADDRESS         — where mining rewards go (default: Hetzner address)
#   BTX_CUDA_ARCH              — GPU SM arch (89=4090, 120=5090)
#   BTX_HETZNER_PEER_IP        — Hetzner public IP for peering
#
# Optional:
#   ENABLE_TAILSCALE=1         — install + join Tailscale for private SSH
#   TS_AUTHKEY=tskey-auth-...  — required if ENABLE_TAILSCALE=1
#   BTX_USER=btx               — username for the daemon (created if missing)

set -euo pipefail

# === REQUIRED env vars (no defaults — script will fail if unset) ===
: "${BTX_REWARD_ADDRESS:?must set BTX reward address (from your cloud-node-setup.sh output)}"
: "${BTX_HETZNER_PEER_IP:?must set Hetzner peer IP (your wallet-node public IP)}"

# === Optional with defaults ===
BTX_CUDA_ARCH="${BTX_CUDA_ARCH:-120}"     # 5090=120, 4090=89, 3090=86
BTX_USER="${BTX_USER:-btx}"
BTX_REPO="${BTX_REPO:-https://github.com/btxchain/btx.git}"
BTX_REF="${BTX_REF:-main}"
ENABLE_TAILSCALE="${ENABLE_TAILSCALE:-0}"

BTX_HOME="/home/${BTX_USER}"
BTX_DATA="${BTX_HOME}/.btx"
BTX_SRC="${BTX_HOME}/btx"

log() { printf '\n\033[1;36m[garage] %s\033[0m\n' "$*"; }
need_root() { [[ $EUID -eq 0 ]] || { echo "rerun with: sudo bash $0"; exit 1; }; }
need_root

# === Sanity checks ===
# This script assumes NVIDIA driver + CUDA toolkit are ALREADY installed.
# It does not install them itself because: (a) driver/CUDA version pinning
# varies by distro + when you read this, (b) those installs sometimes need
# manual review (e.g., DKMS issues, kernel module signing, secure boot).
#
# To install BEFORE running this script:
#
#   # 1. NVIDIA driver (use latest available in your distro)
#   sudo apt install ubuntu-drivers-common
#   sudo ubuntu-drivers autoinstall
#   sudo reboot
#
#   # 2. CUDA toolkit (visit https://developer.nvidia.com/cuda-downloads for current install)
#   # For Ubuntu 24.04 with CUDA 12.6+ (typical as of 2026):
#   wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
#   sudo dpkg -i cuda-keyring_1.1-1_all.deb
#   sudo apt-get update
#   sudo apt-get -y install cuda-toolkit-12-6
#
#   # 3. Verify both work
#   nvidia-smi    # should show GPU + driver version
#   /usr/local/cuda/bin/nvcc --version    # should show CUDA version
#
# Then run THIS script.

log "Verifying NVIDIA driver"
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "FATAL: nvidia-smi not found. Install NVIDIA driver first."
  echo "See the docstring at the top of this script for install steps."
  exit 1
fi
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader

log "Verifying CUDA toolkit"
# nvcc may be at /usr/local/cuda/bin/nvcc but not on PATH yet
if ! command -v nvcc >/dev/null 2>&1; then
  if [[ -x /usr/local/cuda/bin/nvcc ]]; then
    echo 'export PATH=/usr/local/cuda/bin:$PATH' > /etc/profile.d/cuda.sh
    export PATH=/usr/local/cuda/bin:$PATH
  else
    echo "FATAL: nvcc not found. Install CUDA toolkit first."
    echo "See the docstring at the top of this script for install steps."
    exit 1
  fi
fi
nvcc --version | tail -1

log "Installing build deps + utilities"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config git curl ca-certificates ufw jq \
  libboost-dev libevent-dev libsqlite3-dev \
  python3 python3-zmq python3-pip \
  htop tmux smartmontools

log "Configuring UFW (allow SSH + p2p; optionally Tailscale)"
ufw allow 22/tcp
ufw allow 19335/tcp   # btxd p2p — if your home router does port forwarding, expose this to internet for inbound peers
ufw --force enable

log "Creating ${BTX_USER} user"
if ! id "${BTX_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${BTX_USER}"
fi
usermod -aG video "${BTX_USER}"   # GPU access

if [[ "${ENABLE_TAILSCALE}" == "1" ]]; then
  log "Installing Tailscale"
  if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  if [[ -n "${TS_AUTHKEY:-}" ]]; then
    tailscale up --authkey="${TS_AUTHKEY}" --hostname="btx-garage" --ssh
  else
    echo "Run 'tailscale up' interactively after script finishes"
  fi
fi

log "Cloning + building btxd with CUDA backend (sm_${BTX_CUDA_ARCH})"
sudo -u "${BTX_USER}" -H bash -se <<EOF
  set -euo pipefail
  cd "${BTX_HOME}"
  if [[ ! -d "${BTX_SRC}" ]]; then
    git clone --depth 1 --branch "${BTX_REF}" "${BTX_REPO}" "${BTX_SRC}"
  fi
  cd "${BTX_SRC}"
  cmake -B build -DCMAKE_BUILD_TYPE=Release \
    -DBTX_ENABLE_CUDA_EXPERIMENTAL=ON \
    -DBTX_CUDA_ARCHITECTURES=${BTX_CUDA_ARCH} \
    -DBTX_CUDA_RUNTIME_LIBRARY=Shared
  cmake --build build -j"\$(nproc)"
EOF

log "Installing btxd wrapper (CRITICAL — preserves BTX_MATMUL_BACKEND across supervisor restarts)"
# The mining supervisor STRIPS env vars when it restarts btxd. Without this
# wrapper, btxd silently falls back to CPU mining after the first chain_guard
# auto-recovery restart. See internal retrospective for full incident timeline.
sudo -u "${BTX_USER}" mkdir -p "${BTX_SRC}/build/bin-wrapped"
sudo tee "${BTX_SRC}/build/bin-wrapped/btxd" >/dev/null <<WRAPPER
#!/bin/bash
# Auto-installed by garage-rig-setup.sh — sets CUDA env vars then exec's real btxd.
# Both systemd and supervisor point --daemon at this wrapper so restarts preserve env.
exec env BTX_MATMUL_BACKEND=cuda CUDA_VISIBLE_DEVICES=0 "${BTX_SRC}/build/bin/btxd" "\$@"
WRAPPER
sudo chmod +x "${BTX_SRC}/build/bin-wrapped/btxd"
sudo chown "${BTX_USER}:${BTX_USER}" "${BTX_SRC}/build/bin-wrapped/btxd"

log "Verifying CUDA backend compiled"
sudo -u "${BTX_USER}" "${BTX_SRC}/build/bin/btx-matmul-backend-info" --backend cuda | head -15

log "Writing btx.conf"
mkdir -p "${BTX_DATA}"
chown -R "${BTX_USER}:${BTX_USER}" "${BTX_DATA}"

RPC_USER="btxrpc"
RPC_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"

cat > "${BTX_DATA}/btx.conf" <<EOF
# BTX garage mining rig
server=1
listen=1
port=19335
rpcuser=${RPC_USER}
rpcpassword=${RPC_PASS}
rpcport=19334
rpcbind=127.0.0.1
rpcallowip=127.0.0.0/8
dbcache=8192
maxmempool=300
maxconnections=64
retainshieldedcommitmentindex=1
# Peer with Hetzner cloud node + public seeds
addnode=${BTX_HETZNER_PEER_IP}:19335
addnode=node.btx.tools:19335
addnode=146.190.179.86:19335
addnode=164.90.246.229:19335
dnsseed=1
fixedseeds=1
EOF
chown "${BTX_USER}:${BTX_USER}" "${BTX_DATA}/btx.conf"
chmod 600 "${BTX_DATA}/btx.conf"

log "Installing systemd unit for btxd (mining-enabled)"
cat > /etc/systemd/system/btxd.service <<EOF
[Unit]
Description=BTX daemon (garage mining rig)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${BTX_USER}
Environment="BTX_MATMUL_BACKEND=cuda"
Environment="CUDA_VISIBLE_DEVICES=0"
WorkingDirectory=${BTX_HOME}
# ExecStart points at wrapper for defense-in-depth — even if systemd env is bypassed,
# the wrapper sets BTX_MATMUL_BACKEND=cuda before exec'ing btxd.
ExecStart=${BTX_SRC}/build/bin-wrapped/btxd -datadir=${BTX_DATA} -printtoconsole
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

log "Installing systemd unit for live-mining-supervisor"
echo "${BTX_REWARD_ADDRESS}" > "${BTX_DATA}/reward-address.txt"
chown "${BTX_USER}:${BTX_USER}" "${BTX_DATA}/reward-address.txt"

mkdir -p "${BTX_DATA}/mining-ops"
chown "${BTX_USER}:${BTX_USER}" "${BTX_DATA}/mining-ops"

# We call live-mining-loop.sh DIRECTLY instead of start-live-mining.sh.
# start-live-mining.sh auto-provisions a local wallet and overwrites
# reward-address.txt with its address, breaking the "pay to remote wallet"
# pattern. The inner loop accepts --address= so we can be explicit.
# --sleep=0.2 keeps the GPU duty cycle near 100% (default is 1.0).
cat > /etc/systemd/system/btx-miner.service <<EOF
[Unit]
Description=BTX mining loop (pays to ${BTX_REWARD_ADDRESS})
After=btxd.service
Requires=btxd.service

[Service]
Type=simple
User=${BTX_USER}
Environment="BTX_MATMUL_BACKEND=cuda"
Environment="CUDA_VISIBLE_DEVICES=0"
WorkingDirectory=${BTX_SRC}
ExecStart=${BTX_SRC}/contrib/mining/live-mining-loop.sh \\
  --datadir=${BTX_DATA} \\
  --cli=${BTX_SRC}/build/bin/btx-cli \\
  --daemon=${BTX_SRC}/build/bin-wrapped/btxd \\
  --results-dir=${BTX_DATA}/mining-ops \\
  --address=${BTX_REWARD_ADDRESS} \\
  --address-file=${BTX_DATA}/reward-address.txt \\
  --sleep=0.2
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable btxd.service btx-miner.service
systemctl start btxd.service
sleep 15
systemctl start btx-miner.service
sleep 5

log "Status:"
systemctl is-active btxd.service btx-miner.service
sudo -u "${BTX_USER}" "${BTX_SRC}/build/bin/btx-cli" -datadir="${BTX_DATA}" getblockchaininfo | jq '.blocks, .headers, .verificationprogress'

cat <<EOF

============================================================
GARAGE RIG MINING SETUP COMPLETE.

Mining: pays to ${BTX_REWARD_ADDRESS}
GPU:    sm_${BTX_CUDA_ARCH}
Datadir: ${BTX_DATA}

Manage:
  sudo systemctl status btxd btx-miner
  sudo systemctl restart btxd     # restart daemon
  sudo journalctl -u btxd -f      # follow daemon logs
  sudo journalctl -u btx-miner -f # follow mining supervisor logs

Query:
  sudo -u ${BTX_USER} ${BTX_SRC}/build/bin/btx-cli -datadir=${BTX_DATA} getblockchaininfo
  sudo -u ${BTX_USER} ${BTX_SRC}/build/bin/btx-cli -datadir=${BTX_DATA} getmininginfo

GPU:
  nvidia-smi   # GPU utilization, temperature, power draw

Port forwarding (optional, for inbound peers):
  Forward TCP 19335 on your router to this rig's LAN IP.
  Hetzner already peers OUTBOUND to us, so this is optional.

============================================================

# === LOCAL WALLET (optional) ===
# If you want a local wallet on this rig instead of paying to Hetzner:
#
#  1. sudo -u ${BTX_USER} ${BTX_SRC}/build/bin/btx-cli -datadir=${BTX_DATA} createwallet local-rewards
#  2. NEW_ADDR=\$(sudo -u ${BTX_USER} ${BTX_SRC}/build/bin/btx-cli -datadir=${BTX_DATA} -rpcwallet=local-rewards getnewaddress)
#  3. echo "\$NEW_ADDR" > ${BTX_DATA}/reward-address.txt
#  4. echo "wallet=local-rewards" >> ${BTX_DATA}/btx.conf
#  5. sudo systemctl restart btxd btx-miner
#
# Local wallet = more secure (wallet keys never leave this machine).
# Hetzner wallet = consistent with Vast pattern; easier accounting.

# === DASHBOARD ===
# Update ~/.btx-dashboard.conf on your Mac to add this rig as a third node,
# or run dashboard.sh remotely via SSH if you want garage rig stats visible too.
EOF
