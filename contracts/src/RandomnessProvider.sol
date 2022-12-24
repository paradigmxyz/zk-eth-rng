// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {LibString} from "solmate/utils/LibString.sol";

import {RLPReader} from "./RLPReader.sol";
import {IBlockhashOracle} from "./IBlockhashOracle.sol";
import {IRandomnessProvider} from "./IRandomnessProvider.sol";

import {TurboVerifier} from "./VDFVerifier.sol";

/// @title Randao Randomness Beacon
/// @author AmanGotchu <aman@paradigm.xyz>
/// @author sinasab <sina@paradigm.xyz>
/// @notice An experimental onchain randomness project by Paradigm.
contract RandomnessProvider is Owned, IRandomnessProvider, TurboVerifier {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;
    using RLPReader for bytes;

    using LibString for uint256;

    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Blockhash Oracle contract.
    IBlockhashOracle public blockhashOracle;

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice We use this rounding constant to batch users'
    /// randomness requests to the closest multiple of ROUNDING_CONSTANT
    /// in the future. Routing users to the same block allows
    /// a single proof to service multiple users!
    uint256 public constant ROUNDING_CONSTANT = 25;

    /// @notice We only attach randomness requests
    /// after MIN_LOOKAHEAD_BUFFER blocks in the future.
    uint256 public constant MIN_LOOKAHEAD_BUFFER = 5;

    /*//////////////////////////////////////////////////////////////
                            RANDOMNESS STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The randomness value, indexed by block number.
    mapping(uint256 => uint256) public blockNumToRanDAO;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event BlockhashOracleUpgraded(address, address);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BlockhashUnverified(bytes32);
    error RandomnessNotAvailable(uint256);
    error RequestedRandomnessFromPast(uint256);
    error RequestedZeroRandomValues();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets Blockhash oracle contract address, owner, and randomness config.
    /// @param _blockhashOracle Address of blockhash oracle contract.
    constructor(IBlockhashOracle _blockhashOracle) Owned(msg.sender) {
        blockhashOracle = _blockhashOracle;
    }

    /// @notice Change the block hash oracle to a different contract.
    /// @param newOracle The new contract that validates block hashes.
    function upgradeBlockhashOracle(IBlockhashOracle newOracle)
        external
        onlyOwner
    {
        blockhashOracle = newOracle; // Upgrade the blockhash oracle.

        emit BlockhashOracleUpgraded(msg.sender, address(newOracle));
    }

    /// @notice Attests to the previous block's RandDAO value using difficulty
    /// the difficulty opcode.
    /// TODO(aman): Verify we're adding the randao value to the right block!
    function poke() external returns (uint256) {
        uint256 ranDAO = block.difficulty;

        blockNumToRanDAO[block.number - 1] = ranDAO;

        emit RandomnessAvailable(block.number - 1, ranDAO);

        return ranDAO;
    }

    /// @notice Takes an RLP encoded block header, verifies its validity, and
    /// cements the randao value for that block in storage.
    /// @param rlp RLP encoded block header.
    function submitRanDAO(bytes memory rlp) external returns (uint256) {
        // Decode RLP encoded block header.
        RLPReader.RLPItem[] memory ls = rlp.toRlpItem().toList();

        // Extract out block number from decoded RLP header.
        uint256 blockNum = ls[8].toUint();

        // Return randao early if already submitted.
        uint256 ranDAO = blockNumToRanDAO[blockNum];
        if (ranDAO != 0) {
            return ranDAO;
        }

        // Validate blockhash using block hash oracle.
        bytes32 blockHash = keccak256(rlp);
        if (blockhashOracle.blockHashToNumber(blockHash) == 0) {
            revert BlockhashUnverified(blockHash);
        }

        // Extract out mixhash (randao) from block header.
        ranDAO = ls[13].toUint();

        // Cements randao value to this block number.
        blockNumToRanDAO[blockNum] = ranDAO;

        emit RandomnessAvailable(blockNum, ranDAO);

        return ranDAO;
    }

    /// @notice Function to be called when a user requests randomness.
    /// A user requests randomness which commits them to a future block's randao value.
    /// That future block's number is returned to the user which
    /// can be used to read the randomness value when it's posted by a prover.
    function requestRandomness() external returns (uint256) {
        // Batch randomness request to a future block based
        // on ROUNDING_CONSTANT and MIN_LOOKAHEAD_BUFFER.
        uint256 minBlockNum = block.number + MIN_LOOKAHEAD_BUFFER;
        uint256 futureDelta = ROUNDING_CONSTANT -
            (minBlockNum % ROUNDING_CONSTANT);
        if (futureDelta == ROUNDING_CONSTANT) {
            futureDelta = 0;
        }
        uint256 targetBlock = minBlockNum + futureDelta;

        emit RandomnessRequested(msg.sender, targetBlock);

        return minBlockNum + futureDelta;
    }

    /// @notice Function to be called when a user requests randomness.
    /// In this function, a user can specify the exact future block they want
    /// their randomness to come from. This emits an event that provers
    /// can listen to in order to fufill randomness.
    /// @param targetBlockNum The future block number the requestor
    /// is requesting randomness for.
    function requestRandomnessFromBlock(uint256 targetBlockNum) external {
        // Ensure user is requesting a future block!
        if (targetBlockNum <= block.number) {
            revert RequestedRandomnessFromPast(targetBlockNum);
        }

        emit RandomnessRequested(msg.sender, targetBlockNum);
    }

    /// @notice Fetch the random value tied to a specific block with option
    /// to generate more random values using the initial randao value as a seed.
    /// The random value being fetch is the RanDAO, which
    /// is a form of randomness generated and used in the consensus layer.
    /// A new ranDAO value is generated per block and is exposed in the block header, which
    /// we use to attest to randao values at any block.
    /// This contract stores all randao values that are verified from provers calling `submitRanDAO`.
    /// Randao in consensus is a "good enough" form of randomness and extremely difficult to bias
    /// while theoretically possible. Read all about RanDAO + security risks
    /// here: https://eth2book.info/bellatrix/part2/building_blocks/randomness/
    /// @param blockNum Block number to fetch randomness from.
    /// @param numberRandomValues Number of random values returned.
    function fetchRandomness(uint256 blockNum, uint256 numberRandomValues)
        public
        view
        returns (uint256[] memory)
    {
        if (numberRandomValues == 0) {
            revert RequestedZeroRandomValues();
        }

        uint256 ranDAO = blockNumToRanDAO[blockNum];

        // Ensure randao value is proven AND user isn't trying to fetch
        // randomness from a current or future block.
        if (ranDAO == 0) {
            revert RandomnessNotAvailable(blockNum);
        }

        // Uses Randao as the seed to generate more random values.
        return generateMoreRandomValues(ranDAO, numberRandomValues);
    }

    /// @notice Generates more random values using keccak given an initial seed.
    /// View disclaimer about how the random seed (randao) is generated in function above!
    /// @param seed Initial value to base the rest of the random values on.
    /// @param numRandomValues Number of values to return.
    function generateMoreRandomValues(uint256 seed, uint256 numRandomValues)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory res = new uint256[](numRandomValues);
        uint256 iter = seed;

        for (uint256 i = 0; i < numRandomValues; i++) {
            res[i] = iter;
            iter = uint256(keccak256(abi.encodePacked(iter)));
        }

        return res;
    }
}
