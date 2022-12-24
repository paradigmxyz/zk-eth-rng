// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/StdJson.sol";
import "forge-std/Test.sol";

import "../src/BlockhashOpcodeOracle.sol";

contract BlockhashOpcodeOracleTest is Test {
    BlockhashOpcodeOracle blockhashOracle;

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        blockhashOracle = new BlockhashOpcodeOracle();
    }

    /// @notice Tests that poking attests to the previous block's block hash.
    function testPoke() public {
        uint256 blockNumToValidate = 1000;
        vm.roll(blockNumToValidate + 1);
        bytes32 blockhashToValidate = blockhash(blockNumToValidate);

        assertFalse(isValidBlockhash(blockhashToValidate));
        blockhashOracle.poke();
        assertTrue(isValidBlockhash(blockhashToValidate));
    }

    /// @notice Tests that poking a block 256 blocks back works since
    /// 256 is the blockhash opcode's limit.
    function testSpecificPokeValid() public {
        uint256 blockNumToValidate = 1000;
        vm.roll(blockNumToValidate + 256);
        bytes32 blockhashToValidate = blockhash(blockNumToValidate);

        assertFalse(isValidBlockhash(blockhashToValidate));
        blockhashOracle.pokeBlocknum(blockNumToValidate);
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
        return blockhashOracle.blockHashToNumber(blockHash) != 0;
    }
}
