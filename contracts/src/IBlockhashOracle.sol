// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title Blockhash Oracle Interface
/// @author AmanGotchu <aman@paradigm.xyz>
/// @author Sina Sabet <sina@paradigm.xyz>
/// @notice Interface for contracts providing historical blockhashes for randomness providers.
interface IBlockhashOracle {
    /// @notice Emits the validated block number and block hash.
    event BlockhashValidated(uint256 indexed blockNum, bytes32 indexed blockHash);

    /// @notice Returns the nonzero, accurate block number 
    /// if the block hash is validated!.
    function blockHashToNumber(bytes32 hash) external view returns (uint256);
}
