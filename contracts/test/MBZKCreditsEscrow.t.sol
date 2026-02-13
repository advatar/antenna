// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {KeccakHasher} from "../src/utils/KeccakHasher.sol";
import {VerifierRegistry} from "../src/VerifierRegistry.sol";
import {MBZKCreditsEscrow} from "../src/MBZKCreditsEscrow.sol";
import {MockZKCreditsVerifier} from "../src/mocks/MockZKCreditsVerifier.sol";
import {MockDoubleSpendEvidenceVerifier} from "../src/mocks/MockDoubleSpendEvidenceVerifier.sol";

contract MBZKCreditsEscrowTest is Test {
    KeccakHasher hasher;
    VerifierRegistry registry;
    MockZKCreditsVerifier spendVerifier;
    MockDoubleSpendEvidenceVerifier evidenceVerifier;
    MBZKCreditsEscrow credits;

    bytes32 constant ZERO_LEAF = bytes32(uint256(0));

    function setUp() public {
        hasher = new KeccakHasher();
        registry = new VerifierRegistry(address(this));

        spendVerifier = new MockZKCreditsVerifier();
        evidenceVerifier = new MockDoubleSpendEvidenceVerifier();

        registry.setVerifier(keccak256("rln-stub-v1"), address(spendVerifier));
        registry.setVerifier(keccak256("evidence-stub-v1"), address(evidenceVerifier));

        credits = new MBZKCreditsEscrow(hasher, ZERO_LEAF, registry, true);
    }

    function testDepositAndConsume() public {
        bytes32 id = keccak256("alice-secret");
        vm.deal(address(this), 1 ether);

        (uint32 leafIndex, bytes32 leaf) = credits.deposit{value: 0.1 ether}(id);
        assertEq(leafIndex, 0);
        assertTrue(leaf != bytes32(0));
        assertTrue(credits.isKnownRoot(credits.root()));

        bytes32 merkleRoot = credits.root();
        bytes32 nullifier = keccak256("nullifier-1");
        bytes32 signalHash = keccak256("signal-1");
        bytes32 verifierId = keccak256("rln-stub-v1");

        uint256[2] memory a = [uint256(1), uint256(2)];
        uint256[2][2] memory b = [[uint256(3), uint256(4)], [uint256(5), uint256(6)]];
        uint256[2] memory c = [uint256(7), uint256(8)];

        credits.consume(merkleRoot, nullifier, signalHash, verifierId, 0, 1, a, b, c);
        assertTrue(credits.nullifierUsed(nullifier));
    }

    function testSlash() public {
        bytes32 id = keccak256("bob-secret");
        vm.deal(address(this), 1 ether);

        credits.deposit{value: 0.2 ether}(id);

        address payable recipient = payable(address(0xBEEF));
        uint256 balBefore = recipient.balance;

        credits.slash(
            id,
            keccak256("evidence-stub-v1"),
            hex"deadbeef",
            keccak256("nullifier-x"),
            recipient
        );

        assertEq(recipient.balance, balBefore + 0.2 ether);

        (bytes32 commitment,uint256 depositWei,address depositor,bool slashed,uint32 leafIndex) = credits.identities(id);
        commitment; depositWei; depositor; leafIndex;
        assertTrue(slashed);
    }
}
