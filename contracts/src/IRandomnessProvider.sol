// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IBlockhashOracle.sol";

/** ****************************************************************************
 * @notice Paradigm's Randomness Beacon (PRB)
 * *****************************************************************************
 *  @dev PURPOSE
    The purpose of this contract is to provide an ETH native, verifiable source of randomness
    for the application layer.

    At time of writing (Paris fork), RanDAO is a pseudorandom value that is generated in the consensus layer by incrementally 
    mixing contributions from block proposers every block. RanDAO values are currently used in ETH2 consensus layer
    to determine future validator committees every epoch. At the time of writing, you can only access the ranDAO of 
    the previous block using the difficulty opcode which isn't fully secure since a block proposer can censor the transaction
    for a block if the exposed ranDAO value doesn't favor them.

    This contract aims to provide a ranDAO oracle for the application layer by providing any historical 
    ranDAO value from any block proven with RLP encoded block headers and block hash oracles.

    DISCLAIMER: At time of writing, ETH2 RanDAO is pseudorandom and BIASABLE which can have terrible implications
    if used in applications that incentivize block proposers to bias randomness. When RanDAO is unbiasable in the future using 
    VDFs or other constructions we hope this contract will provide unbiasable AND censorship resistant randomness to the application
    layer. Please read the 'Security Considerations' section for more info.

*   @dev USAGE
    Charlie is a contract that needs randomness.
    Phil is a prover that posts verifiable random values (ranDAO) to the Paradigm Randomness Beacon.

    Request
    At block number 10, Charlie requests randomness by calling the PRB contract. 
    When Charlie requests randomness from PRB 2 things happen.
        1.  PRB returns a future block number to Charlie which represents the block Charlie will be using randomness from.
            PRB takes ownership of determining which block in the future to get randomness from in order to abstract away ranDAO
            security considerations AND batch user requests effectively so a single proof from Phil the prover can serve 
            multiple randomness requests.
            However, if the user chooses to, they can specify their own future block number they want randomness from.
                We encourage users to understand the security assumptions of ranDAO if they opt for this option!
        2.  A RandomnessRequest event is emitted, broadcasting that someone needs randomness from block 40. 
            This allows Phil the prover to know which blocks to post randomness proofs for!

    Prove
    Phil sees the RandomnessRequest event for block 40 and waits for that block to be finalized.
    After block 40 is finalized, Phil constructs a proof offchain attesting to the ranDAO value at block 40 and posts it to PRB.
    PRB verifies the proof and hardens the ranDAO value at block 40 in contract.
    PRB also emits a RandomnessFulfilled event broadcasting that randomness for block 40 is fulfilled, so anyone waiting for
    that value can now fetch it from PRB.
    
    Utilize
    Charlie has been listening for RandomnessFulfilled events for block 40 and finally sees that it's been fulfilled.
    Charlie then calls his contract function that utilizes that randomness and continues his application's execution!
        Chainlink currently supports user function callbacks, which we hope to replace with open source
        software that users can host and run on their own!

*   @dev SECURITY CONSIDERATIONS

    At time of writing, ETH2 ranDAO is biasable and not fully secure! A block proposer when at their designated slot knows the
    current ranDAO state and knows what the next ranDAO value will be when mixed with their randomness contribution (ranDAO reveal).
    While the block proposer can't fully influence the next ranDAO value since their contribution is deterministic 
    (signature over current epoch number), a proposer can decide to skip their slot if unfavorable and essentially "reroll" the randomness
    value for a block by allowing the next proposer to create a new ranDAO value which might favor them.

    Example:
    Block proposer Poppy bet on Heads in a lottery contract that's using the randomness from block 10. Poppy happens to be the
    block proposer for block 10 and knows whether the ranDAO for the block they're proposing results in heads or tails
    before anyone else. If the resulting contract determines the coin flips Tails (the unfavorable outcome) 
    and there's sufficient incentive for Poppy to forego the block reward, then Poppy can skip proposing that 
    block and grant themselves another chance by passing the ranDAO generation to the next block proposer. 
    The next block proposer might generate randomness that flips Heads or Tails from Poppy's view, but nonetheless 
    Poppy was granted an extra unfair coin flip. 

    There's a further risk of bias when a block proposer has contiguous proposal slots and can choose which combination of
    contributions to mix into the current ranDAO value leading up to a block's randomness. This is referred to as "bits of influence".

    We mitigate bias by defaulting applications to use randomness at least 2 epochs in the future where block proposers aren't 
    determined yet. Thus, proposers can't participate in an application with a guarantee 
    they're proposing blocks in the epoch that randomness is being fetched from. This however can happen by
    chance which is still unfavorable.

    For more concrete security analysis on ETH2 randao read:
    - https://eth2book.info/bellatrix/part2/building_blocks/randomness/

*   @dev FUTURE UNBIASABLE RANDOMNESS

    While ETH2 Randao is currently biasable, there are plans to introduce an unbiasable form of randomness
    using verifiable delay functions (VDF). A verifiable delay function is a function that requires a specified 
    number of sequential steps to evaluate, is efficiently verifiable, and produces a unique output for every input.
    More simply, a VDF is guaranteed to be slow during computation and fast during verification of the output. 

    This is powerful since a block proposer would need to commit to their randomness (randao reveal) without
    knowing the output of the VDF, removing block proposer bias.

    Read about VDFs here:
    - https://eprint.iacr.org/2018/601.pdf

    Combining future unbiasable randomness using VDFs with this contract's censorship resistance achieved by
    storing historical randao values for anyone to use, we create the ultimate unbiasable, censorship resistant,
    ETH native randomness beacon for the application layer!!!

*   @dev References

    - https://eprint.iacr.org/2018/601.pdf
    - https://eth2book.info/bellatrix/part2/building_blocks/randomness/
    - https://blockdoc.substack.com/p/randao-under-the-hood
    - https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4399.md
    - https://ethereum-magicians.org/t/eip-4399-supplant-difficulty-opcode-with-random/7368/56
***/

interface IRandomnessProvider {
    event RandomnessRequested(
        address indexed requester,
        uint256 indexed randomnessBlock
    );

    event RandomnessAvailable(
        uint256 indexed fulfilledBlock,
        uint256 randomSeed
    );

    function requestRandomness() external returns (uint256);

    function requestRandomnessFromBlock(uint256 block) external;

    function fetchRandomness(uint256 blockNum, uint256 numberRandomValues)
        external
        view
        returns (uint256[] memory);
}
