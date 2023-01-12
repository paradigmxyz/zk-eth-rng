// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import "./IBlockhashOracle.sol";
import "./BlockhashOpcodeOracle.sol";
import "./SingleBlockHeaderVerifier.sol";

/// @title Single block ZK Blockhash Oracle
/// @author AmanGotchu <aman@paradigm.xyz>
/// @author Sina Sabet <sina@paradigm.xyz>
/// @notice ZK based blockhash oracle that proves the parent hash of an already verified block.
contract ZKBlockhashOracle is BlockhashOpcodeOracle, SingleBlockHeaderVerifier {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProof();
    error BlockhashUnvalidated(bytes32 blockHash);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates the block hash of the block before the contract was initialized.
    constructor() {
        poke();
    }

    /// @notice Verifies a proof attesting to a parent blockhash of a block that has already been validated.
    /// @param a Proof a value.
    /// @param b Proof b value.
    /// @param c Proof c value.
    /// @param publicInputs Proof's public inputs (blockHash, parentHash, blockNum).
    function verifyParentHash(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[198] memory publicInputs
    ) public returns (bool) {
        /// Parse relevant information from the proof's public inputs.
        // First 32 bytes are the anchored block hash.
        uint256 i = 0;
        bytes32 blockHash;
        for (; i < 64; i++) {
            blockHash <<= 4;
            blockHash |= bytes32(publicInputs[i]);
        }

        // Next 32 bytes are the parentHash.
        bytes32 parentHash;
        for (; i < 128; i++) {
            parentHash <<= 4;
            parentHash |= bytes32(publicInputs[i]);
        }

        // Next 3 bytes are the anchored block's number.
        bytes32 blockNumAccumulator;
        for (; i < 134; i++) {
            blockNumAccumulator <<= 4;
            blockNumAccumulator |= bytes32(publicInputs[i]);
        }
        uint256 blockNum = uint256(blockNumAccumulator);

        // If the anchored block hash hasn't been validated, we can try to validate using blockhash opcode.
        if (blockhashToBlockNum[blockHash] == 0) {
            bytes32 blockHashFromOpcode = blockhash(blockNum);

            // If blockhash out of range of opcode, return BlockhashUnvalidated.
            if (blockHashFromOpcode == 0) {
                revert BlockhashUnvalidated(blockHash);
            }

            // If within range and doesn't match blockhash from proof, return InvalidProof.
            if (blockHashFromOpcode != blockHash) {
                revert InvalidProof();
            }
            
            setValidBlockhash(blockHash, blockNum);
        }

        // After fulfilling pre-reqs, we can verify the proof.
        if (!verifyProof(a, b, c, publicInputs)) {
            revert InvalidProof();
        }

        setValidBlockhash(parentHash, blockNum - 1);
        return true;
    }
}
