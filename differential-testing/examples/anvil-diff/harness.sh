#!/usr/bin/env bash
# anvil-vs-anvil differential harness.
#
# Deploys two implementations of the same fee function to two separate local
# anvil instances, feeds the SAME inputs to both via `cast call`, and diffs
# the outputs. No fork, no mainnet, no network: both chains are throwaway
# local anvils, so this runs fully offline.
#
# Usage:
#   ./harness.sh               # A = correct FeeCalculator, B = buggy one -> expect MISMATCHes
#   ./harness.sh --both-correct # A = B = correct FeeCalculator      -> expect all MATCH
#
# Exit code: 0 when every output matched, 1 when any output differed.
# Requires: anvil, cast, forge on PATH; run `forge build` in ../fee-diff first.
set -u
cd "$(dirname "$0")"

MODE="${1:-}"
if [ "$MODE" = "--both-correct" ]; then
  IMPL_B="FeeCalculator"
  echo "mode: both-correct (A and B deploy the CORRECT implementation)"
else
  IMPL_B="FeeCalculatorBuggy"
  echo "mode: correct-vs-buggy (A correct, B buggy — expect MISMATCHes)"
fi

ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" # anvil account #0 (0xf39F...92266)
PORT_A=8545
PORT_B=8546
URL_A="http://127.0.0.1:$PORT_A"
URL_B="http://127.0.0.1:$PORT_B"

cleanup() {
  kill "$PID_A" "$PID_B" 2>/dev/null
  wait "$PID_A" "$PID_B" 2>/dev/null
}
trap cleanup EXIT

anvil --port "$PORT_A" --silent > anvil-a.log 2>&1 & PID_A=$!
anvil --port "$PORT_B" --silent > anvil-b.log 2>&1 & PID_B=$!
sleep 2

deploy() { # $1 = contract name, $2 = rpc url -> prints address
  # NOTE: forge 1.10 `forge create` is a DRY RUN unless --broadcast is given.
  (cd ../fee-diff && forge create "src/$1.sol:$1" --rpc-url "$2" --broadcast \
    --private-key "$ANVIL_KEY" 2>/dev/null | awk '/Deployed to:/ {print $3}')
}

ADDR_A=$(deploy FeeCalculator "$URL_A")
ADDR_B=$(deploy "$IMPL_B" "$URL_B")
echo "A ($URL_A): FeeCalculator        -> $ADDR_A"
echo "B ($URL_B): $IMPL_B -> $ADDR_B"
[ -n "$ADDR_A" ] && [ -n "$ADDR_B" ] || { echo "deploy failed"; exit 2; }

# Deterministic inputs: 5 hand-picked edge cases + 15 seeded pseudo-random
# pairs (seed 42), so re-runs diff the same inputs. amount < 1e36 keeps
# amount*bps clear of uint256 overflow, same bound as the fuzz tests.
INPUTS=$(python3 -c "
import random
random.seed(42)
cases = [(1,1),(10000,1),(9999,9999),(10**18,500),(123456789,250)]
for _ in range(15):
    cases.append((random.randint(1, 10**30), random.randint(1, 10000)))
for a, b in cases:
    print(a, b)
")

MATCH=0; MISMATCH=0
while read -r AMOUNT BPS; do
  OUT_A=$(cast call "$ADDR_A" "fee(uint256,uint256)" "$AMOUNT" "$BPS" --rpc-url "$URL_A")
  OUT_B=$(cast call "$ADDR_B" "fee(uint256,uint256)" "$AMOUNT" "$BPS" --rpc-url "$URL_B")
  if [ "$OUT_A" = "$OUT_B" ]; then
    MATCH=$((MATCH+1)); echo "MATCH     amount=$AMOUNT bps=$BPS -> $OUT_A"
  else
    MISMATCH=$((MISMATCH+1)); echo "MISMATCH  amount=$AMOUNT bps=$BPS -> A=$OUT_A B=$OUT_B"
  fi
done <<< "$INPUTS"

echo "summary: $MATCH match, $MISMATCH mismatch (of 20 inputs)"
[ "$MISMATCH" -eq 0 ]
