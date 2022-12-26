// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

import "./IBlockhashOracle.sol";
import "./SingleBlockHeaderVerifier.sol";

/// @title Single block ZK Blockhash Oracle
/// @author AmanGotchu <aman@paradigm.xyz>
/// @author Sina Sabet <sina@paradigm.xyz>
/// @notice ZK based blockhash oracle that proves the parent hash of an already verified block. 
contract ZKBlockhashOracle is IBlockhashOracle, SingleBlockHeaderVerifier {
    /// @notice Maps validated blockhashes to their block number.
    mapping(bytes32 => uint256) public blockhashToBlockNum;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PokeRangeError();
    error InvalidProof();
    error BlockhashUnvalidated(bytes32 blockHash);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates the block hash of the block before the contract was initialized.
    constructor() {
        poke();
    }

    /// @notice Returns the block number of a validated block hash.
    /// This doubles as a block hash verifier and a block number oracle.
    /// @param hash Blockhash being verified.
    function blockHashToNumber(bytes32 hash) external view returns (uint256) {
        return blockhashToBlockNum[hash];
    }

    /// @notice Validates the block hash of the block before this tx is called.
    function poke() public {
        uint256 prevBlockNum = block.number-1;
        setValidBlockhash(blockhash(prevBlockNum), prevBlockNum);
    }

    /// @notice Validates the block hash of a specified block number using
    /// the blockhash opcode. The blockhash opcode is currently limited to
    /// 256 blocks in the past. There have been discussions of EIPs that
    /// allow for arbitrary blockhash lookback which makes this blockhash
    /// oracle approach far better.
    /// @param blockNum Block number to validate.
    function pokeBlocknum(uint256 blockNum) public {
        bytes32 blockhashVal = blockhash(blockNum);
        if (blockhashVal == bytes32(0)) {
            revert PokeRangeError();
        }

        setValidBlockhash(blockhashVal, blockNum);
    }

    /// @notice Validates blockhash and blocknum in storage and emits a validated event.
    /// @param blockNum Block number of the blockhash being validated.
    /// @param blockHash Blockhash being validated.
    function setValidBlockhash(bytes32 blockHash, uint256 blockNum) internal {
        blockhashToBlockNum[blockHash] = blockNum;

        emit BlockhashValidated(blockNum, blockHash);
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
            // If within range anchor blockhash using opcode.
            if (block.number <= blockNum + 256) {
                // Verify the blockhash opcode matches the blockhash from the proof.
                bytes32 blockHashFromOpcode = blockhash(blockNum);
                if (blockHashFromOpcode != blockHash) {
                    revert InvalidProof();
                }

                setValidBlockhash(blockHash, blockNum);
            } else {
                revert BlockhashUnvalidated(blockHash);
            }
        }

        // After fulfilling pre-reqs, we can verify the proof.
        if (!verifyProof(a, b, c, publicInputs)) {
            revert InvalidProof();
        }

        setValidBlockhash(parentHash, blockNum-1);
        return true;
    }
}
