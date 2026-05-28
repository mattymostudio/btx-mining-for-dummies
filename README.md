# BTX Mining For Dummies

A complete, opinionated setup guide for mining **BTX** (the post-quantum, MatMul-PoW Bitcoin Knots fork at [btxchain/btx](https://github.com/btxchain/btx)) using cloud infrastructure — designed to be driven by [Claude Code](https://claude.com/claude-code) so the operator can be technically literate without being a developer.

You paste the packet into Claude. Claude walks you through every step. You end up with a running miner, a wallet, and a dashboard.

Published by [Matty Mo Studio](https://themostfamousartist.com).

---

## What this is

A repo containing:
- **`CLAUDE_PACKET.md`** — paste this into Claude Code as context. Claude reads it and helps you execute every step, troubleshoots known errors, and stops you before predictable mistakes.
- **`cloud-node-setup.sh`** — Hetzner CPX41 (Ubuntu 24.04) → BTX validator + wallet host.
- **`runpod-bootstrap.sh`** — RunPod Secure Cloud GPU pod → CUDA-accelerated BTX miner. **Recommended** for cloud mining (datacenter SLA, ~$0.40-0.70/hr 4090).
- **`vast-miner-bootstrap.sh`** — Vast.ai GPU instance → cheaper but less reliable. Use only if RunPod inventory is unavailable.
- **`garage-rig-setup.sh`** — (optional) owned-hardware setup for those who buy a 5090/4090.
- **`dashboard.sh`** — local terminal dashboard showing sync state, balance, spend, and break-even.

The packet captures every operational gotcha learned from real deployment — including the ones that cost real money the first time around.

---

## ⚠️ Read before you start

**This is a speculative bet.** BTX has no exchanges, no market price, no liquid OTC. Coins you mine cannot be sold today. The thesis is that BTX will list at meaningful prices in the future. If it doesn't, your spend is a loss.

**Expected costs:**
- Hetzner CPX41: **~$46/month** (always-on validator)
- **RunPod Secure 4090** (recommended): **~$240-500/month** (24/7 at $0.34-0.69/hr)
- *or Vast 4090/5090*: $300-1,500/month (cheaper hourly but **expect 1-3 day MTBF**, frequent re-renting)
- **Total: ~$300-550/month** on RunPod, ~$350-1,550 on Vast

**Expected outcomes:** Unknown. BTX has no exchanges, no market price, and no liquid OTC. Coins you mine cannot be sold today. [btxprice.com](https://btxprice.com) publishes a theoretical price model — treat anything there as speculation, not forecast. The published projections have recalibrated dramatically as the chain has matured, so do not anchor on any specific number. This is a bet that BTX will list at meaningful prices in the future. It may not.

**Don't run this with money you can't afford to lose entirely.**

---

## Quick start

1. **Clone this repo:**
   ```bash
   git clone https://github.com/<owner>/btx-mining-for-dummies.git
   cd btx-mining-for-dummies
   ```

2. **Open Claude Code in this directory:**
   ```bash
   claude
   ```

3. **Hand Claude the packet:**
   ```
   Please read CLAUDE_PACKET.md and walk me through BTX mining setup. I'm a layperson — go slow, confirm each step.
   ```

4. **Follow Claude's instructions.** It will guide you through:
   - Creating Hetzner + Vast.ai accounts (~30 min)
   - Provisioning the validator node (~30 min + ~10h chain sync, can run overnight)
   - Provisioning the GPU miner (~30 min + ~6-12h chain sync)
   - Verifying mining is live (~5 min)
   - Setting up the local dashboard (~5 min)

5. **Total active time: ~2 hours.** Total wall-clock time to mining live: ~24-36 hours (chain sync is the bottleneck).

---

## What you'll end up with

```
┌──────────────────┐           ┌────────────────────┐
│  Hetzner CPX41   │ ◄──p2p──► │  RunPod / Vast     │
│  (wallet + node) │           │  GPU node          │
│  Always-on       │           │  (CUDA miner)      │
│  ~$46/mo         │           │  ~$240-700/mo      │
└──────────────────┘           └────────────────────┘
        │                              │
        └─── mining rewards land ──────┘
             on Hetzner-controlled wallet
             (GPU node can die without losing funds)
```

Plus a local dashboard showing:
- Sync state of both nodes
- BTX balance + implied USD value (at btxprice.com model)
- Total spend vs accumulated value
- Break-even math

---

## What you need before starting

- **Mac, Linux, or Windows with WSL** — for terminal access
- **Credit card** for Hetzner (~$5 verification) and Vast.ai ($50+ initial credit)
- **Email** for account signups
- **A password manager** for storing wallet addresses and RPC credentials
- **Claude Code** installed — [https://claude.com/claude-code](https://claude.com/claude-code)
- **SSH key** on your machine (Claude will help generate one if missing)

You do NOT need:
- Linux experience
- Crypto / mining background
- A GPU (cloud-only setup is the default)
- A dedicated computer (your laptop is fine — the mining runs on cloud servers, not your machine)

---

## The two-node architecture (why it's set up this way)

**Hetzner node** holds the wallet and stays online forever. It's where your mining rewards arrive and accumulate.

**Vast.ai node** rents a GPU for the actual mining computation. It pays rewards to the Hetzner wallet address. If Vast crashes (it happens), you don't lose any BTX — they're safely on Hetzner.

This separation is critical. Single-node setups risk losing accumulated rewards if the mining machine fails.

---

## What's in this repo

| File | Purpose | Where it runs |
|---|---|---|
| `CLAUDE_PACKET.md` | The brain — Claude reads this to guide you | Claude Code context |
| `cloud-node-setup.sh` | Provisions BTX validator + wallet on Hetzner | Hetzner Ubuntu 24.04 |
| `runpod-bootstrap.sh` | Provisions GPU miner on RunPod (recommended) | RunPod Secure Cloud pod |
| `vast-miner-bootstrap.sh` | Provisions GPU miner on Vast.ai (cheaper, less reliable) | Vast.ai CUDA container |
| `garage-rig-setup.sh` | (Optional) provisions owned-hardware miner | Your own Ubuntu Server |
| `dashboard.sh` | Live monitoring dashboard | Your laptop |

---

## Going beyond cloud-only

After ~60 days of cloud mining, you'll have real data on your hashrate, the network's growth, and your accumulation rate. At that point, the **`garage-rig-setup.sh`** script can guide you through building a dedicated owned-hardware miner (~$3,500-4,500 for a full 5090 rig — see comments in that script for the parts list).

Owned hardware is roughly 3-5× cheaper per BTX over 24 months than cloud — but only worth committing to once you've validated the cloud setup works for you.

---

## Honest tradeoffs vs other approaches

| Approach | Upfront | Monthly | Pros | Cons |
|---|---|---|---|---|
| **This playbook (cloud)** | $0 | $350-750 | Zero hardware, clean exit, fast start | 3-5× more expensive than owned long-term |
| **Owned 5090 rig** | $3,500-4,500 | $51 | Best long-term economics, your hardware | High commit, hardware fragility, you're sysadmin |
| **Mining pool** (when one exists) | $0 | varies | Smooth variance | None exist for BTX yet |

This playbook is opinionated about cloud-only as the right starting point: low commit, fast setup, easy exit if the thesis breaks.

---

## License

MIT — see [LICENSE](LICENSE). Use this however you want.

If you find errors, hit pitfalls not in the troubleshooting section, or improve the scripts, **PRs welcome**. The packet's troubleshooting cookbook grows by being shared.

---

## Disclaimer (the boring but important part)

**This is not financial advice. Nothing in this repository constitutes investment, tax, legal, or any other professional advice.** The authors are not financial advisors, brokers, dealers, or registered investment professionals. Any decision you make about whether to mine BTX, how much to spend, or what to do with mined coins is entirely your own responsibility.

BTX mining involves speculative cryptocurrency where:
- The chain may fail or fork
- Listings may never materialize
- Models published at [btxprice.com](https://btxprice.com) are theoretical — not market prices
- You may spend $1,000+ and recover $0

Run this with money you can lose entirely. The authors of this playbook are not responsible for losses, dead chains, or unmet expectations.

The scripts and packet capture real operational knowledge from real deployments. They are **opinionated** — they pick specific cloud providers, specific GPU vendors, specific software versions. You can deviate, but the troubleshooting and pitfall-avoidance built into the packet only applies to the documented path.

---

## Credits

Built from operational experience deploying BTX miners on Hetzner + Vast.ai. The packet's troubleshooting cookbook reflects 30+ hours of real-world debugging — every gotcha listed cost time or money to discover.

Published by [Matty Mo Studio](https://themostfamousartist.com). If you want help with strategy, scaling, or the owned-hardware path beyond what Claude can answer from this packet, that's outside the playbook's scope.

---

## Repo structure

```
btx-mining-for-dummies/
├── README.md                       # this file
├── CLAUDE_PACKET.md                # the operational packet for Claude
├── LICENSE                         # MIT
├── cloud-node-setup.sh             # Hetzner validator + wallet
├── runpod-bootstrap.sh             # RunPod GPU miner (recommended)
├── vast-miner-bootstrap.sh         # Vast.ai GPU miner (fallback, less reliable)
├── garage-rig-setup.sh             # (optional) owned hardware
├── dashboard.sh                    # local monitoring
└── .btx-dashboard.conf.example     # dashboard config template
```

Paste the packet into Claude, follow along, mine BTX.
