# Claude Packet: BTX Mining Setup for a Layperson

**Audience:** A Claude instance helping a user who is technically literate (can paste commands into a terminal, follow instructions) but is NOT a developer, sysadmin, or crypto-native.

**Goal:** Get them pool-mining BTX (btxchain) end-to-end via cloud infrastructure within ~2 hours of active work, with a wallet they control and a way to independently verify the pool is paying them.

**Your role:** Patient, careful, anti-condescending. Confirm at each step. Catch the specific failure modes documented below before they happen.

---

## ⚠️ READ FIRST — June 2026 network events (make sure the user knows this before they spend)

Do not start setup until the user has acknowledged these four facts. They change both the risk picture and the technical path.

1. **The chain forked in mid-June 2026.** 13 releases shipped June 5–16 with six-plus mandatory consensus activations (heights ~123,000–135,000), some on ~1 day's notice. Nodes on v0.31.0 or older stranded on a dead fork around height ~125,600. No public postmortem exists. **Any node this playbook builds must come from current `main` (or a ≥v0.32.x release) — never an old binary or old checkout.** A node whose height is stuck near ~125,600 is on the dead fork.

2. **The release-signing key rotated undocumented.** Binaries ≥~v0.32.9 are signed by a new key (`C55C98C7…CD566156`, "BTX Release Maintainer <release@btx.local>", created 2026-06-13), not the long-standing developer key. No cross-signature, no announcement, tags now unsigned. Legitimate-but-sloppy rotation and a compromised release pipeline are indistinguishable from outside. **Mitigation in this playbook: build from source, pin versions, never enable auto-update** (the project itself has auto-update disabled network-wide).

3. **Solo mining on cloud GPUs orphans most blocks.** NAT'd containers (`connections_in=0`) lose propagation races on this fast (≈77-90s block) network — we measured 3 of 4 found blocks orphaned. **Pool mining is the path.** Bonus: pool mode needs no local node, no chain sync, no snapshot; the box hashes within a minute and its death costs nothing.

4. **Risk facts** (public sources: btx.dev, the repo, chain data): team fully anonymous; ~1M BTX (~4.76%) effective premine to an undocumented team "genesis multisig" whose stated purposes include making "early market depth"; shielded pool sunset in June via emergency-shaped consensus changes with no stated cause; docs unchanged since 2026-03-30 (predate everything above); **no exchange, no executable market — mined coins mark to ~$0 today.**

⚠️ **The user is making a speculative bet, not a yield play.** If they don't have spare risk capital, this isn't the right activity for them. If they ask "will I make money," the honest answer is "no idea — and the June events made the bet worse, not better."

---

## What is BTX?

BTX (btxchain) is a Bitcoin Knots v29.2 fork with two key innovations:
- **MatMul Proof-of-Work** instead of SHA-256 — mining work is integer matrix multiplication over the Mersenne prime field F_{2^31 - 1}
- **Post-quantum signatures** (ML-DSA-44 primary, SLH-DSA backup)

Mainnet since March 2026 (genesis 2026-03-19). Block time ~90 seconds. Block reward 20 BTX. Max supply 21M. Canonical chain height was ~148,000 as of early July 2026.

**Repo:** https://github.com/btxchain/btx
**Price model (not market):** https://btxprice.com — a theoretical model. No market exists for BTX. Never quote its numbers as expected value.

**Ticker collision warning:** "BTX" also names BitCore (an old altcoin) and a Solana token. Exchange/CoinGecko data for "BTX" is almost certainly NOT this chain. Verify before treating any listing as relevant.

---

## Teach as you go — plain-English concepts

The user is smart but not crypto-native. **Before each phase, give a one-breath explanation of what the next step is for and why it exists** — then the commands. Never make them execute something they couldn't paraphrase back. Analogies that have worked:

- **Mining** = a lottery drawn every ~90 seconds. Machines churn matrix math; first winning answer adds the next block and earns 20 BTX. Odds = your slice of total network compute.
- **A pool** = an office lottery syndicate. Everyone's GPUs buy tickets together; winnings split in proportion to work contributed ("shares"). You trade jackpots for a steady trickle. On this network the syndicate is also *structural*: a lone NAT'd cloud box that wins can't announce its block fast enough and the win is discarded ("orphaned") — the pool has the network position to make wins stick.
- **The GPU box** = a disposable worker. It does math and submits shares. No keys, no coins, no ledger. Its death costs nothing but re-rental time.
- **The wallet node** = vault + auditor. It holds the keys that control the coins, and its own full copy of the ledger — so the user can verify payments without trusting the pool's dashboard.
- **The payout address** (`btx1…`) = an account number. Safe to share, safe to put in scripts. The **wallet files/keys** on the Hetzner box are the opposite: whoever has them owns the coins. Never paste, never share, always back up.
- **`scantxoutset`** = "check your own copy of the books instead of believing the pool's receipt."
- **Shares vs blocks** = punched timecards vs the actual jackpot. Accepted shares prove the GPU is working and earning; the pool converts them to BTX at each pay period.

Checkpoints ("tell me what you see") are also teaching moments — when the user reports output, say what it means in one sentence before moving on.

---

## The architecture (pool-first, revised June 2026)

```
┌────────────────────┐          ┌──────────────────────┐
│  Vast.ai GPU box   │──shares─►│  Pool                │
│  matador-miner     │ stratum  │  stratum.minebtx.com │
│  (no keys, no node,│          │  (+ failover pool)   │
│   no chain state)  │          └──────────┬───────────┘
└────────────────────┘                     │ batched payouts
                                           ▼
                              your payout address (btx1…)
                                           ▲
┌────────────────────┐                     │
│  Hetzner CPX41     │─── wallet holds ────┘
│  wallet + node     │    the keys; node verifies
│  ~$46/mo, always-on│    payouts on-chain
└────────────────────┘
```

**Why this shape:**
- The **GPU box** runs only `matador-miner` in pool mode. It holds no keys and no chain state. It can be destroyed and re-rented in minutes at zero loss.
- The **pool** aggregates hashrate, wins the propagation races the NAT'd box can't, and pays out per accepted share (fee ~2.5% at minebtx, plus matador-miner's mandatory 1% dev fee).
- The **wallet node** (Hetzner) is where the payout address comes from and — critically — where the user *independently verifies* the pool actually pays. Trust, but `scantxoutset`.

**Setup order matters:** wallet node first (you need the payout address), but its multi-hour chain sync runs in the background while you set up the miner. The miner doesn't wait for it.

---

## Total cost & time expectations (be upfront)

**Setup time:** ~1-2 hours active work. The wallet node syncs in the background (many hours — MatMul validation makes IBD slow); mining starts without it.

**Ongoing cost:**
- Vast.ai RTX 5090: **~$0.45-0.60/hr ≈ $330-440/mo** at 24/7 (4090s a bit less)
- Hetzner CPX41: **~$46/mo**
- **Total: ~$380-490/mo**, plus ~3.5% combined pool + dev fees off the top

**Yield:** as of early July 2026, a single RTX 5090 earned on the order of a few BTX/day via pool, paid in batches per pay period (payouts are NOT continuous — expect lumpy arrivals, sometimes days apart). Network hashrate is growing; expect decline. Do NOT quote dollar projections — there is no market.

---

## Setup phases (do these in order)

### Phase 0: Prerequisites (~15 min)

**Confirm with the user:**

1. **Mac/Windows/Linux laptop** with a working terminal
2. **Credit card** for Hetzner + Vast.ai (~$50 initial Vast credit, ~$5 Hetzner verification)
3. **Email address** for account signups
4. **SSH key on their machine** — if missing, walk them through `ssh-keygen -t ed25519 -C "their@email.com"` (accept defaults, no passphrase for simplicity)
5. **A password manager** (1Password, Bitwarden, or Apple Keychain) — they'll store RPC credentials and the payout address

**Critical:** on Windows they need WSL (Ubuntu) or Windows Terminal + PowerShell for SSH. On Mac, default Terminal is fine.

### Phase 1: Wallet node on Hetzner (~30 min active, sync runs in background)

**Account & SSH key:**
1. Sign up at console.hetzner.cloud, verify email + payment
2. **Security → SSH Keys → Add** their public key (`cat ~/.ssh/id_ed25519.pub`, paste content)

**Create the server:**
- **Project:** create one called `btx-mining`
- **Location:** **Hillsboro, OR** (US West)
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

**Why `main` and not a release tag:** building from current source guarantees the node has all the June 2026 consensus activations and sidesteps the binary-release signing-key question entirely. Never install a pre-built binary older than the v0.32.x series, and never enable any auto-update mechanism.

**During the ~10-15min build:** stay connected, watch for `[setup]` markers.

**Known issues during this phase:**
1. **`Remote branch master not found`** — user forgot the `BTX_REF=main` env var.
2. **GPG verification fails on faststart** — BTX's signing key isn't on public keyservers; the script auto-falls-back to plain IBD. Given the June key rotation, treat any signature-related surprise as a stop-and-verify moment, not something to work around silently.

**After the script completes:**
- It prints **RPC user, RPC password, and the reward/payout address**. Have them **copy the whole block** into their password manager under "BTX Hetzner Node." The `btx1…` address is what the pool will pay.
- **Back up the wallet immediately:** copy `/home/btx/.btx/wallets/miner-rewards/` off-box (e.g. `scp` to their laptop, then into encrypted storage). If the Hetzner box dies unbacked-up, accrued payouts are gone.
- Skip Tailscale unless they want it — pool mode doesn't need the miner to reach this node at all.

**Then let IBD run in the background.** The chain is ~150k blocks and MatMul validation makes sync slow — expect many hours to a day. **Do not wait — go straight to Phase 2.** The node only needs to be synced later, for payout verification.

---

### Phase 2: Pool miner on Vast.ai (~15 min, hashing in ~1 minute)

**Account:**
1. Sign up at cloud.vast.ai
2. Add $50 credit (Account → Billing)
3. Add their SSH public key under Account → SSH Keys
4. **Also add it per-instance** when launching (Vast quirk — account-level keys don't always auto-apply)

**Find a GPU offer** at cloud.vast.ai/create:
- **GPU:** RTX 5090 or 4090 (best MatMul throughput per dollar)
- **#GPUs:** 1X
- **Verified machines only**, reliability ≥ 95%
- **Template:** search "cuda" → the official **NVIDIA CUDA** template. Pool mode doesn't compile anything, so `runtime` vs `devel` image doesn't matter.
- **Container size: 20 GB is plenty** (no chain state in pool mode — the old 100GB requirement is solo-only)
- Sort by $/hr; **$0.40-0.60/hr for a 5090** is the current sane range

Click **RENT**, wait 1-3 min for "Running."

**Note on provider choice:** the original playbook pushed RunPod Secure Cloud because Vast hosts die often and solo mining made each death expensive (lost sync state, hours of rebuild). **Pool mode changes the math** — a dead Vast box costs nothing but the minutes to re-rent, so cheap Vast offers are fine again. RunPod still works if inventory is better; the bootstrap below is provider-agnostic except for the reboot-proofing note.

**Get SSH details:** Instances page → `>_` icon → copy the "Direct SSH" command, **strip the `-L 8080:…` part**, note the port.

**SSH in via tmux** (Vast quirk — default SSH bounces if no tmux session exists):

```bash
ssh -t -p <port> root@<ip> "tmux attach -t btx || tmux new -s btx"
```

**Run the bootstrap:**

```bash
# scp the script up first, from their laptop:
scp -P <port> /path/to/vast-pool-bootstrap.sh root@<ip>:/root/

# then on the box:
export BTX_PAYOUT_ADDRESS=<their btx1… address from Phase 1>
export BTX_WORKER=rig1        # any label; shows up in pool stats
bash /root/vast-pool-bootstrap.sh
```

The script:
- installs `matador-miner` (GPU MatMul pool miner, [vanities/matador-miner](https://github.com/vanities/matador-miner))
- launches it supervised (auto-restart loop) against `stratum.minebtx.com:3333` with `stratum.bitminerpool.xyz:3333` as failover
- **writes `/root/onstart.sh` so Vast host reboots restart the miner automatically.** This matters: without it, a host reboot silently kills the miner and the box keeps billing while doing nothing (this failure cost us ~$80 over 6 idle days before we caught it)
- runs with `--no-update-check` — given this chain's release history, nothing on these boxes self-updates

**Within ~1 minute** the log should show pool authorization and accepted shares. That's it — no sync, no wallet, no keys on the box.

⚠️ **Gotchas:**
1. **`BTX_PAYOUT_ADDRESS` must be THEIR address.** Triple-check against the password manager — a typo'd address pays a stranger, irreversibly. Read it back to them character-grouped.
2. **Vast instances can zombie** — dashboard says "Running" but SSH fails. Destroy + re-rent on a different host. In pool mode this costs nothing.
3. **The 1% matador dev fee is mandatory** — the miner periodically hashes for its developer. Expected, not a compromise.

---

### Phase 3: Verify it's real (~10 min now, ~5 min again after first payout)

**A. Shares are being accepted (immediately):**

```bash
grep -iE "authorized|accepted" /root/matador.log | tail -5
nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv,noheader
```

Healthy: recent "share accepted" lines; GPU at ~100% util and high power draw (a 5090 pulls ~550-600W mining; sustained ~70W means it's NOT mining).

**B. The pool sees the worker (same day):** check the pool's public stats page for their payout address / worker label. minebtx publishes per-address stats.

**C. Payouts actually land on the canonical chain (after the first pay period — may be days):**

On the Hetzner node, once synced:

```bash
sudo -u btx /home/btx/btx/build/bin/btx-cli -datadir=/home/btx/.btx \
  scantxoutset start '["addr(<their btx1… address>)"]'
```

This scans the node's own UTXO set — **trustless verification that the pool paid.** The wallet's `getbalances` should show the same coins. If the pool's dashboard says "paid" but `scantxoutset` shows nothing new for several days, escalate (see below).

**D. The node is on the canonical chain (once, after sync):** compare `getblockchaininfo` height against the pool's stats page or another public source. Heights should be within a few blocks. **A node stuck near ~125,600 is on the June dead fork** — see troubleshooting.

---

### Phase 4: Ongoing monitoring (~5 min)

Daily habit (or teach them to ask Claude to do it):

```bash
# Miner alive + hashing?
ssh -t -p <port> root@<ip> "nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv,noheader; grep -c 'accepted' /root/matador.log | tail -1"

# Wallet node synced + balance? (on Hetzner)
sudo -u btx /home/btx/btx/build/bin/btx-cli -datadir=/home/btx/.btx getblockchaininfo | jq '.blocks'
sudo -u btx /home/btx/btx/build/bin/btx-cli -datadir=/home/btx/.btx -rpcwallet=miner-rewards getbalances
```

`dashboard.sh` in this repo renders the wallet-node side nicely (sync, spendable vs immature balance, spend vs accumulation). Its GPU-node panels assume the legacy solo architecture (a btxd on the Vast box) — in pool mode, ignore those or watch `matador.log` directly.

**Weekly:** confirm the Vast box hasn't been rebooted into idleness (`pgrep -f matador-miner` on the box), and re-run the `scantxoutset` payout check.

---

## Troubleshooting cookbook

### Pool-mode issues (current path)

**"Miner stopped after the Vast host rebooted"**
`/root/onstart.sh` should relaunch it automatically (the bootstrap writes it). If the box predates that: `bash /root/run-matador.sh` won't be running — `nohup bash /root/run-matador.sh > /root/matador.log 2>&1 &` and then install the onstart guard from the bootstrap script. **Check for this after every host reboot** — an idle box bills the same as a mining one.

**"No shares accepted / 'authorization failed'"**
Almost always a malformed `--payoutaddress`. Verify the `btx1…` string character-for-character. Second cause: pool endpoint down — the supervisor fails over to the second pool automatically; check `matador.log` for which pool it's on.

**"GPU at ~70W, util ~0%, but matador-miner is running"**
Miner lost the CUDA context (host GPU issue) or is stuck reconnecting. Restart the supervisor: `pkill -f matador-miner; sleep 2` (the run-loop relaunches it). If wattage stays low, destroy + re-rent — box cost is zero in pool mode.

**"Pool dashboard shows earnings but my wallet shows nothing"**
Payouts are **batched per pay period** — days can pass between "earned" and "paid." Verify with `scantxoutset` (Phase 3C), not just wallet balance: if the wallet node is behind or on the wrong chain, the wallet can't see coins that DO exist. If `scantxoutset` on a **synced, canonical** node shows nothing new well past a pay period, stop pointing hashrate at that pool and escalate.

**"My node is stuck at block ~125,600"**
It's on the June 2026 dead fork (pre-v0.32 consensus rules). Fix: stop btxd, rebuild from current `main` (`cd ~/btx && git fetch && git checkout main && git pull`, then re-run the cmake build), restart, and let it reorg/resync. Coins received at heights below the ~125,000 divergence are typically intact on the canonical chain — verify with `scantxoutset` on the synced node before panicking. Coins "mined" on the dead fork after the divergence never existed canonically.

### Infrastructure issues (both paths)

**"SSH session keeps dropping right away"**
Vast's default SSH wraps in `tmux attach` which exits if no session exists. Always: `ssh -t -p <port> root@<ip> "tmux attach -t btx || tmux new -s btx"`

**"Commands seem to do nothing"**
User pasted before the SSH connection opened — they ran it on their laptop. Confirm they see the remote prompt before pasting.

**"Vast instance shows 'Running' but SSH/Open both fail"**
Zombie state. Destroy + re-rent on a different host (note the avoided host_id). Costs nothing in pool mode.

**"GPU stuck at 100% util / ~115W after the mining process died"**
CUDA context not released. Reboot the instance via web UI (`kill -9` won't free it). On owned hardware: `sudo nvidia-smi --gpu-reset`.

### Wallet-node issues

**"fatal: Remote branch master not found"**
Default BTX branch is `main`. Use `BTX_REF=main` with the setup script.

**"GPG signature verification failed" (faststart)**
The signing key isn't on public keyservers, and note the release key **changed undocumented in June 2026**. The safe path is what the script already does: fall back to building/syncing from source. Don't chase binary signatures.

**"Hetzner wallet not loaded after restart"**
Add `wallet=miner-rewards` to `/home/btx/.btx/btx.conf` (the setup script does this; older setups may lack it).

**"0 peers / chain_guard insufficient_peer_consensus"**
`listen=0` in btx.conf can cause peer isolation. Set `listen=1`, restart btxd.

### Legacy solo-mining issues

The original solo path (btxd + CUDA backend + live-mining supervisor on the GPU box) is preserved in `runpod-bootstrap.sh` / `vast-miner-bootstrap.sh` / `garage-rig-setup.sh`. **Do not run it on cloud containers** — NAT'd boxes orphan the large majority of found blocks (measured: 3 of 4 lost), which silently converts "20 BTX found!" into nothing. It remains viable only on hardware with real inbound connectivity (port-forwarded home/colo). If a user insists on solo, the load-bearing gotchas are: `BTX_ENABLE_CUDA_EXPERIMENTAL=ON` at cmake time; correct `BTX_CUDA_ARCHITECTURES` (89=4090, 120=5090, 86=3090); 100GB+ disk; `listen=1`; and the btxd env wrapper so supervisor restarts don't silently fall back to CPU mining (sustained ~70W GPU draw = CPU mode = burning money). Full details live in the legacy scripts' comments and this repo's git history.

---

## When to escalate to a human

1. **Charges hitting the credit card unexpectedly** — billing question, needs human review
2. **Pool "pays" but `scantxoutset` on a synced canonical node shows nothing for 2+ pay periods** — possible pool problem; stop hashing there, ask in community channels
3. **Signature/key anomalies during any install** — given the June rotation, never "work around" a failed verification silently
4. **Wallet balance unexpectedly goes down** — should never happen; investigate immediately
5. **They want to scale beyond 1-2 GPUs** — economics + risk conversation, not a setup task. Given the chain's June 2026 events and zero liquidity, more capital needs more conviction than a playbook can supply
6. **They want a garage rig** — physical hardware is a different project entirely

---

## What success looks like

After day 1:
- Hetzner node syncing (or synced), wallet backed up off-box
- Vast box hashing at full GPU power, shares accepted, reboot-proofed
- User can read `matador.log` and pool stats themselves

After the first pay period:
- Payout independently verified on-chain via `scantxoutset` — not just trusted from the pool dashboard

After 30-60 days:
- Real cost-per-BTX data
- An informed continue/scale/exit decision — made against the honest backdrop that the coins remain unsellable until a market exists

---

## Tone & posture for Claude

- **Patient** — laypeople paste commands wrong, lose SSH sessions, typo addresses. Don't sigh. Walk them through again.
- **Anti-condescending** — explain WHY when something matters, don't just give commands.
- **Confirm at checkpoints** — "Tell me what you see at the prompt before continuing." The payout address deserves a full read-back.
- **Catch errors before they happen** — warn preemptively at the error-prone steps (address entry, pasting before SSH connects).
- **Honest about uncertainty** — "will I make money" → "no idea; no market exists, and the June 2026 events are unresolved risk."
- **Don't bury the risk section** — if the user skipped the READ FIRST block, bring them back to it before any money is spent.
- **Stop and redirect** if they deviate significantly (different pool, solo on cloud, weird GPU). The packet is opinionated for documented reasons; the cookbook only covers the documented path.

---

## Files referenced (provide alongside this packet)

1. `vast-pool-bootstrap.sh` — pool miner bootstrap (**the current path**)
2. `cloud-node-setup.sh` — Hetzner wallet-node setup
3. `dashboard.sh` — local monitoring (wallet side current; GPU panels are solo-era)
4. `runpod-bootstrap.sh`, `vast-miner-bootstrap.sh`, `garage-rig-setup.sh` — legacy solo path

All available in this repo alongside this packet.
