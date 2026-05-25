# Claude Packet: BTX Mining Setup for a Layperson

**Audience:** A Claude instance helping a user who is technically literate (can paste commands into a terminal, follow instructions) but is NOT a developer, sysadmin, or crypto-native.

**Goal:** Get them mining BTX (btxchain) end-to-end via cloud infrastructure (no garage hardware, no Linux server knowledge required) within ~6 hours of work spread over 1-2 sessions.

**Your role:** Patient, careful, anti-condescending. Confirm at each step. Catch the specific failure modes documented below before they happen.

---

## What is BTX?

BTX (btxchain) is a Bitcoin Knots v29.2 fork with two key innovations:
- **MatMul Proof-of-Work** instead of SHA-256 — mining work is integer matrix multiplication over the Mersenne prime field F_{2^31 - 1}
- **Post-quantum signatures** (ML-DSA-44 primary, SLH-DSA backup)

Mainnet stable as of March 2026. Block time 90 seconds. Block reward 20 BTX. Max supply 21M. No exchange listings yet — accumulation is via mining only.

**Repo:** https://github.com/btxchain/btx
**Price model (not market):** https://btxprice.com (model spot ~$1-2, 12m projection ~$1,200+)

⚠️ **The user is making a speculative bet, not a yield play.** BTX has no market. Their accumulated BTX cannot be sold today. Frame it as: "you're spending ~$X for the chance that BTX lists at $Y in 12 months." If they don't have spare risk capital, this isn't the right activity for them.

---

## The architecture

Two cloud nodes paired together:

```
┌──────────────────┐           ┌────────────────────┐
│  Hetzner CPX41   │ ◄──p2p──► │  Vast.ai GPU node  │
│  (wallet + node) │  port 19335│  (CUDA miner)      │
│  <YOUR_HETZNER_PUBLIC_IP>     │           │  Variable IP/port  │
│  Always-on       │           │  $0.50-1.50/hr     │
└──────────────────┘           └────────────────────┘
        │                              │
        │ holds wallet                 │ runs btxd with
        │ receives rewards             │ BTX_MATMUL_BACKEND=cuda
        │ ~$46/mo                      │ + live-mining-supervisor
        └─────── mining rewards go ───┘
                 to a Hetzner address
                 (Vast can die without losing funds)
```

**Why two nodes:** Hetzner is the persistent wallet — if Vast crashes, no funds lost. Vast is the GPU miner — short-lived rentals are cheap and replaceable.

---

## Total cost & time expectations (be upfront)

**Setup time:** 2-6 hours active work over 1-2 sessions.

**Ongoing cost:**
- Hetzner CPX41: **$46/mo** (Hillsboro, OR — fixed)
- Vast.ai GPU: **$300-700/mo** depending on GPU choice and uptime
- **Total: ~$350-750/mo**

**60-day "data gathering" run:** ~$1,000

**Returns:** Unknown until they mine for ~1 week. Even after a week, BTX has no market price, so "profit" exists only on paper. Be honest: realistic outcomes range from "total loss if BTX never lists" to "10-100× ROI if BTX trades at projected model price."

**Mining yield:** Their first block typically lands within 24-72 hours of mining starting. After that, they should expect ~1 block per day per GPU at current network conditions (subject to rapid changes — network hashrate is growing fast).

---

## Setup phases (do these in order)

### Phase 0: Prerequisites (~15 min)

**Confirm with the user:**

1. **Mac/Windows/Linux laptop** with a working terminal
2. **Credit card** for Hetzner + Vast.ai (~$50 initial Vast credit, ~$5 Hetzner verification)
3. **Email address** for account signups
4. **SSH key on their machine** — if they don't have one, walk them through `ssh-keygen -t ed25519 -C "their@email.com"` (accept defaults, no passphrase for simplicity)
5. **A password manager** (1Password, Bitwarden, or Apple Keychain) — they'll need to store RPC credentials and wallet addresses persistently

**Critical:** if they're on Windows, they need either WSL (Ubuntu) or a real terminal app (Windows Terminal + PowerShell works for SSH). If they're on Mac, default Terminal app is fine.

### Phase 1: Hetzner setup (~30 min including 5-15min build wait)

**Account & SSH key:**
1. Sign up at console.hetzner.cloud, verify email + payment
2. **Security → SSH Keys → Add** their public key (`cat ~/.ssh/id_ed25519.pub` on Mac/Linux, paste content)

**Create the server:**
- **Project:** create one called `btx-mining`
- **Location:** **Hillsboro, OR** (US West — best GPU latency in US/EU mix)
- **Type:** Standard → **CPX41** (8 vCPU AMD / 16GB RAM / ~$46/mo)
- **Image:** **Ubuntu 24.04**
- **Networking:** Public IPv4 + IPv6 on (defaults)
- **SSH keys:** select the key they added
- **Volumes, Firewalls, Backups, Placement, Labels, Cloud config:** all skip
- **Name:** `btx-cloud-node`
- Click **Create & Buy now**

**Get the public IP** (~30 sec wait) from the server detail page. Save in their password manager.

**SSH in and run setup:**

```bash
# On their local terminal:
scp <PATH_TO_cloud-node-setup.sh> root@<their-hetzner-ip>:/root/
ssh root@<their-hetzner-ip>
# accept the host key (yes)
BTX_REF=main bash /root/cloud-node-setup.sh
```

**During the ~10-15min build, the user should:**
- Stay connected — don't close the terminal
- Watch for `[setup]` markers indicating phase progress

**Known issues during this phase:**
1. **`Remote branch master not found`** — user forgot the `BTX_REF=main` env var. Solution: include it in the bash command.
2. **GPG verification fails on faststart** — happens because BTX's signing key isn't on public keyservers. Workaround: skip faststart, let plain IBD run (slow but works). The script auto-fallbacks to plain IBD.

**After the script completes:**
- The script prints a final block with **RPC user, RPC password, reward address, and instructions for Tailscale**.
- Have them **copy this entire block** to their password manager under "BTX Hetzner Node."
- **Skip Tailscale** — Vast containers can't run it. We peer over public IP instead. Just close the SSH session.

**Then wait for IBD.** This takes ~6-15 hours. The chain is ~107k blocks and the script does plain initial block download.

They can close their laptop. The Hetzner server keeps running.

---

### Phase 2 — Provider choice: RunPod (recommended) or Vast.ai

⚠️ **Strong recommendation: use RunPod Secure Cloud, not Vast.** Empirical operational data from real BTX miners:
- **Vast.ai**: 4 of 4 instances failed within 1-3 days (zombie state, "retries exceeded," disk fill, peer-disconnect storms). P2P marketplace means random consumer-grade hosts. Cheaper hourly but you pay it back in babysitting time.
- **RunPod Secure Cloud**: 99% SLA, Tier 3/4 datacenter hosts, ~1/3 the price of equivalent Vast for 4090 ($0.34-0.69/hr). Crypto-mining not prohibited in TOS.

If you have free Vast credit to burn, use Vast as a *backup* miner alongside RunPod primary. Otherwise skip Vast entirely.

### Phase 2A: RunPod setup (~30 min)

**Account:**
1. Sign up at runpod.io
2. Add credit (Settings → Billing). $25-50 to start is plenty.
3. Settings → SSH Public Keys → add your public key (`cat ~/.ssh/id_ed25519.pub`)

**Find a good pod:**

Filter at runpod.io/console/deploy:
- **GPU**: RTX 4090 (best $/perf) or RTX 5090 if budget allows
- **Pricing**: select **"Secure Cloud"** filter, NOT Community Cloud — Community = P2P (same Vast problems)
- **Image / Template**: search "cuda" → pick `runpod/pytorch:2.x-cuda12.4-devel-ubuntu22.04` (or equivalent with `-devel`)
- **Container Disk**: 50 GB (using `--preset miner` pruned mode) or 100 GB (full node)
- **Network Volume** (optional but recommended): attach a 50GB volume — survives pod stop/restart

Click "Deploy."

**Get SSH details:**
- RunPod console → My Pods → click your pod → Connect → SSH command shown like:
  ```
  ssh root@<pod-ip> -p <port> -i ~/.ssh/id_ed25519
  ```

**Bootstrap:**

```bash
scp -P <port> /path/to/runpod-bootstrap.sh root@<pod-ip>:/root/
ssh root@<pod-ip> -p <port>
export BTX_REWARD_ADDRESS=<from Hetzner setup>
export BTX_HETZNER_PEER_IP=<your Hetzner public IP>
export BTX_CUDA_ARCH=89   # or 120 for 5090
bash /root/runpod-bootstrap.sh
```

Build takes ~5-10 min. Mining auto-starts when IBD completes (~6-12h).

### Phase 2B: Vast.ai setup (~30 min, do this AFTER Hetzner is at least 50% synced) — OPTIONAL/FALLBACK

**Account:**
1. Sign up at cloud.vast.ai
2. Add $50 credit (Account → Billing)
3. Add their SSH public key (same one used for Hetzner) under Account → SSH Keys
4. **Also add it per-instance** when you launch one (Vast quirk — account-level keys don't auto-apply)

**Find a good GPU offer:**

Filter at cloud.vast.ai/create:
- **GPU:** RTX 4090 OR 5090 (NOT 3090, NOT 5070, NOT 4070 — too few CUDA cores)
- **#GPUs:** 1X
- **Verified machines only**
- Sort by $/hr ascending

Click **"Select Template"** → search "cuda" → pick **"NVIDIA CUDA"** (the Vast official one). Confirm the image tag includes `devel` (NOT `runtime` — we need nvcc).

**Pick an offer with these specs:**
- **Container Size: must be set to 100 GB** (critical — defaults too small, will fill overnight and crash)
- Verified host, reliability ≥ 95%
- Bandwidth ≥ 500 Mbps
- **Different from any previously-failed host_id** if they've had problems

**Recommended price range:** $0.50-1.50/hr for a 4090 or 5090.

Click **RENT**, then in the configuration dialog:
- **Container Size: drag slider to 100 GB** (or type it)
- Disk volumes: skip
- Confirm

Wait 1-3 min for instance to become "Running."

**Get SSH details:**
1. Go to Instances page
2. Click the `>_` (terminal) icon on the instance row
3. The dialog shows the "Direct SSH" command — looks like:
   `ssh -p XXXXX root@<ip-address> -L 8080:localhost:8080`
4. **Strip the `-L 8080:localhost:8080`** (Jupyter forwarding, not needed)
5. Note the port number

**SSH in via tmux** (Vast quirk — default SSH session auto-attaches to tmux and bounces if no session exists):

```bash
ssh -t -p <port> root@<ip> "tmux attach -t btx || tmux new -s btx"
```

Once they see `(main) root@C.XXXXX:/workspace$`:

```bash
# Confirm 100GB disk
df -h /workspace
# Should show ~100G available

# Set reward address (from Hetzner setup output)
export BTX_REWARD_ADDRESS=<paste reward address from password manager>
echo "Reward: $BTX_REWARD_ADDRESS"
```

**Then paste the one-shot build block** (provided below in this packet). Build takes ~5-15 min on a decent host CPU.

⚠️ **CRITICAL gotchas during Vast setup:**

1. **BTX_CUDA_ARCHITECTURES varies by GPU:**
   - **RTX 4090: use 89** (Ada Lovelace architecture)
   - **RTX 5090: use 120** (Blackwell)
   - **RTX 3090/3090 Ti: use 86** (Ampere)
   - **RTX 4070/5070/4080: use 89 or 120** depending on series
   - If unsure, the cmake will fail with a clear error — adjust accordingly.

2. **CUDA backend is OPT-IN** — `-DBTX_ENABLE_CUDA_EXPERIMENTAL=ON` is required, default is OFF. Without it, btxd silently falls back to CPU mining (much slower).

3. **`listen=1` in btx.conf is critical** — without it, peers can isolate and chain_guard pauses mining.

4. **SSH session can drop** but processes survive via tmux. Have them reconnect with `ssh -t -p <port> root@<ip> "tmux attach -t btx"`.

5. **Vast instances can go zombie** — dashboard shows "Running" but instance is unreachable. Reboot rarely fixes it. If SSH/`Open` button both fail and `nc -zv <ip> <port>` times out, the answer is destroy + re-rent.

---

### Phase 3: Verify mining is live (~30 min waiting)

After the build script completes, run these checks:

```bash
echo "=== Backends compiled (CUDA must show compiled+available) ==="
/workspace/btx/build/bin/btx-matmul-backend-info --backend cuda | head -15

echo "=== Processes alive ==="
ps aux | grep -v grep | grep -E 'btxd|mining'

echo "=== Sync state ==="
/workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getblockchaininfo | jq '.blocks, .headers, .verificationprogress, .initialblockdownload'

echo "=== Peers (need >5) ==="
/workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getconnectioncount

echo "=== Mining loop ==="
tail -10 /workspace/.btx/mining.log
```

**Healthy signals:**
- CUDA backend: `compiled: true, available: true, reason: ready`
- btxd + live-mining-loop both alive
- Headers climbing fast to ~107k, blocks gradually filling in
- Peer count > 5
- Mining log shows "Started live mining loop"

**Then wait 4-12 hours for IBD on Vast.** Mining auto-starts when chain_guard clears (`should_pause_mining: false`).

**First block typically arrives 0-72 hours after mining starts.** Variance is huge at small share — they may find 0 in week 1 then 5 in week 2. Patience.

---

### Phase 4: Dashboard for ongoing monitoring (~5 min)

Download `dashboard.sh` to their local machine (provided in this packet's appendix).

Create config:

```bash
cat > ~/.btx-dashboard.conf <<EOF
VAST_HOST=<their vast ip>
VAST_PORT=<their vast port>
VAST_HOURLY_RATE=<their hourly rate>
VAST_START_EPOCH=$(date +%s)
HETZNER_HOST=<their hetzner ip>
HETZNER_MONTHLY_RATE=46.49
HETZNER_START_EPOCH=$(date +%s)
EOF
```

Then check status anytime:

```bash
bash <path-to>/dashboard.sh
```

For auto-refresh every 30 sec:
```bash
watch -n 30 -c 'bash <path-to>/dashboard.sh'
```

**Dashboard shows:**
- Sync state of both nodes
- Mining state (paused/active)
- GPU utilization
- BTX balance + implied USD value at model price
- Total spend vs accumulated value
- Break-even calculation

---

## The one-shot build block (paste into Vast tmux after env vars are set)

```bash
set -e
export DEBIAN_FRONTEND=noninteractive
HETZNER_PUBLIC_IP=<YOUR_HETZNER_PUBLIC_IP>   # The public IP from Phase 1 — replace before running
BTX_CUDA_ARCH=89   # 89=4090, 120=5090, 86=3090, etc.

AVAIL_GB=$(df -BG /workspace 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
[[ "${AVAIL_GB}" -lt 60 ]] && { echo "FATAL: only ${AVAIL_GB}GB free; need 60+"; exit 1; }
echo "[guard] Disk OK: ${AVAIL_GB}GB free"

echo "[miner] Installing build deps"
apt-get update
apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config git curl ca-certificates jq \
  libboost-dev libevent-dev libsqlite3-dev \
  python3 python3-zmq

echo "[miner] Cloning + building btxd with CUDA backend (sm_${BTX_CUDA_ARCH})"
mkdir -p /workspace
cd /workspace
[ -d /workspace/btx ] || git clone --depth 1 --branch main https://github.com/btxchain/btx.git
cd /workspace/btx
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DBTX_ENABLE_CUDA_EXPERIMENTAL=ON \
  -DBTX_CUDA_ARCHITECTURES=${BTX_CUDA_ARCH} \
  -DBTX_CUDA_RUNTIME_LIBRARY=Shared
cmake --build build -j"$(nproc)"

echo "[miner] Verifying CUDA backend"
/workspace/btx/build/bin/btx-matmul-backend-info --backend cuda | head -15

echo "[miner] Writing btx.conf"
mkdir -p /workspace/.btx
cat > /workspace/.btx/btx.conf <<EOF
server=1
listen=1
dbcache=8192
maxmempool=300
maxconnections=64
addnode=${HETZNER_PUBLIC_IP}:19335
addnode=node.btx.tools:19335
addnode=146.190.179.86:19335
addnode=164.90.246.229:19335
dnsseed=1
fixedseeds=1
EOF
chmod 600 /workspace/.btx/btx.conf

echo "[miner] Starting btxd with BTX_MATMUL_BACKEND=cuda"
BTX_MATMUL_BACKEND=cuda nohup /workspace/btx/build/bin/btxd -datadir=/workspace/.btx -daemon
sleep 15
/workspace/btx/build/bin/btx-cli -datadir=/workspace/.btx getblockchaininfo | jq '.blocks, .headers'

echo "[miner] Launching mining supervisor"
echo "${BTX_REWARD_ADDRESS}" > /workspace/.btx/reward-address.txt
export PATH=/workspace/btx/build/bin:$PATH
BTX_MINING_CLI=/workspace/btx/build/bin/btx-cli \
BTX_MINING_DAEMON=/workspace/btx/build/bin/btxd \
nohup /workspace/btx/contrib/mining/start-live-mining.sh \
  --datadir=/workspace/.btx \
  --address-file=/workspace/.btx/reward-address.txt \
  > /workspace/.btx/mining.log 2>&1 &

echo "============================================================"
echo "Miner setup complete. Tail with: tail -f /workspace/.btx/mining.log"
echo "============================================================"
```

---

## Troubleshooting cookbook

### "SSH session keeps dropping right away"
Vast's default SSH wraps in `tmux attach` which exits if no session exists. Always use:
```bash
ssh -t -p <port> root@<ip> "tmux attach -t btx || tmux new -s btx"
```

### "Commands seem to do nothing"
User likely pasted commands BEFORE the SSH connection fully opened. Local Mac doesn't have `/workspace` or btxd. Confirm they're at the remote prompt `root@C.XXXXX:/workspace$` before pasting.

### "fatal: Remote branch master not found"
Default BTX branch is `main`. Use `BTX_REF=main` env var with the setup script.

### "GPG signature verification failed"
BTX dev signing key (fingerprint `4204C1DD9BC1F6E65893653AE8EBF01F15A88DC4`) isn't on public keyservers. Fetch from release page:
```bash
curl -fsSL https://github.com/btxchain/btx/releases/download/v0.30.0/BTX-RELEASE-PUBKEY.asc -o /tmp/btx-pubkey.asc
sudo -u btx gpg --import /tmp/btx-pubkey.asc
```

### "could not load BTX shielded snapshot section"
Known upstream bug — fixed in v0.30.0+. If they're seeing it on an older build, either rebuild from main or skip snapshot loading entirely (plain IBD works).

### "Disk space is too low" on Vast
Container Size was set < 100GB at rent time. Solution: destroy and re-rent with 100GB. (Cannot resize live.)

### "CUDA oracle acceleration is unavailable on this build"
`BTX_ENABLE_CUDA_EXPERIMENTAL=ON` wasn't passed to cmake. Rebuild with it.

### "0 peers, mining paused, chain_guard insufficient_peer_consensus"
`listen=0` in btx.conf can cause peer isolation. Edit btx.conf to `listen=1` and restart btxd.

### "Vast instance shows 'Running' but SSH/Open both fail"
Zombie state. Destroy + re-rent on a different host (note the host_id you avoid). If this happens repeatedly, **switch to RunPod Secure Cloud** — the Vast P2P marketplace has empirically high failure rates for sustained mining workloads.

### "Vast instance hits 'retries exceeded' after 1-3 days"
Container infrastructure failure. Vast hosts can't sustain 24/7 100% GPU at high power. Same fix: switch to RunPod Secure Cloud (datacenter Tier 3/4 hosts).

### "Two btxd instances fill 100GB disk"
Each btxd's full chain state is ~50GB. Two btxd's = >100GB → disk full. Fix: use `--preset miner` for the second btxd, which prunes block storage (~5-10GB per instance). Or rent a pod with 200GB+ disk.

### "Peer count drops to 1 and stays there, peers keep connecting then disconnecting in debug.log"
Container network layer broken (we hit this on Vast). Peers connect (visible in debug.log as "New peer X connected") but never accumulate in getconnectioncount. Fix: destroy the instance, switch providers.

### "GPU 1 stuck at 100% util / ~115W after btxd died"
CUDA context not released by dead btxd. Reboot the instance via web UI (kill -9 won't release the GPU context). On owned hardware, `sudo nvidia-smi --gpu-reset` works.

### "Mining supervisor restarts btxd without preserving env vars"
Mining supervisor calls btxd directly without inheriting `BTX_MATMUL_BACKEND=cuda` or `CUDA_VISIBLE_DEVICES=N`. After supervisor-managed restart, the new btxd may fall back to CPU mining. Workaround: wrap btxd in a launch script that sets env vars, point supervisor at that.

### "Hetzner wallet not loaded after restart"
Add `wallet=miner-rewards` to `/home/btx/.btx/btx.conf` to auto-load on startup.

### "Mining log says 'Missing required command: btx-cli'"
Mining supervisor can't find btx-cli on PATH. Restart with explicit env vars:
```bash
BTX_MINING_CLI=/workspace/btx/build/bin/btx-cli \
BTX_MINING_DAEMON=/workspace/btx/build/bin/btxd \
nohup /workspace/btx/contrib/mining/start-live-mining.sh \
  --datadir=/workspace/.btx \
  --address-file=/workspace/.btx/reward-address.txt \
  > /workspace/.btx/mining.log 2>&1 &
```

---

## When to escalate to a human

If any of these happen, the user should pause and seek help (community forum, GitHub issue, or someone with hands-on experience) rather than continue Claude-only:

1. **Charges hitting credit card unexpectedly** — billing question, needs human review
2. **Vast keeps zombie-ing repeatedly** — pattern suggests infrastructure issue, may need to switch providers
3. **First block not found after 7 days** — could be hashrate issue, wallet config error, or chain divergence; needs hands-on debugging
4. **Wallet balance unexpectedly goes down** — should never happen with coinbase rewards; investigate immediately
5. **Mining works but they want to scale beyond 2 GPUs** — economics shift; benefit from human strategy conversation
6. **They want to add a garage rig** — physical hardware setup is a different packet entirely

---

## What success looks like

After ~3 days of following this packet:
- Hetzner CPX41 running 24/7, fully synced
- Vast.ai instance running, GPU at >50% utilization when not paused
- First block found, 20 BTX in Hetzner wallet
- Dashboard showing positive economics at spot model price
- User comfortable checking status independently and replacing Vast instances when needed

After 60 days:
- ~50-500 BTX accumulated (depending on hashrate share + variance)
- Real data on cost-per-BTX-mined vs network growth
- Informed decision point: continue/scale/exit

---

## Tone & posture for Claude

- **Patient** — laypeople will paste commands wrong, lose SSH sessions, forget to set env vars. Don't sigh. Walk them through it again.
- **Anti-condescending** — explain WHY when something matters, don't just give commands.
- **Confirm at checkpoints** — "Tell me what you see at the prompt before continuing."
- **Catch errors before they happen** — when about to do something error-prone (rent Vast without setting disk size, paste a command before SSH connects), preemptively warn.
- **Honest about uncertainty** — when the user asks "will I make money," the answer is "no idea — this is a speculative bet on a chain with no market yet."
- **Stop and ask** when the user's intent diverges from this packet (e.g., wants to use a different provider, wants to mine on a 3070 — push back, explain why this packet's choices are recommended).

If the user starts deviating significantly from this packet's setup, gently redirect them. The packet is opinionated for good reasons — every deviation increases failure risk, and the troubleshooting cookbook below only applies to the documented path.

---

## Files referenced (provide alongside this packet)

1. `cloud-node-setup.sh` — Hetzner setup script (paste into Ubuntu 24.04)
2. `vast-miner-bootstrap.sh` — Vast setup (or use the inline build block above)
3. `dashboard.sh` — local monitoring tool
4. (Optional) `garage-rig-setup.sh` — for the small number of users who want to build owned hardware later

All available in this repo alongside this packet.
