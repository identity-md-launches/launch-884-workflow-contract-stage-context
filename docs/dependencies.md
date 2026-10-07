# Vendored dependencies

Builds and tests require no package download. The following source and licenses are ordinary repository files; no submodule is used.

| Dependency | Version | Included files | Source |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.1.0 | ERC20, IERC20, IERC20Metadata, Context, IERC6093 errors, MIT license | [Tagged release](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0) |
| forge-std | v1.9.7 | Complete `src/` tree and both MIT/Apache licenses | [Tagged release](https://github.com/foundry-rs/forge-std/tree/v1.9.7) |

The forge-std source tarball downloaded from GitHub's v1.9.7 codeload endpoint had SHA-256 `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`. `vendor-sha256.txt` records each delivered dependency file's SHA-256. No installed package or global Solidity library is needed. Forge cheatcode interfaces contain optional APIs such as filesystem/FFI/environment access, but this project's tests do not invoke those capabilities, and the Foundry profile grants no filesystem permissions and disables FFI.

Optional tooling scripts use only the Python standard library (Python 3.10 or newer for reference-vector regeneration). Scientific papers are cited by source links and summarized in original language; full papers are not vendored or required at build time.
