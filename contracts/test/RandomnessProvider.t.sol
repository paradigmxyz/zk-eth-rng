// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import {LibString} from "solmate/utils/LibString.sol";

import "../src/RandomnessProvider.sol";
import "../src/BlockhashOpcodeOracle.sol";
import "../src/SingleBlockHeaderVerifier.sol";

contract RanDAOOracleTest is Test {
    using stdJson for string;
    using stdStorage for StdStorage;

    BlockhashOpcodeOracle public blockhashOracle;
    RandomnessProvider public randomProvider;
    SingleBlockHeaderVerifier public zkpVerifier;

    uint256[] public blockNums;

    uint256 constant mockRandao =
        74959964106633704346858077179036090420725799257578598593094705978576627503466;

    // Blockhash oracle upgrade event from randomness provider.
    event BlockhashOracleUpgraded(address, address);

    // Randomness Requested event from randomness provider.
    event RandomnessRequested(
        address indexed requester,
        uint256 indexed requestedBlock
    );

    // Randomness available for use event from randomness provider.
    event RandomnessAvailable(
        uint256 indexed fulfilledBlock,
        uint256 randomSeed
    );

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        blockhashOracle = new BlockhashOpcodeOracle();
        randomProvider = new RandomnessProvider(blockhashOracle);
        zkpVerifier = new SingleBlockHeaderVerifier();

        // Only testing blocknums that we have blockdata json files for.
        blockNums.push(15537394);
        blockNums.push(15537395);
    }

    /*//////////////////////////////////////////////////////////////
                            RANDOMNESS REQUESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that a proof returned from
    /// singleBlockHeader.circom can be validated on chain.
    /// This proof proves the blockheader of Goerli block 8150160.
    function testCanVerifySingleBlockHeaderZKP() public {
        uint256[2] memory a = [
            uint256(bytes32(hex'29b0e5ac6476d71ff50544f78bf93a699b0793928308553249338660fda00703')), 
            uint256(bytes32(hex'2ca0b5b9629b981275265776e6a34e44448a1b4e7aca234c7b6b101fda59a1f5'))
        ];
        uint256[2][2] memory b = [[
            uint256(bytes32(hex'1c993c951040e7ea4f17b30876339f2d9fe7c895c008ef9a3e39e4a9bb3dcb70')),
            uint256(bytes32(hex'0fc5ad56c8aed67e5262a2d64f73a564ae1b15509f7b83fd715e18ca38c08cb3'))
        ], [
            uint256(bytes32(hex'2bf980adcb909672e98b23d4b3cda4a4eb93f1803d9e89ec9ef3c021f7456e5c')),
            uint256(bytes32(hex'1642b91468d0c795cad26f79279800752e8649808c7439d60aa43c6853b5a7fa'))
        ]];
        uint256[2] memory c = [
            uint256(bytes32(hex'2a9340525c337ec7c573aadfe4a9af2cb4139373b8f669c8aa64902458f85ab0')),
            uint256(bytes32(hex'2aec28199f7c0cfddc588e46d44bb75e258e5db05a4416fdbcc0bf2b5654eef6'))
        ];
        uint256[198] memory input = [uint256(12), 9, 6, 9, 14, 15, 13, 12, 2, 8, 9, 10, 10, 14, 3, 8, 7, 6, 8, 10, 8, 10, 15, 5, 1, 14, 15, 12, 3, 5, 8, 7, 4, 10, 13, 8, 5, 6, 8, 6, 1, 6, 15, 0, 7, 5, 10, 0, 5, 8, 6, 4, 1, 3, 11, 14, 6, 15, 11, 14, 4, 10, 5, 5, 5, 2, 0, 11, 4, 2, 8, 15, 13, 8, 9, 4, 14, 5, 12, 13, 12, 8, 11, 4, 3, 7, 10, 10, 6, 12, 13, 3, 11, 3, 9, 12, 6, 11, 15, 1, 0, 11, 13, 10, 6, 8, 0, 0, 12, 15, 5, 11, 4, 0, 4, 12, 15, 13, 12, 2, 3, 12, 4, 5, 4, 3, 5, 4, 7, 12, 5, 12, 9, 0, 2, 4, 9, 8, 1, 15, 3, 7, 0, 6, 5, 0, 9, 4, 0, 6, 15, 6, 10, 1, 12, 4, 3, 5, 0, 3, 4, 1, 14, 15, 2, 14, 8, 2, 9, 2, 7, 10, 9, 5, 2, 13, 7, 11, 8, 4, 2, 4, 10, 8, 15, 5, 15, 1, 5, 8, 5, 4, 5, 6, 0, 1, 10, 14];

        bool verified = zkpVerifier.verifyProof(a, b, c, input);
        assertTrue(verified);
    }

    /// @notice Tests that block returned from randomness request
    /// is >= current block + MIN_LOOKAHEAD_BUFFER and is
    /// a multiple of ROUNDING_CONSTANT.
    function testRandomnessRequest(uint256 currentBlock) public {
        vm.assume(
            currentBlock <
                type(uint256).max -
                    randomProvider.MIN_LOOKAHEAD_BUFFER() -
                    randomProvider.ROUNDING_CONSTANT()
        );
        vm.roll(currentBlock);

        uint256 randomnessBlock = randomProvider.requestRandomness();

        // Assert the retrieved block is greater or equal to
        // the current block + the minimum buffer lookahead.
        assertGe(
            randomnessBlock,
            currentBlock + randomProvider.MIN_LOOKAHEAD_BUFFER()
        );

        // Assert the retrieved blocks is a multiple of the rounding
        // constant.
        assertEq(0, randomnessBlock % randomProvider.ROUNDING_CONSTANT());

        // Assert that retrieved block is isn't too far in the future.
        uint256 maxDistance = randomProvider.ROUNDING_CONSTANT() +
            randomProvider.MIN_LOOKAHEAD_BUFFER();
        assertLt(randomnessBlock - currentBlock, maxDistance);
    }

    /// @notice Tests that event is emitted when randomness is requested.
    function testRandomnessRequestFromBlock() public {
        vm.roll(100);
        vm.expectEmit(true, true, false, false, address(randomProvider));
        emit RandomnessRequested(address(this), 101);

        randomProvider.requestRandomnessFromBlock(101);
    }

    /// @notice Tests that randomness cannot be requested for the current block.
    function testCannotRequestRandomnessForCurrentOrPastBlock(uint256 blockNum)
        public
    {
        vm.roll(200);
        vm.assume(blockNum <= 200);

        vm.expectRevert(
            abi.encodeWithSelector(
                RandomnessProvider.RequestedRandomnessFromPast.selector,
                200
            )
        );

        randomProvider.requestRandomnessFromBlock(200);
    }

    /*//////////////////////////////////////////////////////////////
                        RANDOMNESS SUBMISSION
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that we can extract and attest to
    /// the randao value for blocks that are verified by our blockhash oracle.
    function testCanSubmitRanDAO() public {
        for (uint256 i = 0; i < blockNums.length; ++i) {
            internalRecoverVerifiedRanDAOValue(blockNums[i], true);
        }
    }

    /// @notice Tests that we can't attest to randao values
    /// that aren't verified by our blockhash oracle.
    function testCannotSubmitRanDAO() public {
        for (uint256 i = 0; i < blockNums.length; ++i) {
            internalRecoverVerifiedRanDAOValue(blockNums[i], false);
        }
    }

    /// @notice Tests that a valid RLP encoded header will properly
    /// extract and attest to the randao value when blockhash is
    /// validated and that it won't attest if blockhash hasn't
    /// been validated yet.
    function internalRecoverVerifiedRanDAOValue(
        uint256 blockNum,
        bool validBlockhash
    ) internal {
        (
            bytes32 expectedHash,
            bytes memory rlp,
            bytes32 expectedRanDao
        ) = readBlockDataFile(blockNum);
        // Sanity check, RLP matches expected hash.
        assertEq(keccak256(rlp), expectedHash);

        if (validBlockhash) {
            // Mock validity of blockhash through oracle.
            mockOracle(expectedHash, blockNum);

            // Expect randomness availability event.
            vm.expectEmit(true, false, false, false, address(randomProvider));
            emit RandomnessAvailable(blockNum, 1);

            // Attempt to submit a single RanDAO value.
            uint256 derivedRanDao = randomProvider.submitRanDAO(rlp);

            // Sanity check that it matches expected.
            assertEq(bytes32(derivedRanDao), expectedRanDao);

            // Verify randao value exists and can be fetched in the future.
            vm.roll(blockNum + 1);
            uint256[] memory fetchedRandomValues = randomProvider
                .fetchRandomness(blockNum, 1);
            assertEq(bytes32(fetchedRandomValues[0]), expectedRanDao);
        } else {
            mockOracle(expectedHash, 0);

            vm.expectRevert(
                abi.encodeWithSelector(
                    RandomnessProvider.BlockhashUnverified.selector,
                    keccak256(rlp)
                )
            );

            // Submit a single RanDAO value, expecting function to revert.
            randomProvider.submitRanDAO(rlp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FETCHING RANDOMNESS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that we can fetch an arbitrary amount of random values,
    /// given randao value is proven in contract.
    function testFetchingRandomness(uint8 numRandomValues) public {
        vm.assume(numRandomValues > 0);
        uint256 blockNum = 100;
        mockRandaoAtBlock(blockNum, mockRandao);

        uint256[] memory randomValues = randomProvider.fetchRandomness(
            blockNum,
            numRandomValues
        );

        assertEq(randomValues.length, numRandomValues);
        assertEq(randomValues[0], mockRandao);

        for (uint256 i = 1; i < numRandomValues; i++) {
            assertEq(
                randomValues[i],
                uint256(keccak256(abi.encodePacked(randomValues[i - 1])))
            );
        }
    }

    /// @notice Tests that we can't fetch randomness if randao value
    /// isn't attested to.
    function testCannotFetchRandomnessWithoutValidRandaoSubmission() public {
        uint256 blockNum = 100;
        mockRandaoAtBlock(blockNum, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                RandomnessProvider.RandomnessNotAvailable.selector,
                blockNum
            )
        );

        randomProvider.fetchRandomness(blockNum, 1);
    }

    /// @notice Tests that we can't request 0 random values.
    function testCannotFetchZeroRandomValues() public {
        uint256 blockNum = 100;
        mockRandaoAtBlock(blockNum, mockRandao);

        vm.expectRevert(RandomnessProvider.RequestedZeroRandomValues.selector);

        randomProvider.fetchRandomness(blockNum, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        UPGRADING BLOCKHASH ORACLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that the owner can change the blockhash oracle.
    function testCanUpgradeBlockhashOracle() public {
        address newOracle = 0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b;

        vm.expectEmit(true, true, false, false, address(randomProvider));
        emit BlockhashOracleUpgraded(address(this), newOracle);

        // The test contract is the current owner of the random provider.
        randomProvider.upgradeBlockhashOracle(IBlockhashOracle(newOracle));
    }

    /// @notice Tests that someone that isn't the owner can't change the
    /// blockhash verifir contract.
    function testCannotUpgradeBlockhashOracle() public {
        // Change the current user to someone other than owner of contract.
        vm.prank(address(0));
        vm.expectRevert("UNAUTHORIZED");

        address newOracle = 0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b;
        randomProvider.upgradeBlockhashOracle(IBlockhashOracle(newOracle));
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reads the block data from JSON in the repo to use for testing.
    function readBlockDataFile(uint256 blockNum)
        public
        returns (
            bytes32 expectedHash,
            bytes memory rlp,
            bytes32 mixHash
        )
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/testdata/blockheaderinfo/",
            LibString.toString(blockNum),
            ".json"
        );
        string memory json = vm.readFile(path);

        expectedHash = json.readBytes32(".goldenHash");
        rlp = json.readBytes(".rlp");
        mixHash = json.readBytes32(".cleanedHeaderFields.mixHash");
    }

    /// @notice Read the VDF proof data from JSON in the repo to use for testing.
    function readVDFDataFile(uint256 blockNum)
        public
        returns (
            bytes memory proof,
            bytes32 blockHash,
            bytes32 vdfOutput
        )
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(
            root,
            "/testdata/vdf/",
            LibString.toString(blockNum),
            ".json"
        );
        string memory json = vm.readFile(path);

        proof = json.readBytes(".proof");
        console2.logBytes(proof);

        blockHash = json.readBytes32(".blockHash");
        vdfOutput = json.readBytes32(".vdfOutput");
    }

    /// @notice Mocks the block hash oracle's response for a validity check.
    function mockOracle(bytes32 blockHash, uint256 response) internal {
        stdstore
            .target(address(blockhashOracle))
            .sig("blockHashToNumber(bytes32)")
            .with_key(blockHash)
            .checked_write(response);
    }

    /// @notice Mocks the randao value for a block.
    function mockRandaoAtBlock(uint256 blockNumber, uint256 randao) internal {
        stdstore
            .target(address(randomProvider))
            .sig("blockNumToRanDAO(uint256)")
            .with_key(blockNumber)
            .checked_write(randao);
    }
}
