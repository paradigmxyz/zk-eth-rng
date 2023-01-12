// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {LibString} from "solmate/utils/LibString.sol";

import {IFactRegistry} from "./vdf/IFactRegistry.sol";
import {IRandomnessProvider} from "./IRandomnessProvider.sol";

/// @title Veedo VDF Provider Reference Implementation
/// @notice This is an EXAMPLE contract of how to implement a VDF based
///         randomness provider using Starkware's Veedo VDF. It is NOT suited for
///         production use since Veedo isn't public.
///
///         Credit:
///         This contract was heavily influenced by the Starkware contracts and sources
///         referenced below.
///
///         References:
///         - https://github.com/starkware-libs/veedo/blob/master/contracts/IStarkVerifier.sol
///         - https://medium.com/starkware/presenting-veedo-e4bbff77c7ae
///         - https://github.com/starkware-libs/veedo/blob/master/LICENSE
contract VDFProvider is IRandomnessProvider {
    using LibString for uint256;

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The following are relevant constants for the Veedo VDF.
    uint256 internal immutable nIterations;
    uint256 internal constant PUBLIC_INPUT_SIZE = 5;
    uint256 internal constant OFFSET_LOG_TRACE_LENGTH = 0;
    uint256 internal constant OFFSET_VDF_OUTPUT_X = 1;
    uint256 internal constant OFFSET_VDF_OUTPUT_Y = 2;
    uint256 internal constant OFFSET_VDF_INPUT_X = 3;
    uint256 internal constant OFFSET_VDF_INPUT_Y = 4;
    uint256 internal constant PRIME = 0x30000003000000010000000000000001;
    uint256 internal constant MAX_LOG_TRACE_LENGTH = 40;

    /// @notice We use this rounding constant to batch users'
    /// randomness requests to the closest multiple of ROUNDING_CONSTANT
    /// in the future. Routing users to the same block allows
    /// a single proof to service multiple users.
    /// This is an arbitrary rounding constant and
    /// should be influenced by the VDF time.
    uint256 public constant ROUNDING_CONSTANT = 10;

    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Fact Registry contract.
    IFactRegistry public verifierContract;

    /// @notice The address of the Blockhash Oracle contract.
    IRandomnessProvider public randaoProvider;

    /*//////////////////////////////////////////////////////////////
                            RANDOMNESS STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The randomness value, indexed by block number.
    mapping(uint256 => uint256) public blockNumToVDFRandomness;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error RandomnessNotAvailable(uint256);
    error RequestedRandomnessFromPast(uint256);
    error RequestedZeroRandomValues();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets RANDAO provider contract address.
    /// @param _randaoProvider Address of RANDAO provider contract.
    constructor(IFactRegistry _factRegistry, IRandomnessProvider _randaoProvider, uint256 _nIterations) {
        verifierContract = _factRegistry;
        randaoProvider = _randaoProvider; // Must be a RANDAO randomnes provider.
        nIterations = _nIterations;
    }

    function submitVDFRandomness(
        uint256 blockNumber,
        uint256 randao,
        uint256[PUBLIC_INPUT_SIZE] calldata proofPublicInput
    ) external {
        // Verify this is a valid ranDAO for this block number
        require(isValidRANDAO(blockNumber, randao), "Invalid randao for this block.");

        require(
            proofPublicInput[OFFSET_LOG_TRACE_LENGTH] < MAX_LOG_TRACE_LENGTH,
            "VDF reported length exceeds the integer overflow protection limit."
        );
        require(
            nIterations == 10 * 2 ** proofPublicInput[OFFSET_LOG_TRACE_LENGTH] - 1,
            "Public input and n_iterations are not compatible."
        );
        require(
            proofPublicInput[OFFSET_VDF_OUTPUT_X] < PRIME && proofPublicInput[OFFSET_VDF_OUTPUT_Y] < PRIME,
            "Invalid vdf output."
        );

        // To calculate the input of the VDF we first hash the RANDAO with the string "veedo",
        // then we split the last 250 bits to two 125 bit field elements.
        uint256 vdfInput = uint256(keccak256(abi.encodePacked(randao, "veedo")));
        require(
            vdfInput & ((1 << 125) - 1) == proofPublicInput[OFFSET_VDF_INPUT_X],
            "randao does not match the given proofPublicInput."
        );
        require(
            ((vdfInput >> 125) & ((1 << 125) - 1)) == proofPublicInput[OFFSET_VDF_INPUT_Y],
            "randao does not match the given proofPublicInput."
        );
        require(verifierContract.isValid(keccak256(abi.encodePacked(proofPublicInput))), "No valid proof provided.");
        // The randomness is the hash of the VDF output and the string "veedo"
        uint256 randomness = uint256(
            keccak256(
                abi.encodePacked(proofPublicInput[OFFSET_VDF_OUTPUT_X], proofPublicInput[OFFSET_VDF_OUTPUT_Y], "veedo")
            )
        );

        blockNumToVDFRandomness[blockNumber] = randomness;
        emit RandomnessFulfilled(blockNumber, randomness);
    }

    /// @notice Function to be called when a user requests randomness.
    /// A user requests randomness which commits them to a future block's VDF
    /// generated value.
    /// That future block's number is returned to the user which
    /// can be used to read the randomness value when it's posted by a prover.
    function requestRandomness() external returns (uint256) {
        // Batch randomness request to a future block based
        // on ROUNDING_CONSTANT.
        uint256 targetBlock = block.number;
        if (targetBlock % ROUNDING_CONSTANT != 0) {
            targetBlock += ROUNDING_CONSTANT - (targetBlock % ROUNDING_CONSTANT);
        }

        emit RandomnessRequested(msg.sender, targetBlock);
        return targetBlock;
    }

    /// @notice Function to be called when a user requests randomness.
    /// In this function, a user can specify the exact future block they want
    /// their randomness to come from. This emits an event that provers
    /// can listen to in order to fufill randomness.
    /// @param targetBlockNum The future block number the requestor
    /// is requesting randomness for.
    function requestRandomnessFromBlock(uint256 targetBlockNum) external {
        // Ensure user is requesting a future block.
        if (targetBlockNum <= block.number) {
            revert RequestedRandomnessFromPast(targetBlockNum);
        }

        emit RandomnessRequested(msg.sender, targetBlockNum);
    }

    /// @notice Fetch the VDF generated random value tied to a specific block
    /// with option to generate more random values using the initial RANDAO value
    /// as a seed.
    /// @param blockNum Block number to fetch randomness from.
    /// @param numberRandomValues Number of random values returned.
    function fetchRandomness(uint256 blockNum, uint256 numberRandomValues) public view returns (uint256[] memory) {
        uint256 randomness = blockNumToVDFRandomness[blockNum];

        // Ensure RANDAO value is proven AND user isn't trying to fetch
        // randomness from a current or future block.
        if (randomness == 0) {
            revert RandomnessNotAvailable(blockNum);
        }

        if (numberRandomValues == 0) {
            revert RequestedZeroRandomValues();
        }

        // Uses VDF randomness as the seed to generate more values.
        return generateMoreRandomValues(randomness, numberRandomValues);
    }

    /// @notice Checks if the given randao value is valid for the given block number.
    function isValidRANDAO(uint256 blockNumber, uint256 randao) internal view returns (bool) {
        // Verify this is a valid ranDAO for this block number
        return randaoProvider.fetchRandomness(blockNumber, 1)[0] == randao;
    }

    /// @notice Generates more random values using keccak given an initial seed.
    /// View disclaimer about how the random seed (RANDAO) is generated in function above!
    /// @param seed Initial value to base the rest of the random values on.
    /// @param numRandomValues Number of values to return.
    function generateMoreRandomValues(uint256 seed, uint256 numRandomValues) internal pure returns (uint256[] memory) {
        uint256[] memory res = new uint256[](numRandomValues);
        uint256 iter = seed;

        for (uint256 i = 0; i < numRandomValues; i++) {
            res[i] = iter;
            iter = uint256(keccak256(abi.encodePacked(iter)));
        }

        return res;
    }
}
