// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./IBlockhashOracle.sol";

/// @title Blockhash Opcode Oracle
/// @author AmanGotchu <aman@paradigm.xyz>
/// @author Sina Sabet <sina@paradigm.xyz>
/// @notice Blockhash opcode based blockhash oracle.
contract BlockhashOpcodeOracle is IBlockhashOracle {
    /// @notice Maps validated blockhashes to their block number.
    mapping(bytes32 => uint256) public blockhashToBlockNum;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PokeRangeError();

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
}
