// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/StdJson.sol";
import "forge-std/Test.sol";

import "../src/BlockhashOpcodeOracle.sol";

contract BlockhashOpcodeOracleTest is Test {
    BlockhashOpcodeOracle blockhashOracle;

    /// Emits the validated block number and block hash.
    event BlockhashValidated(uint256 indexed blockNum, bytes32 indexed blockHash);

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        blockhashOracle = new BlockhashOpcodeOracle();
    }

    /// @notice Tests that the constructor pokes the blockhash of the previous block.
    function testConstructorPoke() public {
        vm.roll(100);
        bytes32 pokedBlockhash = blockhash(99);

        // Expect randomness availability event.
        vm.expectEmit(true, true, false, false);
        emit BlockhashValidated(99, pokedBlockhash);

        BlockhashOpcodeOracle oracle = new BlockhashOpcodeOracle();
        assertEq(oracle.blockhashToBlockNum(pokedBlockhash), 99);
    }

    /// @notice Tests that poking attests to the previous block's block hash.
    function testPoke() public {
        uint256 blockNumToValidate = 1000;
        vm.roll(blockNumToValidate + 1);
        bytes32 blockhashToValidate = blockhash(blockNumToValidate);

        assertFalse(isValidBlockhash(blockhashToValidate));

        (uint256 pokedBlocknum, bytes32 pokedBlockhash) = blockhashOracle.poke();
        assertEq(pokedBlocknum, blockNumToValidate);
        assertEq(pokedBlockhash, blockhashToValidate);

        assertTrue(isValidBlockhash(blockhashToValidate));
    }

    /// @notice Tests that poking a block 256 blocks back works since
    /// 256 is the blockhash opcode's limit.
    function testSpecificPokeValid() public {
        uint256 blockNumToValidate = 1000;
        vm.roll(blockNumToValidate + 256);
        bytes32 blockhashToValidate = blockhash(blockNumToValidate);

        assertFalse(isValidBlockhash(blockhashToValidate));
        
        bytes32 pokedBlockhash = blockhashOracle.pokeBlocknum(blockNumToValidate);
        assertEq(pokedBlockhash, blockhashToValidate);

        assertTrue(isValidBlockhash(blockhashToValidate));
    }

    /// @notice Tests that poking a block further than 256 blocks back
    /// fails since the blockhash opcode can only lookback 256.
    function testSpecificPokeInvalid() public {
        uint256 blockNumToValidate = 1000;
        vm.roll(blockNumToValidate + 257);
        bytes32 blockhashToValidate = blockhash(blockNumToValidate);

        assertFalse(isValidBlockhash(blockhashToValidate));
        vm.expectRevert(BlockhashOpcodeOracle.PokeRangeError.selector);

        blockhashOracle.pokeBlocknum(blockNumToValidate);
    }

    /// @notice Wrapper function that determines if a block hash is valid.
    function isValidBlockhash(bytes32 blockHash) internal view returns (bool) {
        return blockhashOracle.blockhashToBlockNum(blockHash) != 0;
    }
}
