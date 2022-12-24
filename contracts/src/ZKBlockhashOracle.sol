// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IBlockhashOracle.sol";
import "./SingleBlockHeaderVerifier.sol";

error InvalidProof();
error InvalidBlockHash(bytes32 blockHash);
error LinksUnavailable(bytes32 blockHash, uint256 blockNum);

contract ZKPBlockhashOracle is IBlockhashOracle, SingleBlockHeaderVerifier {
    mapping(uint256 => bytes32) public numToHash;

    /// @notice Maps validated blockhashes to their block number.
    mapping(bytes32 => uint256) public blockhashToBlockNum;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PokeRangeError();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    // 
    constructor() {
        poke();
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

    /// @notice Returns the nonzero, accurate block number 
    /// if the block hash is validated!.
    function blockHashToNumber(bytes32 hash) external view returns (uint256) {
        return blockhashToBlockNum[hash];
    }

    /// @notice Validates blockhash and blocknum in storage and emits a validated event.
    /// @param blockNum Block number of the blockhash being validated.
    /// @param blockHash Blockhash being validated.
    function setValidBlockhash(bytes32 blockHash, uint256 blockNum) internal {
        blockhashToBlockNum[blockHash] = blockNum;

        emit BlockhashValidated(blockHash);
    }

    function prove(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[198] memory publicInputs
    ) public {
        if (!verifyProof(a, b, c, publicInputs)) {
            revert InvalidProof();
        }

        // Parse relevant information from the proof's public inputs.
        uint256 i = 0;
        // First 32 bytes is the anchored block hash.
        bytes32 blockHash;
        for (; i < 64; i++) {
            blockHash <<= 4;
            blockHash |= bytes32(publicInputs[i]);
        }
        // Next 32 bytes is the parentHash.
        bytes32 parentHash;
        for (; i < 128; i++) {
            parentHash <<= 4;
            parentHash |= bytes32(publicInputs[i]);
        }
        // Next 6 bytes is the anchored block's number.
        bytes32 blockNumAccumulator;
        for (; i < 134; i++) {
            blockNumAccumulator <<= 4;
            blockNumAccumulator |= bytes32(publicInputs[i]);
        }
        uint256 blockNum = uint256(blockNumAccumulator);

        if (numToHash[blockNum] != blockHash) {
            // If within range poke with blockhash opcode.
            if (block.number <= blockNum + 256) {
                pokeBlocknum(blockNum);
            } else {
                revert InvalidBlockHash(blockHash);
            }
        }

        setValidBlockhash(parentHash, blockNum-1);
    }
}
