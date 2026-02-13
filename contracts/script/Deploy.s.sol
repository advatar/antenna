// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {KeccakHasher} from "../src/utils/KeccakHasher.sol";
import {VerifierRegistry} from "../src/VerifierRegistry.sol";
import {MBZKCreditsEscrow} from "../src/MBZKCreditsEscrow.sol";

/// @notice Reference deployment script.
/// @dev This script deploys:
/// 1) KeccakHasher (for testnets only)
/// 2) VerifierRegistry
/// 3) MBZKCreditsEscrow
///
/// After deployment, set verifiers in the registry with `setVerifier(bytes32 id, address verifier)`.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        KeccakHasher hasher = new KeccakHasher();
        VerifierRegistry registry = new VerifierRegistry(msg.sender);

        MBZKCreditsEscrow credits = new MBZKCreditsEscrow(
            hasher,
            bytes32(uint256(0)), // zeroLeaf
            registry,
            false // enforceNullifiers: start false; enforce off-chain first
        );

        console2.log("KeccakHasher:", address(hasher));
        console2.log("VerifierRegistry:", address(registry));
        console2.log("MBZKCreditsEscrow:", address(credits));

        vm.stopBroadcast();
    }
}
