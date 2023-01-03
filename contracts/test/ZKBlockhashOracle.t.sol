// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import "forge-std/StdJson.sol";
import "forge-std/Test.sol";

import "../src/ZKBlockhashOracle.sol";

contract ZKBlockhashOracleTest is Test {
    using stdJson for string;
    using stdStorage for StdStorage;

    ZKBlockhashOracle zkBlockhashOracle;

    // Proof calldata that verifies blockheader of Goerli block 8150160.
    uint256[2] proofA = [
        uint256(bytes32(hex"29b0e5ac6476d71ff50544f78bf93a699b0793928308553249338660fda00703")),
        uint256(bytes32(hex"2ca0b5b9629b981275265776e6a34e44448a1b4e7aca234c7b6b101fda59a1f5"))
    ];
    uint256[2][2] proofB = [
        [
            uint256(bytes32(hex"1c993c951040e7ea4f17b30876339f2d9fe7c895c008ef9a3e39e4a9bb3dcb70")),
            uint256(bytes32(hex"0fc5ad56c8aed67e5262a2d64f73a564ae1b15509f7b83fd715e18ca38c08cb3"))
        ],
        [
            uint256(bytes32(hex"2bf980adcb909672e98b23d4b3cda4a4eb93f1803d9e89ec9ef3c021f7456e5c")),
            uint256(bytes32(hex"1642b91468d0c795cad26f79279800752e8649808c7439d60aa43c6853b5a7fa"))
        ]
    ];
    uint256[2] proofC = [
        uint256(bytes32(hex"2a9340525c337ec7c573aadfe4a9af2cb4139373b8f669c8aa64902458f85ab0")),
        uint256(bytes32(hex"2aec28199f7c0cfddc588e46d44bb75e258e5db05a4416fdbcc0bf2b5654eef6"))
    ];
    uint256[198] proofPublicInputs = [
        uint256(12),
        9,
        6,
        9,
        14,
        15,
        13,
        12,
        2,
        8,
        9,
        10,
        10,
        14,
        3,
        8,
        7,
        6,
        8,
        10,
        8,
        10,
        15,
        5,
        1,
        14,
        15,
        12,
        3,
        5,
        8,
        7,
        4,
        10,
        13,
        8,
        5,
        6,
        8,
        6,
        1,
        6,
        15,
        0,
        7,
        5,
        10,
        0,
        5,
        8,
        6,
        4,
        1,
        3,
        11,
        14,
        6,
        15,
        11,
        14,
        4,
        10,
        5,
        5,
        5,
        2,
        0,
        11,
        4,
        2,
        8,
        15,
        13,
        8,
        9,
        4,
        14,
        5,
        12,
        13,
        12,
        8,
        11,
        4,
        3,
        7,
        10,
        10,
        6,
        12,
        13,
        3,
        11,
        3,
        9,
        12,
        6,
        11,
        15,
        1,
        0,
        11,
        13,
        10,
        6,
        8,
        0,
        0,
        12,
        15,
        5,
        11,
        4,
        0,
        4,
        12,
        15,
        13,
        12,
        2,
        3,
        12,
        4,
        5,
        4,
        3,
        5,
        4,
        7,
        12,
        5,
        12,
        9,
        0,
        2,
        4,
        9,
        8,
        1,
        15,
        3,
        7,
        0,
        6,
        5,
        0,
        9,
        4,
        0,
        6,
        15,
        6,
        10,
        1,
        12,
        4,
        3,
        5,
        0,
        3,
        4,
        1,
        14,
        15,
        2,
        14,
        8,
        2,
        9,
        2,
        7,
        10,
        9,
        5,
        2,
        13,
        7,
        11,
        8,
        4,
        2,
        4,
        10,
        8,
        15,
        5,
        15,
        1,
        5,
        8,
        5,
        4,
        5,
        6,
        0,
        1,
        10,
        14
    ];

    // Proof metadata.
    uint256 proofBlockNumber = 8150160;
    bytes32 proofBlockHash = 0xc969efdc289aae38768a8af51efc35874ad8568616f075a0586413be6fbe4a55;
    bytes32 proofParentHash = 0x520b428fd894e5cdc8b437aa6cd3b39c6bf10bda6800cf5b404cfdc23c454354;

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        zkBlockhashOracle = new ZKBlockhashOracle();
    }

    /// @notice Tests that a proof validates within blockhash opcode range.
    function testCanVerifyValidProofInBlockhashOpcodeRange() public {
        uint256 testBlock = proofBlockNumber + 256;
        vm.roll(testBlock);

        // Both proof's block hash and parent blockhash are not be verified before the proof.
        uint256 unverifiedBlockNumber = zkBlockhashOracle.blockhashToBlockNum(proofBlockHash);
        assertEq(unverifiedBlockNumber, 0);
        uint256 unVerifiedParentBlockNumber = zkBlockhashOracle.blockhashToBlockNum(proofParentHash);
        assertEq(unVerifiedParentBlockNumber, 0);

        // TODO(aman): Figure out how to mock blockhash opcode itself instead of contract storage.
        mockBlockhashOracle(proofBlockHash, proofBlockNumber);

        // Proof is verified.
        bool verified = zkBlockhashOracle.verifyParentHash(proofA, proofB, proofC, proofPublicInputs);
        assertTrue(verified);

        // Both proof's block hash and parent blockhash are verified.
        uint256 verifiedBlockNumber = zkBlockhashOracle.blockhashToBlockNum(proofBlockHash);
        assertTrue(verifiedBlockNumber != 0); // TODO(aman): Change this after mocking blockhash opcode.
        uint256 verifiedParentBlockNumber = zkBlockhashOracle.blockhashToBlockNum(proofParentHash);
        assertEq(verifiedParentBlockNumber, proofBlockNumber - 1);
    }

    function testCanVerifyValidProofOutsideBlockhashOpcodeRange() public {
        uint256 testBlock = proofBlockNumber + 257;
        vm.roll(testBlock);

        // Mock blockhash validity. The proof's blockhash must already be validated to validate the proof's parent hash.
        mockBlockhashOracle(proofBlockHash, proofBlockNumber);

        bool verified = zkBlockhashOracle.verifyParentHash(proofA, proofB, proofC, proofPublicInputs);
        assertTrue(verified);
    }

    function testCannotVerifyValidProofOutsideBlockhashOpcodeRange() public {
        uint256 testBlock = proofBlockNumber + 257;
        vm.roll(testBlock);

        // Proof's block hash isn't validated which results in a failed parent hash verification.
        vm.expectRevert(abi.encodeWithSelector(ZKBlockhashOracle.BlockhashUnvalidated.selector, proofBlockHash));

        zkBlockhashOracle.verifyParentHash(proofA, proofB, proofC, proofPublicInputs);
    }

    function testCannotVerifyIncorrectProof(uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) public {
        uint256 testBlock = proofBlockNumber + 100;
        vm.roll(testBlock);

        // Mock proof's block hash to be valid.
        mockBlockhashOracle(proofBlockHash, proofBlockNumber);

        // Expect a revert from verifying an invalid proof.
        vm.expectRevert();
        zkBlockhashOracle.verifyParentHash(a, b, c, proofPublicInputs);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mocks the block hash oracle's response for a validity check.
    function mockBlockhashOracle(bytes32 blockHash, uint256 response) internal {
        stdstore.target(address(zkBlockhashOracle)).sig("blockhashToBlockNum(bytes32)").with_key(blockHash).checked_write(
            response
        );
    }
}
