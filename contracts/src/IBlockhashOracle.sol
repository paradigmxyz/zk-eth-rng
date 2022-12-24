// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @notice Interface that all blockhash oracles must implement
/// so RandomnessProvider can plug in.
interface IBlockhashOracle {
    event BlockhashValidated(bytes32);

    /// @notice Returns the nonzero, accurate block number 
    /// if the block hash is validated!.
    function blockHashToNumber(bytes32 hash) external view returns (uint256);
}
