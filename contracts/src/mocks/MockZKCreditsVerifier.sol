// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IZKCreditsVerifier} from "../interfaces/IZKCreditsVerifier.sol";

/// @notice Mock Groth16 verifier that always returns true. For tests only.
contract MockZKCreditsVerifier is IZKCreditsVerifier {
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[5] calldata
    ) external pure returns (bool) {
        return true;
    }
}
