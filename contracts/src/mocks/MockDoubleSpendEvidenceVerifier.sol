// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDoubleSpendEvidenceVerifier} from "../interfaces/IDoubleSpendEvidenceVerifier.sol";

/// @notice Mock evidence verifier that always returns true. For tests only.
contract MockDoubleSpendEvidenceVerifier is IDoubleSpendEvidenceVerifier {
    function verifyDoubleSpendEvidence(bytes calldata, bytes32) external pure returns (bool) {
        return true;
    }
}
