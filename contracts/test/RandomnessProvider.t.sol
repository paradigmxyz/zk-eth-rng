// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import {LibString} from "solmate/utils/LibString.sol";

import "../src/RANDAOProvider.sol";
import "../src/BlockhashOpcodeOracle.sol";
import "../src/ZKBlockhashOracle.sol";

contract RANDAOOracleTest is Test {
    using stdJson for string;
    using stdStorage for StdStorage;

    BlockhashOpcodeOracle public blockhashOracle;
    RANDAOProvider public randomProvider;

    uint256[] public blockNums;

    uint256 constant mockRANDAO = 74959964106633704346858077179036090420725799257578598593094705978576627503466;

    // Blockhash oracle upgrade event from randomness provider.
    event BlockhashOracleUpgraded(address, address);

    // Randomness Requested event from randomness provider.
    event RandomnessRequested(address indexed requester, uint256 indexed requestedBlock);

    // Randomness available for use event from randomness provider.
    event RandomnessFulfilled(uint256 indexed fulfilledBlock, uint256 randomSeed);

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        blockhashOracle = new BlockhashOpcodeOracle();
        randomProvider = new RANDAOProvider(blockhashOracle);

        // Only testing blocknums that we have blockdata json files for.
        blockNums.push(15537394);
        blockNums.push(15537395);
        blockNums.push(15539395);
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that the constructor pokes the blockhash of the previous block.
    function testConstructorPoke() public {
        vm.roll(100);
        uint256 pokedRANDAO = block.difficulty;

        vm.expectEmit(true, false, false, true);
        emit RandomnessFulfilled(100, pokedRANDAO);

        RANDAOProvider provider = new RANDAOProvider(blockhashOracle);
        assertEq(provider.blockNumToRANDAO(100), pokedRANDAO);
    }

    /*//////////////////////////////////////////////////////////////
                            RANDOMNESS REQUESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that block returned from randomness request
    /// is >= current block + MIN_LOOKAHEAD_BUFFER and is
    /// a multiple of ROUNDING_CONSTANT.
    function testRandomnessRequest(uint256 currentBlock) public {
        vm.assume(
            currentBlock
                < type(uint256).max - randomProvider.MIN_LOOKAHEAD_BUFFER() - randomProvider.ROUNDING_CONSTANT()
        );
        vm.roll(currentBlock);

        uint256 randomnessBlock = randomProvider.requestRandomness();

        // Assert the retrieved block is greater or equal to
        // the current block + the minimum buffer lookahead.
        assertGe(randomnessBlock, currentBlock + randomProvider.MIN_LOOKAHEAD_BUFFER());

        // Assert the retrieved blocks is a multiple of the rounding
        // constant.
        assertEq(0, randomnessBlock % randomProvider.ROUNDING_CONSTANT());

        // Assert that retrieved block is isn't too far in the future.
        uint256 maxDistance = randomProvider.ROUNDING_CONSTANT() + randomProvider.MIN_LOOKAHEAD_BUFFER();
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
    function testCannotRequestRandomnessForCurrentOrPastBlock(uint256 blockNum) public {
        vm.roll(200);
        vm.assume(blockNum <= 200);

        vm.expectRevert(abi.encodeWithSelector(RANDAOProvider.RequestedRandomnessFromPast.selector, 200));

        randomProvider.requestRandomnessFromBlock(200);
    }

    /*//////////////////////////////////////////////////////////////
                        RANDOMNESS SUBMISSION
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that we can extract and attest to
    /// the RANDAO value for blocks that are verified by our blockhash oracle.
    function testCanSubmitRANDAO() public {
        for (uint256 i = 0; i < blockNums.length; ++i) {
            internalRecoverVerifiedRANDAOValue(blockNums[i], true);
        }
    }

    /// @notice Tests that we can't attest to RANDAO values
    /// that aren't verified by our blockhash oracle.
    function testCannotSubmitRANDAO() public {
        for (uint256 i = 0; i < blockNums.length; ++i) {
            internalRecoverVerifiedRANDAOValue(blockNums[i], false);
        }
    }

    /// @notice Tests that a valid RLP encoded header will properly
    /// extract and attest to the RANDAO value when blockhash is
    /// validated and that it won't attest if blockhash hasn't
    /// been validated yet.
    function internalRecoverVerifiedRANDAOValue(uint256 blockNum, bool validBlockhash) internal {
        (bytes32 expectedHash, bytes memory rlp, bytes32 expectedRANDAO) = readBlockDataFile(blockNum);
        // Sanity check, RLP matches expected hash.
        assertEq(keccak256(rlp), expectedHash);

        if (validBlockhash) {
            // Mock validity of blockhash through oracle.
            mockOracle(expectedHash, blockNum);

            // Expect randomness availability event.
            vm.expectEmit(true, false, false, false, address(randomProvider));
            emit RandomnessFulfilled(blockNum, 1);

            // Attempt to submit a single RANDAO value.
            uint256 derivedRANDAO = randomProvider.submitRANDAO(rlp);

            // Sanity check that it matches expected.
            assertEq(bytes32(derivedRANDAO), expectedRANDAO);

            // Verify RANDAO value exists and can be fetched in the future.
            vm.roll(blockNum + 1);
            uint256[] memory fetchedRandomValues = randomProvider.fetchRandomness(blockNum, 1);
            assertEq(bytes32(fetchedRandomValues[0]), expectedRANDAO);
        } else {
            mockOracle(expectedHash, 0);

            vm.expectRevert(abi.encodeWithSelector(RANDAOProvider.BlockhashUnverified.selector, keccak256(rlp)));

            // Submit a single RANDAO value, expecting function to revert.
            randomProvider.submitRANDAO(rlp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FETCHING RANDOMNESS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that we can fetch an arbitrary amount of random values,
    /// given RANDAO value is proven in contract.
    function testFetchingRandomness(uint8 numRandomValues) public {
        vm.assume(numRandomValues > 0);
        uint256 blockNum = 100;
        mockRANDAOAtBlock(blockNum, mockRANDAO);

        uint256[] memory randomValues = randomProvider.fetchRandomness(blockNum, numRandomValues);

        assertEq(randomValues.length, numRandomValues);
        assertEq(randomValues[0], mockRANDAO);

        for (uint256 i = 1; i < numRandomValues; i++) {
            assertEq(randomValues[i], uint256(keccak256(abi.encodePacked(randomValues[i - 1]))));
        }

        for (uint256 i = 0; i < numRandomValues; i++) {
            for (uint256 j = i + 1; j < numRandomValues; j++) {
                assertTrue(randomValues[i] != randomValues[j]);
            }
        }
    }

    /// @notice Tests that we can't fetch randomness if RANDAO value
    /// isn't attested to.
    function testCannotFetchRandomnessWithoutValidRANDAOSubmission() public {
        uint256 blockNum = 100;
        mockRANDAOAtBlock(blockNum, 0);

        vm.expectRevert(abi.encodeWithSelector(RANDAOProvider.RandomnessNotAvailable.selector, blockNum));

        randomProvider.fetchRandomness(blockNum, 1);
    }

    /// @notice Tests that we can't request 0 random values.
    function testCannotFetchZeroRandomValues() public {
        uint256 blockNum = 100;
        mockRANDAOAtBlock(blockNum, mockRANDAO);

        vm.expectRevert(RANDAOProvider.RequestedZeroRandomValues.selector);

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
        view
        returns (bytes32 expectedHash, bytes memory rlp, bytes32 mixHash)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/testdata/blockheaderinfo/", LibString.toString(blockNum), ".json");
        string memory json = vm.readFile(path);

        expectedHash = json.readBytes32(".goldenHash");
        rlp = json.readBytes(".rlp");
        mixHash = json.readBytes32(".cleanedHeaderFields.mixHash");
    }

    /// @notice Mocks the block hash oracle's response for a validity check.
    function mockOracle(bytes32 blockHash, uint256 response) internal {
        stdstore.target(address(blockhashOracle)).sig("blockhashToBlockNum(bytes32)").with_key(blockHash).checked_write(
            response
        );
    }

    /// @notice Mocks the RANDAO value for a block.
    function mockRANDAOAtBlock(uint256 blockNumber, uint256 RANDAO) internal {
        stdstore.target(address(randomProvider)).sig("blockNumToRANDAO(uint256)").with_key(blockNumber).checked_write(
            RANDAO
        );
    }
}
