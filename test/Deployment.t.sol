// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {QuantumEngine} from "../src/QuantumEngine.sol";

// Local constructor probe: no keys, broadcast, environment, policy, or chain dependencies.
contract ConstructorFactory {
    function deploy() external returns (LaunchToken token, QuantumEngine engine) {
        token = new LaunchToken{salt: bytes32(uint256(1))}();
        engine = new QuantumEngine{salt: bytes32(uint256(2))}(address(token));
    }
}

contract DeploymentTest is Test {
    function test_factoryRetainsSupplyThroughAllConstructorsAndRuntimeHasNoEscape() public {
        ConstructorFactory factory = new ConstructorFactory();
        (LaunchToken token, QuantumEngine engine) = factory.deploy();
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.balanceOf(address(engine)), 0);
        assertEq(address(engine.token()), address(token));
        _checkCode(address(token).code);
        _checkCode(address(engine).code);
    }

    function _checkCode(bytes memory runtime) private pure {
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
        }
    }
}
