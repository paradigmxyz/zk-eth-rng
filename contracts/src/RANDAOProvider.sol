// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Owned} from "solmate/auth/Owned.sol";
import {LibString} from "solmate/utils/LibString.sol";

import {IBlockhashOracle} from "./IBlockhashOracle.sol";
import {IRandomnessProvider} from "./IRandomnessProvider.sol";
import {RLPReader} from "./utils/RLPReader.sol";

/**
 *
 * @title RANDAO Provider
 * @author AmanGotchu <aman@paradigm.xyz>
 * @author sinasab <sina@paradigm.xyz>
 * @notice Provides historical RANDAO values.
 * *****************************************************************************
 *  @dev PURPOSE
 *     This contract aims to provide a RANDAO oracle for the application layer by providing any historical
 *     RANDAO value from any block proven with RLP encoded block headers and block hash oracles.
 *
 *     At time of writing (Paris fork), RANDAO is a pseudorandom value that is generated in the consensus layer by incrementally
 *     mixing contributions from block proposers every block. RANDAO values are currently used in ETH2 consensus layer
 *     to determine future validator committees every epoch. You can only access the RANDAO of
 *     the previous block using the difficulty opcode which isn't fully secure since a block proposer
 *     can censor the transaction for a block if the exposed RANDAO value doesn't favor them.
 *
 *     DISCLAIMER:
 *     A pseudorandom RANDAO is BIASABLE which can have terrible implications if used in applications
 *     that incentivize block proposers to bias randomness.
 *     Please read the 'Security Considerations' section for more info.
 *
 *   @dev USAGE
 *     Charlie is a contract that needs randomness.
 *     Phil is a prover that posts verifiable random values (RANDAO) to RANDAOProvider.
 *
 *     Request
 *         At block number 10, Charlie requests randomness from RANDAOProvider and the following occurs.
 *         1.  RANDAOProvider returns a future block number to Charlie which represents the block Charlie will be using randomness from.
 *             RANDAOProvider takes ownership of determining which block in the future to get randomness from in order to abstract away RANDAO
 *             security considerations AND batch user requests effectively so a single proof from Phil the prover can serve
 *             multiple randomness requests.
 *             However, if the user chooses to, they can specify their own future block number they want randomness from.
 *             We encourage users to understand the security assumptions of RANDAO when considering both approaches.
 *         2.  A RandomnessRequest event is emitted, broadcasting that someone needs randomness from block 40.
 *             This allows Phil the prover to know which blocks to post randomness proofs for.
 *
 *     Prove
 *         Phil sees the RandomnessRequest event for block 40 and waits for that block to be finalized.
 *         After block 40 is finalized, Phil constructs a proof offchain attesting to the RANDAO value
 *         at block 40 and posts it to RANDAOProvider.
 *         The contract verifies the proof and hardens the RANDAO value at block 40 in storage.
 *         RANDAOProvider also emits a RandomnessFulfilled event broadcasting that randomness for block 40 is fulfilled,
 *         so anyone waiting for that value can now fetch it from RANDAOProvider.
 *
 *     Utilize
 *         Charlie has been listening for RandomnessFulfilled events for block 40 and finally sees that it's been fulfilled.
 *         Charlie then calls his contract function that utilizes that randomness and continues his application's execution flow.
 *             Chainlink currently supports user function callbacks, which we hope to replace with open source
 *             software that users can host and run on their own!
 *
 *   @dev SECURITY CONSIDERATIONS
 *
 *     At time of writing, ETH2 RANDAO is biasable and not fully secure! A block proposer when at their designated slot knows the
 *     current RANDAO state and knows what the next RANDAO value will be when mixed with their randomness contribution (RANDAO reveal).
 *     While the block proposer can't fully influence the next RANDAO value since their contribution is deterministic
 *     (signature over current epoch number), a proposer can decide to skip their slot if unfavorable and essentially "reroll" the randomness
 *     value for a block by allowing the next proposer to create a new RANDAO value which might favor them.
 *
 *     Example:
 *     Block proposer Poppy bet on Heads in a lottery contract that's using the randomness from block 10. Poppy happens to be the
 *     block proposer for block 10 and knows whether the RANDAO for the block they're proposing results in heads or tails
 *     before anyone else. If the resulting contract determines the coin flips Tails (the unfavorable outcome)
 *     and there's sufficient incentive for Poppy to forego the block reward, then Poppy can skip proposing that
 *     block and grant themselves another chance by passing the RANDAO generation to the next block proposer.
 *     The next block proposer might generate randomness that flips Heads or Tails from Poppy's view, but nonetheless
 *     Poppy was granted an extra unfair coin flip.
 *
 *     There's a further risk of bias when a block proposer has contiguous proposal slots and can choose which combination of
 *     contributions to mix into the current RANDAO value leading up to a block's randomness. This is referred to as "bits of influence".
 *
 *     We mitigate bias by defaulting applications to use randomness at least 2 epochs in the future where block proposers aren't
 *     determined yet. Thus, proposers can't participate in an application with a guarantee
 *     they're proposing blocks in the epoch that randomness is being fetched from. This however can happen by
 *     chance which is still unfavorable.
 *
 *     For a more concrete security analysis on ETH2 RANDAO read:
 *     - https://eth2book.info/bellatrix/part2/building_blocks/randomness/
 *
 *   @dev FUTURE UNBIASABLE RANDOMNESS
 *
 *     While ETH2 RANDAO is currently biasable, there are plans to introduce an unbiasable form of randomness
 *     using verifiable delay functions (VDF). A verifiable delay function is a function that requires a specified
 *     number of sequential steps to evaluate, is efficiently verifiable, and produces a unique output for every input.
 *     More simply, a VDF is guaranteed to be slow during computation and fast during verification of the output.
 *
 *     This is powerful since a block proposer would need to commit to their randomness (RANDAO reveal) without
 *     knowing the output of the VDF, removing block proposer bias.
 *
 *     Read about VDFs here:
 *     - https://eprint.iacr.org/2018/601.pdf
 *
 *     Combining future unbiasable randomness using VDFs with a censorship resistant RANDAO Provider
 *     creates an unbiasable, censorship resistant, ETH native randomness beacon for the
 *     application layer!
 *
 *   @dev References
 *
 *     - https://eprint.iacr.org/2018/601.pdf
 *     - https://eth2book.info/bellatrix/part2/building_blocks/randomness/
 *     - https://blockdoc.substack.com/p/RANDAO-under-the-hood
 *     - https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4399.md
 *     - https://ethereum-magicians.org/t/eip-4399-supplant-difficulty-opcode-with-random/7368/56
 *
 */
contract RANDAOProvider is Owned, IRandomnessProvider {
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
    mapping(uint256 => uint256) public blockNumToRANDAO;

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

        poke();
    }

    /// @notice Change the block hash oracle to a different contract.
    /// @param newOracle The new contract that validates block hashes.
    function upgradeBlockhashOracle(IBlockhashOracle newOracle) external onlyOwner {
        blockhashOracle = newOracle; // Upgrade the blockhash oracle.

        emit BlockhashOracleUpgraded(msg.sender, address(newOracle));
    }

    /// @notice Attests to the current block's RandDAO value using
    /// the difficulty opcode.
    function poke() public returns (uint256) {
        uint256 RANDAO = block.difficulty;
        uint256 blockNum = block.number;

        blockNumToRANDAO[blockNum] = RANDAO;

        emit RandomnessFulfilled(blockNum, RANDAO);

        return RANDAO;
    }

    /// @notice Takes an RLP encoded block header, verifies its validity, and
    /// cements the RANDAO value for that block in storage.
    /// @param rlp RLP encoded block header.
    function submitRANDAO(bytes memory rlp) external returns (uint256) {
        // Decode RLP encoded block header.
        RLPReader.RLPItem[] memory ls = rlp.toRlpItem().toList();

        // Extract out block number from decoded RLP header.
        uint256 blockNum = ls[8].toUint();

        // Return RANDAO early if already submitted.
        uint256 RANDAO = blockNumToRANDAO[blockNum];
        if (RANDAO != 0) {
            return RANDAO;
        }

        // Validate blockhash using block hash oracle.
        bytes32 blockHash = keccak256(rlp);
        if (blockhashOracle.blockhashToBlockNum(blockHash) != blockNum) {
            revert BlockhashUnverified(blockHash);
        }

        // Extract out mixhash (RANDAO) from block header.
        RANDAO = ls[13].toUint();

        // Cements RANDAO value to this block number.
        blockNumToRANDAO[blockNum] = RANDAO;

        emit RandomnessFulfilled(blockNum, RANDAO);

        return RANDAO;
    }

    /// @notice Function to be called when a user requests randomness.
    /// A user requests randomness which commits them to a future block's RANDAO value.
    /// That future block's number is returned to the user which
    /// can be used to read the randomness value when it's posted by a prover.
    function requestRandomness() external returns (uint256) {
        // Batch randomness request to a future block based
        // on ROUNDING_CONSTANT and MIN_LOOKAHEAD_BUFFER.
        uint256 targetBlock = block.number + MIN_LOOKAHEAD_BUFFER;
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
        // Ensure user is requesting a future block!
        if (targetBlockNum <= block.number) {
            revert RequestedRandomnessFromPast(targetBlockNum);
        }

        emit RandomnessRequested(msg.sender, targetBlockNum);
    }

    /// @notice Fetch the random value tied to a specific block with option
    /// to generate more random values using the initial RANDAO value as a seed.
    /// The random value being fetch is the RANDAO, which
    /// is a form of randomness generated and used in the consensus layer.
    /// A new RANDAO value is generated per block and is exposed in the block header, which
    /// we use to attest to RANDAO values at any block.
    /// This contract stores all RANDAO values that are verified from provers calling `submitRANDAO`.
    /// RANDAO in consensus is a "good enough" form of randomness and extremely difficult to bias
    /// while theoretically possible. Read all about RANDAO + security risks
    /// here: https://eth2book.info/bellatrix/part2/building_blocks/randomness/
    /// @param blockNum Block number to fetch randomness from.
    /// @param numberRandomValues Number of random values returned.
    function fetchRandomness(uint256 blockNum, uint256 numberRandomValues) public view returns (uint256[] memory) {
        uint256 RANDAO = blockNumToRANDAO[blockNum];

        // Ensure RANDAO value is proven AND user isn't trying to fetch
        // randomness from a current or future block.
        if (RANDAO == 0) {
            revert RandomnessNotAvailable(blockNum);
        }

        if (numberRandomValues == 0) {
            revert RequestedZeroRandomValues();
        }

        // Uses RANDAO as the seed to generate more values.
        return generateMoreRandomValues(RANDAO, numberRandomValues);
    }

    /// @notice Generates more values using keccak given an initial seed.
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
