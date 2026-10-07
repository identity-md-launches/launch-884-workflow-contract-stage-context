// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply Quantum Observatory token. The launch factory distributes the supply.
contract LaunchToken is ERC20 {
    constructor() ERC20("Quantum Observatory", "QOBS") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
