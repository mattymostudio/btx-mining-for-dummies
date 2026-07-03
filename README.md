# BTX Mining For Dummies

**BTX** ([btxchain/btx](https://github.com/btxchain/btx)) is a new cryptocurrency, launched March 2026, that you cannot buy anywhere — no exchange lists it. The only way to acquire it is to mine it. This repo is a complete, opinionated playbook for doing that with rented cloud hardware, written to be driven by [Claude Code](https://claude.com/claude-code) so the operator can be technically literate without being a developer, sysadmin, or crypto-native.

You paste the packet into Claude. Claude explains each concept, walks you through every step, and catches the known mistakes before they cost money. You end up with a running pool miner, a wallet you control, and a way to verify — on-chain, trusting no one — that you're actually being paid.

Everything here is distilled from three months of real deployments (May–July 2026): through provider failures, a chain fork, and a mid-course pivot from solo to pool mining. Every gotcha documented below cost real time or money to learn. If you don't know what "mining," "pool," or "wallet node" mean yet, there's a [plain-English explainer](#how-it-works-in-plain-english) below.

Published by [Matty Mo Studio](https://themostfamousartist.com).

---

## ⚠️ July 2026 update — read this before anything else

This playbook was first published in May 2026. **Both the chain and the playbook changed materially in June 2026.** If you cloned this repo before July 2026, re-read everything. What changed:

1. **The chain went through rapid consensus upgrades in mid-June 2026 — and forked.** Between June 5–16 the project shipped 13 releases carrying six-plus *mandatory* consensus activations (heights ~123,000–135,000), some activating within about a day of release. That's a young chain iterating fast — but the practical consequence is that nodes running v0.31.0 or older, including nodes set up by earlier versions of this playbook, were left on a dead fork around height ~125,600. **If your node's block height is stuck near 125,600, you are on the dead fork** (the troubleshooting cookbook covers recovery — coins mined *before* the divergence are typically intact on the canonical chain, but verify). The playbook now builds every node from current source, so you always carry the latest consensus rules.

2. **The release-signing key changed in June.** Binaries from ~v0.32.9 onward are signed by a new key (`C55C98C7…CD566156`, "BTX Release Maintainer <release@btx.local>", created 2026-06-13) rather than the key that signed earlier releases. Most likely this is routine key housekeeping by a small team moving fast; the write-up just hasn't landed yet. Until it does, the prudent habit — on any chain, this young especially — is the one this playbook uses anyway: **build from source, pin versions, and don't rely on auto-update** (the project itself currently ships with auto-update disabled).

3. **Solo mining on cloud GPUs doesn't work — pools do.** Empirically, NAT'd cloud containers lose most found blocks to orphaning (we measured 3 of 4) — they sit at the edge of the network and lose propagation races. The good news is that the mining ecosystem matured quickly: **pool mining now exists and is the recommended path** (this reverses the original playbook's architecture). Pool mode is also dramatically simpler — no local node, no chain sync, hashing within about a minute of renting a box.

4. **Know what "early" looks like before you spend money.** None of the following is a red flag on its own — it's the honest shape of a small team solving a hard problem, shipping code faster than paperwork. But you should know it going in (all verifiable from the project's site, repo, and chain data):
   - The development team is pseudonymous ("BTX Developers") — not unusual in this space — with releases published by two GitHub accounts.
   - The first 50,000 blocks were mined at a compressed cadence into a team-controlled "genesis multisig" — a reserve of roughly 1M BTX (~4.76% of max supply) earmarked for, among other things, providing early market depth. Documentation of its management policy hasn't caught up yet.
   - The shielded transaction pool was retired in June via consensus changes; the write-up hasn't been published yet.
   - Project documentation (last updated 2026-03-30) trails the code — expect to learn recent history from release notes, community channels, and the chain itself rather than the docs.
   - **There is no exchange listing yet.** [btxprice.com](https://btxprice.com) publishes model values, not trades; the OTC site matches buyers and sellers rather than executing trades. Coins you mine can't be sold today — the value of mining is a position in the chain's future.

**Why we're still mining:** because this might turn into something. A post-quantum chain with a GPU-friendly proof-of-work is a genuinely hard, genuinely early problem, and the team is visibly building — thirteen releases in ten days is a group that shows up. Mining now is how you hold a position, learn the stack, and be part of the community while it's still small. The list above isn't a reason to stay away; it's what being early actually looks like. Just size your spend to it: money you can park indefinitely, on a chain that hasn't listed yet.

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

**This is a speculative, pre-market bet** (see the July 2026 update above). BTX has no exchanges, no market price, no liquid OTC. Coins you mine cannot be sold today — you are accumulating a position in the chain's future. If BTX never lists, your spend is a loss.

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
| **Owned rig, solo or pool** | $3,500-4,500 | ~$51 power | Best long-term unit economics | High upfront commit — validate your economics in the cloud first |

---

## FAQ

**Can I sell the BTX I mine?**
Not today. No exchange lists it, and there is no functioning over-the-counter market yet. That's the nature of the bet: you're spending dollars now to accumulate a position that pays off if and when a real market develops. You're mining conviction, not income.

**Is this profitable?**
Unknowable. Profit requires a price, and BTX has no market price — only theoretical models. Anyone quoting you an ROI is making it up.

**Can I mine on my gaming PC or laptop?**
The software technically runs anywhere with a modern GPU, but mining rewards 24/7 uptime on a top-end card. A laptop will earn almost nothing and cook itself. A gaming PC with a 4090/5090 works if you're comfortable running it flat-out around the clock — `garage-rig-setup.sh` covers that path — but this playbook's default is rented cloud GPUs precisely so you can start without committing hardware.

**What happens if the GPU box dies?**
Nothing. In pool mode it holds no keys, no coins, and no chain data — you re-rent a new box and paste one script. This is by design; cheap cloud hosts fail constantly.

**How do I know the pool isn't cheating me?**
You don't trust it — you check. Your wallet node keeps an independent copy of the entire ledger, and the playbook includes the exact command (`scantxoutset`) that scans it for payments to your address. If the pool's dashboard says "paid" and your own ledger copy disagrees, you stop mining there. The packet walks you through this verification after your first pay period.

**Why does this need Claude?**
Strictly, it doesn't — an experienced Linux admin could follow the scripts by hand. The packet exists so that someone who *isn't* one can operate this safely: it encodes every failure mode we hit, and Claude recognizes them in real time instead of you discovering them at 2am with a billing meter running.

**Why rent cloud GPUs instead of buying one?**
No upfront cost, no hardware to resell if you quit, and a clean exit at any moment. Owned hardware wins on long-run economics (3-5× cheaper per coin over two years) — it's the right move once a month or two of cloud data has validated your own numbers, and `garage-rig-setup.sh` is here for when it does.

---

## License

MIT — see [LICENSE](LICENSE). Use this however you want.

If you find errors, hit pitfalls not in the troubleshooting section, or improve the scripts, **PRs welcome**. The packet's troubleshooting cookbook grows by being shared.

---

## Disclaimer (the boring but important part)

**This is not financial advice. Nothing in this repository constitutes investment, tax, legal, or any other professional advice.** The authors are not financial advisors, brokers, dealers, or registered investment professionals. Any decision you make about whether to mine BTX, how much to spend, or what to do with mined coins is entirely your own responsibility.

BTX mining involves a speculative cryptocurrency where:
- The chain hard-forked during rapid consensus upgrades (June 2026) and may fork again
- The release-signing key rotated in June 2026 without public documentation
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

Paste the packet into Claude, follow along, mine BTX.
