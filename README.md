# BTX Mining For Dummies

**BTX** ([btxchain/btx](https://github.com/btxchain/btx)) is a new cryptocurrency, launched March 2026, that you cannot buy anywhere — no exchange lists it. The only way to acquire it is to mine it. This repo is a complete, opinionated playbook for doing that with rented cloud hardware, written to be driven by [Claude Code](https://claude.com/claude-code) so the operator can be technically literate without being a developer, sysadmin, or crypto-native.

You paste the packet into Claude. Claude explains each concept, walks you through every step, and catches the known mistakes before they cost money. You end up with a running pool miner, a wallet you control, and a way to verify — on-chain, trusting no one — that you're actually being paid.

Everything here is distilled from three months of real deployments (May–July 2026): through provider failures, a chain fork, and a mid-course pivot from solo to pool mining. Every gotcha documented below cost real time or money to learn. If you don't know what "mining," "pool," or "wallet node" mean yet, there's a [plain-English explainer](#how-it-works-in-plain-english) below.

Published by [Matty Mo Studio](https://themostfamousartist.com).

---

## ⚠️ July 2026 status update — read this before anything else

This playbook was first published in May 2026. **The chain and the playbook both changed materially in June 2026.** If you cloned this repo before July 2026, re-read everything. What happened:

1. **The chain forked in mid-June 2026.** Between June 5–16 the project shipped 13 releases containing six-plus *mandatory* consensus activations (heights ~123,000–135,000), some announced roughly a day before activation. Nodes running v0.31.0 or older — including nodes set up by earlier versions of this playbook — got stranded on a dead fork around height ~125,600. No public postmortem was ever published. **If your node's block height is stuck near 125,600, you are on the dead fork** (see the troubleshooting cookbook for how to recover — coins mined *before* the divergence are typically safe on the canonical chain, but verify).

2. **The release-signing key changed without announcement.** Binaries from ~v0.32.9 onward are signed by a new key (`C55C98C7…CD566156`, "BTX Release Maintainer <release@btx.local>", created 2026-06-13) instead of the long-standing developer key that signed everything before. There is no cross-signature from the old key, no note in SECURITY.md, and git tags are no longer signed. A sloppy-but-legitimate rotation and a compromised release pipeline look identical from the outside. **This playbook now builds from source and never trusts auto-update.**

3. **Solo mining on cloud GPUs doesn't work.** Empirically, NAT'd cloud containers lose the large majority of found blocks to orphaning (we measured 3 of 4 blocks orphaned) — they sit at the edge of the network and lose propagation races. **Pool mining now exists and is the recommended path** (this reverses the original playbook's architecture). Pool mode is also dramatically simpler: no local node, no chain sync, hashing within about a minute of renting a box.

4. **Facts worth knowing before you spend money** (all verifiable from public sources — the project's own site, repo, and chain data):
   - The team is fully anonymous ("BTX Developers"); releases are published by two GitHub accounts.
   - The first 50,000 blocks were mined at a compressed cadence into a team-controlled "genesis multisig" — effectively a **~1M BTX (~4.76% of max supply) premine** whose spending policy the project's own spec says should be documented, but never was. Its stated purposes include providing "early market depth" — i.e., the team intends to make markets itself.
   - The shielded transaction pool was sunset in June via emergency-shaped consensus changes (forced-exit transactions, drain RPCs, velocity quotas). No cause was ever stated.
   - Project documentation has not been updated since 2026-03-30 — it predates and does not mention any of the above.
   - **There is still no exchange listing and no executable market.** [btxprice.com](https://btxprice.com) publishes model values, not trades; the OTC site is a non-binding lead-matching desk. Coins you mine mark to ~$0 until a real venue exists.

**Our own posture after learning all this: we kept existing miners running at marginal cost and stopped adding capital.** This repo remains published because the operational knowledge is real and hard-won — but the honest frame has shifted from "speculative bet" to "speculative bet on a chain with a live disclosure problem." Size accordingly.

---

## How it works, in plain English

**The chain.** BTX is a Bitcoin-family cryptocurrency with two twists. First, the "work" miners perform is enormous integer matrix multiplication — the same math AI chips are built for — so mining runs on ordinary GPUs rather than specialized Bitcoin hardware. Second, its signatures use post-quantum cryptography, designed to survive future quantum computers. It launched in March 2026, and that youth is the entire reason this playbook exists: a young chain has little mining competition, so a single rented GPU still earns meaningful coin. That window narrows every week as more miners arrive.

**Mining.** Roughly every 90 seconds the network runs a lottery: mining machines churn through the matrix math, and the first to find a winning answer adds the next block to the ledger and earns 20 BTX. Your odds are exactly your slice of the network's total compute.

**Why a pool.** Solo mining is jackpot-or-nothing — a single GPU might win twice in a day, then nothing for a week. A mining pool is the office lottery syndicate: thousands of GPUs buy tickets together, and winnings are split in proportion to the work ("shares") each machine contributed. You trade the jackpot for a steady trickle. On this network, the pool isn't just about smoothing variance — it's essential: a lone cloud GPU that *does* win a block usually can't announce it to the network fast enough, and its win gets discarded ("orphaned"). We measured this: 3 of our 4 solo-found blocks evaporated. The pool has the network position to make wins stick.

**The two machines you'll rent.**
- A **GPU box** (Vast.ai, roughly $0.50/hr) that does nothing but math and submits shares to the pool. It holds no coins, no keys, and no ledger — if it dies, you re-rent another and lose nothing.
- A **wallet node** (Hetzner, ~$46/mo) that is your vault and your auditor: it holds the cryptographic keys that control your coins, and it maintains your own independent copy of the BTX ledger, so you can confirm the pool actually paid you without taking anyone's word for it.

**The money flow.** GPU box submits shares → pool credits your account → every pay period the pool sends BTX to your address → the wallet node's keys control that address → you verify the payment against your own copy of the ledger.

**Claude's role.** `CLAUDE_PACKET.md` is a runbook: the architecture, every command, and every known failure mode. Claude Code reads it and becomes your operator — explaining what each step is for, executing it with you, and recognizing the documented errors when they appear. You supply judgment and credit cards; Claude supplies the sysadmin.

---

## What this is

A repo containing:
- **`CLAUDE_PACKET.md`** — paste this into Claude Code as context. Claude reads it and helps you execute every step, troubleshoots known errors, and stops you before predictable mistakes.
- **`vast-pool-bootstrap.sh`** — **recommended path.** Vast.ai GPU box → pool miner via [matador-miner](https://github.com/vanities/matador-miner). No node, no sync, hashing in ~1 minute, reboot-proof.
- **`cloud-node-setup.sh`** — Hetzner CPX41 (Ubuntu 24.04) → BTX validating node + wallet host. Where your payout address lives and where you verify payouts on-chain.
- **`dashboard.sh`** — local terminal dashboard (wallet sync, balance split, spend, break-even). Written for the original solo architecture; wallet-side panels still apply.
- **`runpod-bootstrap.sh`** / **`vast-miner-bootstrap.sh`** / **`garage-rig-setup.sh`** — the legacy *solo-mining* scripts. Kept for reference and for owned-hardware setups with real inbound connectivity. **Not recommended on cloud** (see status update above).

The packet captures every operational gotcha learned from real deployment — including the ones that cost real money the first time around.

---

## ⚠️ Read before you start

**This is a speculative bet with a live disclosure problem** (see the July 2026 status update above). BTX has no exchanges, no market price, no liquid OTC. Coins you mine cannot be sold today. If BTX never lists, your spend is a loss.

**Expected costs (pool path):**
- GPU box (Vast.ai RTX 5090): **~$0.45-0.60/hr ≈ $330-440/month** at 24/7
- Wallet node (Hetzner CPX41): **~$46/month** — needed to hold keys and verify payouts
- Pool fee (~2.5% at minebtx) + matador-miner's mandatory 1% dev fee

**Expected yield:** as of early July 2026, a single RTX 5090 in pool mode earned on the order of a few BTX per day, paid in batches per pool pay period. Network hashrate is growing, so expect this to decline. None of it can currently be sold.

**Don't run this with money you can't afford to lose entirely.**

---

## Quick start

1. **Clone this repo:**
   ```bash
   git clone https://github.com/mattymostudio/btx-mining-for-dummies.git
   cd btx-mining-for-dummies
   ```

2. **Open Claude Code in this directory:**
   ```bash
   claude
   ```

3. **Hand Claude the packet:**
   ```
   Please read CLAUDE_PACKET.md and walk me through BTX pool-mining setup. I'm a layperson — go slow, confirm each step.
   ```

4. **Follow Claude's instructions.** It will guide you through:
   - Creating a wallet node on Hetzner (~30 min active + sync time in the background)
   - Renting a GPU box and starting the pool miner (~15 min, hashing almost immediately)
   - Verifying shares are being accepted (~5 min)
   - Verifying payouts actually land at your address on the canonical chain

5. **Total active time: ~1-2 hours.** Pool mode removed the old 24-36 hour sync bottleneck on the miner side.

---

## What you'll end up with

```
┌────────────────────┐          ┌──────────────────────┐
│  Vast.ai GPU box   │──shares─►│  Mining pool         │
│  (matador-miner,   │          │  (stratum.minebtx.com│
│   no node, no sync)│          │   + failover)        │
└────────────────────┘          └──────────┬───────────┘
                                            │ batched payouts
                                            ▼
                                 your payout address
                                            ▲
┌────────────────────┐                      │
│  Hetzner CPX41     │── holds the keys ────┘
│  (wallet + node)   │   verifies payouts on-chain
│  ~$46/mo           │   (scantxoutset)
└────────────────────┘
```

The GPU box holds **no keys and no chain state** — it can die at any moment and you lose nothing but rental time. The wallet node is where your address lives and where you independently verify the pool is actually paying you.

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

## What's in this repo

| File | Purpose | Where it runs | Status |
|---|---|---|---|
| `CLAUDE_PACKET.md` | The brain — Claude reads this to guide you | Claude Code context | current |
| `vast-pool-bootstrap.sh` | Pool miner via matador-miner (**recommended**) | Vast.ai CUDA container | current |
| `cloud-node-setup.sh` | Validating node + wallet on Hetzner | Hetzner Ubuntu 24.04 | current |
| `dashboard.sh` | Local monitoring (wallet side) | Your laptop | partial — solo-era |
| `runpod-bootstrap.sh` | Solo GPU miner on RunPod | RunPod pod | legacy |
| `vast-miner-bootstrap.sh` | Solo GPU miner on Vast | Vast.ai container | legacy |
| `garage-rig-setup.sh` | Owned-hardware solo miner | Your own Ubuntu box | legacy |

---

## Honest tradeoffs vs other approaches

| Approach | Upfront | Monthly | Pros | Cons |
|---|---|---|---|---|
| **Pool on cloud GPU (this playbook)** | $0 | ~$380-490 | No node, hashing in minutes, box death is free, paid per share | Pool + dev fees, must trust pool to pay (verify on-chain!) |
| **Solo on cloud GPU (legacy)** | $0 | ~$350-750 | Full 20 BTX block reward | **~75% of blocks orphan on NAT'd containers** — don't |
| **Owned rig, solo or pool** | $3,500-4,500 | ~$51 power | Best long-term unit economics | High commit to a chain with disclosure problems |

---

## FAQ

**Can I sell the BTX I mine?**
Not today. No exchange lists it, and there is no functioning over-the-counter market. That is the entire bet: you're spending real dollars now for coins that are worth something only if a real market ever exists. See the July 2026 status update above before deciding how you feel about those odds.

**Is this profitable?**
Unknowable. Profit requires a price, and BTX has no market price — only theoretical models. Anyone quoting you an ROI is making it up.

**Can I mine on my gaming PC or laptop?**
The software technically runs anywhere with a modern GPU, but mining rewards 24/7 uptime on a top-end card. A laptop will earn almost nothing and cook itself. A gaming PC with a 4090/5090 works if you're comfortable running it flat-out around the clock — `garage-rig-setup.sh` covers that path — but this playbook's default is rented cloud GPUs precisely so you don't have to commit hardware to an unproven chain.

**What happens if the GPU box dies?**
Nothing. In pool mode it holds no keys, no coins, and no chain data — you re-rent a new box and paste one script. This is by design; cheap cloud hosts fail constantly.

**How do I know the pool isn't cheating me?**
You don't trust it — you check. Your wallet node keeps an independent copy of the entire ledger, and the playbook includes the exact command (`scantxoutset`) that scans it for payments to your address. If the pool's dashboard says "paid" and your own ledger copy disagrees, you stop mining there. The packet walks you through this verification after your first pay period.

**Why does this need Claude?**
Strictly, it doesn't — an experienced Linux admin could follow the scripts by hand. The packet exists so that someone who *isn't* one can operate this safely: it encodes every failure mode we hit, and Claude recognizes them in real time instead of you discovering them at 2am with a billing meter running.

**Why rent cloud GPUs instead of buying one?**
No upfront cost, no hardware to resell if you quit, and a clean exit at any moment. Owned hardware wins on long-run economics (3-5× cheaper per coin over two years), but committing $3,500+ of hardware to this particular chain requires more conviction than its June 2026 track record currently earns.

---

## License

MIT — see [LICENSE](LICENSE). Use this however you want.

If you find errors, hit pitfalls not in the troubleshooting section, or improve the scripts, **PRs welcome**. The packet's troubleshooting cookbook grows by being shared.

---

## Disclaimer (the boring but important part)

**This is not financial advice. Nothing in this repository constitutes investment, tax, legal, or any other professional advice.** The authors are not financial advisors, brokers, dealers, or registered investment professionals. Any decision you make about whether to mine BTX, how much to spend, or what to do with mined coins is entirely your own responsibility.

BTX mining involves a speculative cryptocurrency where:
- The chain has **already forked once** (June 2026) with no postmortem
- The release-signing key has **already rotated once** without documentation
- Listings may never materialize; there is no market today
- Models published at [btxprice.com](https://btxprice.com) are theoretical — not market prices
- You may spend $1,000+ and recover $0

Run this with money you can lose entirely. The authors of this playbook are not responsible for losses, dead chains, or unmet expectations.

The scripts and packet capture real operational knowledge from real deployments. They are **opinionated** — they pick specific cloud providers, specific pools, specific pinned versions. You can deviate, but the troubleshooting and pitfall-avoidance built into the packet only applies to the documented path.

---

## Credits

Built from operational experience deploying BTX miners on Hetzner, RunPod, and Vast.ai across May–July 2026 — through the June fork, the provider failures, the orphan discovery, and the pivot to pool mining. Every gotcha listed cost time or money to discover.

Published by [Matty Mo Studio](https://themostfamousartist.com).

---

## Repo structure

```
btx-mining-for-dummies/
├── README.md                       # this file
├── CLAUDE_PACKET.md                # the operational packet for Claude
├── LICENSE                         # MIT
├── vast-pool-bootstrap.sh          # pool miner (recommended)
├── cloud-node-setup.sh             # Hetzner validating node + wallet
├── dashboard.sh                    # local monitoring (wallet side)
├── .btx-dashboard.conf.example     # dashboard config template
├── runpod-bootstrap.sh             # legacy: solo miner on RunPod
├── vast-miner-bootstrap.sh         # legacy: solo miner on Vast
└── garage-rig-setup.sh             # legacy: owned-hardware solo miner
```

Paste the packet into Claude, follow along, mine BTX — eyes open.
