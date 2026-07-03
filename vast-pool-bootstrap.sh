#!/usr/bin/env bash
# Vast.ai BTX POOL-miner bootstrap — matador pool mode (June 2026 pivot).
#
# WHY POOL (replaces the solo bootstraps): solo-on-cloud loses ~75% of found blocks
# to orphaning — cloud containers are NAT'd (connections_in=0), so the node sits at
# the edge of a forky ~90s-block network and loses propagation races. Confirmed
# empirically (3 of 4 found blocks orphaned). Pool mode submits SHARES to a
# well-connected pool, which finds and propagates blocks; payout accrues per-share
# to --payoutaddress regardless of orphans.
#
# Bonus: NO local btxd, NO chain sync, NO snapshot. Box hashes in ~1 min. Death is free.
# Cost: pool fee (~2.5% at minebtx) + the mandatory 1% matador dev-fee + trusting the
# pool to pay out (VERIFY on-chain with scantxoutset — see CLAUDE_PACKET.md Phase 3).
#
# Env (required): BTX_PAYOUT_ADDRESS — YOUR btx1… address. Typos pay a stranger.
# Env (optional): BTX_WORKER — rig label shown in pool stats (default: vast-pool).

set -uo pipefail
ADDR="${BTX_PAYOUT_ADDRESS:?FATAL: export BTX_PAYOUT_ADDRESS=<your btx1... address> first}"
WORKER="${BTX_WORKER:-vast-pool}"
log(){ printf '\n\033[1;36m[matador-pool] %s\033[0m\n' "$*"; }

log "GPU check"
nvidia-smi >/dev/null 2>&1 || { echo "FATAL: no GPU"; exit 1; }
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader || true

log "ensure curl, then install matador-miner (retry on flaky CDN)"
command -v curl >/dev/null || { apt-get update -qq; apt-get install -y -qq curl; }
for a in 1 2 3 4; do
  curl -fsSL --retry 5 https://raw.githubusercontent.com/vanities/matador-miner/main/install.sh | bash
  command -v matador-miner >/dev/null && break
  echo "matador install retry $a"; sleep 5
done
command -v matador-miner >/dev/null || { echo "FATAL: matador-miner did not install"; exit 1; }

log "launch supervised pool miner (worker=${WORKER})"
# --no-update-check is deliberate: given this chain's June 2026 release/key history,
# nothing on this box self-updates. Pin what works.
cat > /root/run-matador.sh <<SUP
#!/usr/bin/env bash
while true; do
  matador-miner --mode pool \\
    --pool stratum+tcp://stratum.minebtx.com:3333 \\
    --pool stratum+tcp://stratum.bitminerpool.xyz:3333 \\
    --payoutaddress ${ADDR} \\
    --worker ${WORKER} --gpus 0 --backend cuda --no-update-check --api --api-port 4060
  echo "[matador] exited \$? — restart 5s"; sleep 5
done
SUP
chmod +x /root/run-matador.sh

# Reboot-proofing: Vast re-runs /root/onstart.sh on every container (re)start. Without
# this, a host reboot silently kills the miner and the box idle-bills — this failure
# cost ~$80 over 6 idle days before we caught it. pgrep guard prevents a second
# supervisor if one is already alive.
cat > /root/onstart.sh <<'ONSTART'
#!/usr/bin/env bash
pgrep -f matador-miner >/dev/null || nohup bash /root/run-matador.sh > /root/matador.log 2>&1 &
sleep infinity
ONSTART
chmod +x /root/onstart.sh

pkill -f run-matador 2>/dev/null; pkill -f matador-miner 2>/dev/null; sleep 1
nohup setsid bash /root/run-matador.sh > /root/matador.log 2>&1 </dev/null & disown 2>/dev/null
sleep 25
echo "============================================================"
echo "pool miner up. worker=${WORKER} payout=${ADDR}"
grep -iE "authorized|job received|share|accepted" /root/matador.log | sed 's/\x1b\[[0-9;]*m//g' | tail -8
nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv,noheader
echo "============================================================"
