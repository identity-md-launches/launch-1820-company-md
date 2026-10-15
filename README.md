# Company.md (COMD)

`src/CompanyToken.sol:CompanyToken` is an immutable ERC-20 token built on
OpenZeppelin Contracts v5.0.2. Its constructor takes **no arguments** and mints
the entire supply once to `msg.sender`, the address executing deployment.

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `CompanyToken` |
| Token name | `Company.md` |
| Symbol | `COMD` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Base-unit supply | `1000000000000000000000000000` |
| Constructor arguments | None (`[]`) |
| Initial recipient | Deployer (`msg.sender`) |

## Behavior and assumptions

The brief specifies a fixed supply and no custom transfer rules, so this project
uses standard ERC-20 transfers and allowances. Successful `transfer`, `approve`,
and `transferFrom` return `true`; invalid operations revert with OpenZeppelin's
ERC-6093 custom errors. Transfers arrive in full, with no fees, taxes, reflections,
or rebasing. Zero-value transfers are accepted and emit `Transfer`; transfers to
the zero address and approvals to the zero spender are rejected.

There is no owner, minter, pause, blacklist, seizure, burn, permit, proxy, or
upgrade function. The deployer has only the same rights as any other holder after
deployment. Internal mint and burn routines inherited from ERC-20 have no public
entry points. The total supply remains fixed forever.

Finite allowances decrease on delegated transfers. An allowance of
`type(uint256).max` follows standard OpenZeppelin semantics and does not decrease.
`approve` replaces the existing allowance; `approve(spender, 0)` revokes it.
Explicit approvals emit `Approval`. This OpenZeppelin version does not emit
`Approval` when `transferFrom` spends an allowance, so integrations should query
`allowance` rather than reconstructing it solely from events.

## Build and test

Run these commands from the repository root with Foundry and Solidity 0.8.26
available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x38f9c7d307e50a6265ee78094b51d9d57fa3893b28bb8d20addbc21a6acf0fcc forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun EVM, optimizer enabled with 200 runs,
and `bytecode_hash = "none"`. Dependency sources and licenses are ordinary files
under `lib/`; no package install, network access, submodules, environment values
inside tests, FFI, or filesystem cheatcodes are required. The verifier supplies
the pinned compiler offline. Build output and cache are disposable.

The suite has 28 tests, including four fuzz tests at 1,000 cases each. It covers
metadata, exact supply and mint event, EOA and CREATE2 contract deployment,
whole-supply transfers, launch distribution and claims, event emission, zero and
self transfers, allowance spending, revocation, unlimited approvals, overdraws,
unauthorized transfers, invalid addresses, revert rollback, supply conservation,
and rejection of common privileged selectors. It also scans runtime opcodes for
DELEGATECALL, CALLCODE, and SELFDESTRUCT and checks the EIP-170 size bound.

The factory/distributor/pool-manager identities in tests are local fixtures, not
production configuration. The distribution test checks exact ERC-20 movements;
it does not simulate Uniswap pricing, liquidity accounting, or actual swaps.
The supplied protected launch harness is read as acceptance input; its external
factory, Uniswap helpers, manifest, and deployment environment belong to the
separate launch verifier and are not reproduced here.

## Deployment and operational responsibilities

Deploy `CompanyToken` directly from its creation bytecode, with no initialization
calls or constructor arguments. Do not deploy it through a proxy. Deployment
performs no external calls and requires no registry, oracle, signer, or owner
address. When the IdentityMD factory deploys it, the factory receives the entire
supply; for direct wallet deployment, that wallet receives it. The original
transaction sender is not substituted for the immediate deploying address.

The intended launch chain is Ethereum (chain ID 1). The separate IdentityMD
launch process controls distribution, pool creation, and its manifest. No token
allocation or pool logic is embedded in this contract, and no `launch.json` is
provided. This assignment builds artifacts and does not broadcast transactions.

Before launch, the deployer must confirm the chain, deployment bytecode, empty
argument list, token metadata, and exact base-unit supply against the final
manifest. After deployment it must verify source and constructor details on the
explorer and confirm the initial mint recipient and balance. Distribution is the
launch factory's responsibility. No token administration, post-launch settings,
maintenance calls, keys, or privileged operator are required.

Holders control their transfers and approvals. They should grant only necessary
allowances and revoke unused approvals. When changing an existing nonzero
allowance, use a confirmed revocation before granting the new amount to mitigate
the standard ERC-20 approval ordering race. Tokens sent to this token contract
or an incompatible recipient contract cannot be recovered by an administrator.

The local security review checked constructor-only issuance, authority boundaries,
exact transfer accounting, rollback, arithmetic bounds, and the absence of
external calls and upgrade mechanisms. Foundry build, unit/fuzz tests, and format
checks are the validation tools used; Slither and Mythril were not run. These
checks do not constitute an independent security audit; independent review and
launch verification remain the release process's responsibilities.
