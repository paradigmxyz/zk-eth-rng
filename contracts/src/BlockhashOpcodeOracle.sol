// SPDX-License-Identifier: MIT
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

    /// @notice Validates the block hash of the block before this tx is called.
    /// @return The block number and blockhash being validated.
    function poke() public returns (uint256, bytes32) {
        uint256 prevBlockNum = block.number - 1;
        bytes32 blockhashVal = blockhash(prevBlockNum);
        setValidBlockhash(blockhashVal, prevBlockNum);

        return (prevBlockNum, blockhashVal);
    }

    /// @notice Validates the block hash of a specified block number using
    /// the blockhash opcode. The blockhash opcode is currently limited to
    /// 256 blocks in the past. There have been discussions of EIPs that
    /// allow for arbitrary blockhash lookback which makes this blockhash
    /// oracle approach far better.
    /// @param blockNum Block number to validate.
    function pokeBlocknum(uint256 blockNum) public returns (bytes32) {
        bytes32 blockhashVal = blockhash(blockNum);
        if (blockhashVal == bytes32(0)) {
            revert PokeRangeError();
        }

        setValidBlockhash(blockhashVal, blockNum);
        return blockhashVal;
    }

    /// @notice Validates blockhash and blocknum in storage and emits a validated event.
    /// @param blockNum Block number of the blockhash being validated.
    /// @param blockHash Blockhash being validated.
    function setValidBlockhash(bytes32 blockHash, uint256 blockNum) internal {
        blockhashToBlockNum[blockHash] = blockNum;

        emit BlockhashValidated(blockNum, blockHash);
    }
}
