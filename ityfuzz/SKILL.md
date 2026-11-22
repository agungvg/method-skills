# ItyFuzz — Snapshot-Based Hybrid Fuzzer for EVM Smart Contracts

Blazing-fast bytecode-level hybrid fuzzer (LibAFL + symbolic/concolic execution)
that finds bugs in Solidity contracts **without you writing a harness**: it
deploys the compiled artifacts on a clean local chain, mutates transaction
sequences, and reports violations from built-in oracles (reentrancy, ERC20 /
pair misuse, arbitrary calls, arithmetic, selfdestruct, …). It can also run
Foundry invariant tests and fuzz deployed contracts via fork.

Official sources: github.com/fuzzland/ityfuzz · docs.ityfuzz.rs · ISSTA'23
paper (Shou, Tan, Sen). License MIT.

## Install (verified 2026-11-22 on this VM)

Recommended install is the official `ityfuzzup` script, which downloads a
prebuilt nightly binary (no compile, no Z3 build):

```bash
export ITYFUZZ_DIR=~/workspace/tools/ityfuzz-bin   # keep it under workspace, durable
bash ~/workspace/tools/ityfuzz/ityfuzzup/ityfuzzup  # or: curl -L https://ity.fuzz.land/ | bash && ityfuzzup
~/workspace/tools/ityfuzz-bin/bin/ityfuzz --version
# ityfuzz fb4e87a36ae3b4596fe74178004d1b51e4cfcad5["cmp,dataflow,evm,force_cache,full_trace,print_txn_corpus,real_balance,"]
```

- Binary: `~/workspace/tools/ityfuzz-bin/bin/ityfuzz` (~57 MB nightly).
- Source checkout (for reading detector/oracle code, not needed to run):
  `~/workspace/tools/ityfuzz` (clone of github.com/fuzzland/ityfuzz).
- Build-from-source alternative (slow, only if the binary won't run):
  Rust nightly-2024-01-01 (see `rust-toolchain.toml` in the repo), then
  `cargo build --release` in the repo. The `z3` crate links Z3 statically,
  so no system `libz3-dev` is needed.
- Rust toolchain already on this VM: `~/workspace/tools/cargo/bin/cargo`
  (export it onto `PATH` first).

## Project setup — what it fuzzes

Offline mode fuzzes a directory of compiled artifacts. It needs one
`[X].abi` + `[X].bin` pair per contract (solc output). Any solc works; on
this VM Foundry's cached solc is fastest:

```bash
mkdir -p lab/artifacts
~/.svm/0.8.20/solc-0.8.20 --bin --abi --overwrite -o lab/artifacts lab/src/Vault.sol
# or: forge build, then extract .abi/.bin from out/ artifacts
```

Caveats for the target directory:

- ItyFuzz deploys **all** artifacts in the directory onto a clean chain with
  no other contracts. If your target depends on other contracts (ERC20,
  Uniswap, …), deploy them too — put their artifacts in the same directory
  or use a Foundry deployment script (`-m path/Deploy.s.sol:Deploy`, the
  fuzzer calls its constructor / `setUp()`).
- Constructor arguments: `--constructor-args "<arg1>;<arg2>"` (see
  docs.ityfuzz.rs "Constructor Arguments for Offchain Fuzzing").
- The vault starts with balance 0; the fuzzer funds it by calling payable
  functions itself (it uses EOA callers plus contract callers whose
  `fallback()` re-enters the target).

## Running a campaign

```bash
cd lab
~/workspace/tools/ityfuzz-bin/bin/ityfuzz evm -t 'artifacts/*' -w work_dir
```

- `-t` is a glob (offline) or an address (onchain, see below).
- `-w` is the work dir: corpus, coverage, traces, and any findings land
  here. Reuse the same `-w` to resume from the saved corpus.
- By default the fuzzer **exits as soon as it finds a bug**. Add
  `--run-forever` to keep hunting after the first finding.
- There is no wall-clock timeout flag: wrap it in `timeout 600 …` or run
  it under `nohup … &` and watch the log. Progress lines look like:
  `run time: 0h-1m-38s, clients: 1, corpus: 8, objectives: 0, executions: 2517793, exec/sec: 25.66k`
  (~20–25k exec/s on this VM, 1.5 shared vCPU).

### Detectors — READ THIS FIRST

```bash
ityfuzz evm -t 'artifacts/*' -d <detectors>   # default: high_confidence
```

The detector set is the difference between finding a bug and missing it:

| `-d` value | Oracles enabled |
|---|---|
| `high_confidence` (default) | erc20, pair, arbitrary_call, echidna, typed_bug, selfdestruct, invariant |
| `all` | all of the above **plus reentrancy, math_calculate, state_comparison** |
| `reentrancy` (or any comma list, e.g. `reentrancy,erc20`) | exactly the named ones |

**The default set does NOT include the reentrancy oracle.** Verified on the
lab Vault below: default run did 10,861,590 executions over 7m24s with
`objectives: 0` and found nothing; `-d reentrancy` found the bug in
257 executions (<70 s). Always run with `-d all` for a real campaign unless
you have a reason to narrow it (verified in `src/evm/mod.rs`,
`OracleType::from_strs`).

Other useful flags: `--concolic` (experimental concolic execution),
`-f/--flashloan` (assume attacker has flash-loan funds),
`--seed <n>` (reproduce a run), `--load-corpus <dir>` (resume),
`-m test/Invariant.sol:Invariant -- forge test` (run a Foundry invariant
test under ItyFuzz instead of `forge test`).

### Onchain (deployed contracts) — NOT verified locally, documented only

```bash
ETH_RPC_URL=https://polygon-rpc.com ityfuzz evm \
  -t 0xTargetAddress -c polygon \
  --onchain-block-number 35718198 \
  --onchain-etherscan-api-key <key> [--flashloan]
```

Needs an Etherscan-family API key for source/ABI fetching and an RPC URL
(`ETH_RPC_URL` env or `-u`). Chain types: `eth, bsc, polygon, arbitrum,
optimism, base, …` (`--help` lists them). No key is stored anywhere in this
skill; pass it on the command line per run.

## Verified run (2026-11-22) — planted reentrancy, found

Target (`lab/src/Vault.sol`, compiled with solc 0.8.20): a vault whose
`withdraw()` sends ETH **before** zeroing the balance:

```solidity
function withdraw() external {
    uint256 bal = balances[msg.sender];
    require(bal > 0, "nothing to withdraw");
    (bool ok, ) = msg.sender.call{value: bal}("");
    require(ok, "send failed");
    balances[msg.sender] = 0;   // <-- too late: re-entered call already drained
}
```

Commands (lab at `~/workspace/tools/ityfuzz-lab`, artifacts in `artifacts/`):

```bash
~/workspace/tools/ityfuzz-bin/bin/ityfuzz evm -t 'artifacts/*' -d reentrancy -w work_dir_vault2
```

Observed output (run 1, default detectors — **missed**):

```
run time: 0h-7m-24s, clients: 1, corpus: 8, objectives: 0, executions: 10861590, exec/sec: 24.42k
```

Observed output (run 2, `-d reentrancy` — **found in 257 executions**):

```
😊😊 Found vulnerabilities!

================ Description ================
[Reentrancy]: Reentrancy on "artifacts/Vault(0x887db5715868498cff494b5dcc8eda6ce5b7652a)"
  at slot 276416896359542683946398823401879949021604486037763510887513125271436631789
================ Trace ================
[Sender] 0xe1A425f1AC34A8a441566f93c82dD730639c8510
   ├─[1] 0x887dB5715868498Cff494b5Dcc8eDA6CE5B7652a.deposit{value: 4722.3664 ether}()
   ├─[1] 0x887dB5715868498Cff494b5Dcc8eDA6CE5B7652a.withdraw()
   │  ├─[2] [Sender] 0xe1A425f1AC34A8a441566f93c82dD730639c8510.fallback()
   │  │  ├─[3] 0x887dB5715868498Cff494b5Dcc8eDA6CE5B7652a.deposit{value: 32768}()
   │  │  └─[3] 0x887dB5715868498Cff494b5Dcc8eDA6CE5B7652a.call(0x00000000)
```

How it works under the hood (from the repo source): a tracer watches
`SLOAD`/`SSTORE` on each storage slot. When the fuzzer's contract caller
re-enters, the same `balances[attacker]` slot is read at a deeper call depth
and then written — that read-after-external-call + write pattern is flagged
as reentrancy. ItyFuzz also "leaks" the mid-call state (after the external
call, before the balance update) so follow-up transactions execute against
the not-yet-updated state.

## Reading results / triaging a finding into a PoC

Findings are saved under `<work_dir>/`:

- `vulnerabilities/` — one directory per bug (`<id>` and
  `<id>_replayable`) plus a Foundry replay test `Artifacts.t.sol`. That file
  is the PoC: it replays the exact trace with `vm.prank(<attacker>)`
  (deposit → withdraw → re-entered deposit). Copy it into a Foundry project
  and run `forge test` to confirm the exploit independently.
- `vuln_info.jsonl` — machine-readable bug records (`bug_type`,
  `bug_info`, full input trace).
- `coverage.txt` / `coverage.json` — instruction/branch coverage per
  contract (lab Vault: 67.05% instruction, 54.17% branch).
- `traces/` and `corpus/` — per-testcase execution traces and the saved
  corpus (reusable via `--load-corpus`).

Triage checklist before reporting a finding:

1. Read the trace in the banner: does the sequence actually move funds or
   break an invariant, or is it just the pattern (e.g. a reentrancy-shaped
   read/write with no profit)? Re-run the `Artifacts.t.sol` replay and check
   the attacker's end balance vs. start.
2. Confirm the flagged slot is a real accounting variable (the slot number
   is the keccak of the mapping key + slot — map it back with
   `cast keccak` / the storage layout).
3. Check whether the "attacker" is a privileged role in the real deployment
   (owner-only paths are usually by-design, not bugs — see the bug rule in
   memory: only outsider attacks with direct impact on funds/state count).
4. For a custom property (not a built-in oracle), encode it as a Foundry
   invariant test and run it with `-m test/Invariant.sol:Invariant`.

## Limits (what it can't catch)

- **No user-defined invariants in plain mode** — without a Foundry
  invariant harness it only finds what its built-in oracles cover. Business-
  logic bugs (wrong price, wrong accounting that no oracle models) are
  missed unless you write the invariant.
- **Reentrancy oracle is OFF by default** (see Detectors above).
- **Offline = clean chain.** Missing dependencies (oracles, tokens, pools)
  are not deployed for you; coverage of code paths that need them is 0.
- No source needed (bytecode-level), but without source maps the trace
  shows addresses/selectors, not function names — keep the `.abi` files so
  the trace is readable.
- Concolic execution is experimental (`--concolic`); the nightly binary can
  change behaviour between builds — record the version hash with every run.
- Onchain mode needs network + API keys and is slower; flash-loan mode only
  helps if the bug is reachable with borrowed funds.
- It fuzzes EVM only in this mode (MoveVM support is WIP in the repo).

## Safety

Local-only, offline by default. No accounts, no keys, no funds, no
exfiltration: the only network use is the optional onchain mode (RPC +
explorer API, user-supplied). Never point it at a mainnet contract you
don't own with `--flashloan` and live funds — fuzzing is read-only against a
fork, but the generated exploit is real; keep it in the lab.
