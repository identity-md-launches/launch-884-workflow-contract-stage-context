# Contract-stage deployment handoff

This document is configuration guidance for the manifest and service stages. It is not a deployment transaction, attestation, admission decision, or launch manifest.

## Artifacts and constructors

| Role | Compiler identifier | Constructor ABI | Manifest arguments |
| --- | --- | --- | --- |
| Launch token | `src/LaunchToken.sol:LaunchToken` | `constructor()` nonpayable | `[]` |
| Application | `src/QuantumEngine.sol:QuantumEngine` | `constructor(address token_)` nonpayable | `["$token"]` |

The launch kind is `evm_project`; the token identifier is `LaunchToken`. The application list contains only `QuantumEngine`. Deploy the token before the engine. `QuantumModel` is an internal library embedded in the engine, requiring no deployment or link addresses. No proxy, initialization transaction, owner parameter, or initialization call exists.

The engine constructor must reference the launch token, not the pair token, factory, owner wallet, or an arbitrary ERC-20. The code-existence check is deliberately only a basic input check; it is the manifest review's responsibility to verify this linkage. No privileged address is hard-coded. `msg.sender` is used in the token constructor solely to mint the entire fixed supply to the deploying factory. Engine construction leaves that supply untouched.

## Reproducible settings

Use the committed `foundry.toml`: solc `0.8.26`, Cancun, optimizer enabled with 200 runs, and no bytecode metadata hash. Keep the compiler-version metadata trailer; `bytecode_hash = "none"` is the required setting, not a request to hand-edit runtime bytes. The engine token address is an immutable embedded by its constructor and must be considered when comparing deployed runtime.

Dependencies are vendored; see [dependencies.md](dependencies.md). `forge build` emits artifacts into `out/`. `python3 tools/export_abi.py` exports the compiler ABIs to `docs/abi/`; `--check` verifies the delivered copies without modifying them. Python is not required by `forge build` or `forge test`.

## Parameters owned by later stages

The approved target is **Ethereum mainnet, chain ID 1**. No deployed addresses, transaction hashes, production RPC endpoint, signed policy, or public website URL is supplied or invented here. The manifest contributor and services obtain actual network configuration and the pinned policy through their own authorized handoff.

Use the canonical platform pool guidance: native ETH pairing by default, unless policy selected the permitted network pair token; canonical admission fee `3000`, tick spacing `60`, legacy sqrt price `79228162514264337593543950336`. The deployer derives the effective opening price from the policy and reads the actual trading fee from the chain's LaunchFees. Confirm the requester's liquidity allocation from policy. No source constructor here takes a pool, pair currency, fee, or owner argument.

ProjectFactory supplies MerkleDistributor and PoolInitializationGuard. The contributor application list must not duplicate those protocol artifacts. Policy linkage, signatures, reward allocation, admission, and deployment belong to services, not to additional application contracts. Any concrete mismatch between source, constructor arguments, or authorization remains a review finding.

## Service and frontend responsibilities

1. The manifest assignment generates only `launch.json` describing the accepted token and engine source.
2. An independent contributor reviews accepted contracts, constructor arguments, manifest references, bounded storage/gas behavior, immutable roles, and model/user-input assumptions. Resolve concrete findings before release. The builder's notes in `security.md` are not that independent review.
3. Services publish source to GitHub, produce/link attestations and policy, admit, deploy through the authorized ProjectFactory, and verify source with the exact compiler settings. The contracts need no post-deployment initialization. No contributor wallet or private key is needed for this task.
4. Services hand over chain ID, token and engine addresses, deployment block/transactions, exact poolKey, policy/effective fees, verified-source links, and website publication configuration. Initial epoch time is the engine deployment block's timestamp.
5. The frontend connects a wallet on chain ID 1, reads both ABIs, shows verified deployed addresses, reads token balance and engine state, displays [model.md](model.md), and submits `observe(uint8)` / `advanceEpoch()` with zero ETH value. No token approval is needed. Handle capacity, duplicate, insufficient-balance, expiry, and pending-transaction failures. Re-read state after receipt and on account/chain change; use a common block tag for related reads.
6. The website/IPFS stage publishes a usable site and its public URL. Bind to the exact handed-off poolKey if displaying or interacting with the pool. No pool or website address can be inferred from the source alone.

Operationally, an optional service or any user can call `advanceEpoch` after expiry. Failure to call leaves the epoch closed; there is no automatic timer or keeper reward. Monitor chain confirmations/reorganizations and transaction fees. Model history is reconstructed from logs; no historical-state enumeration is stored in the engine.
