# eth-rng: Utilities for Randomness Generation On Ethereum

This repository contains various scripts and utilities related to generating randomness on the Ethereum blockchain.

Meant to accompany the [eth-rng blog post](https://www.paradigm.xyz/2023/01/eth-rng).

## Getting Started

To get started with this repo, you will need to have the following set up on your machine:

- [Foundry](https://github.com/foundry-rs/foundry) to compile contracts and run Solidity tests
- [yarn](https://yarnpkg.com/) and [Node.js](https://nodejs.org/) for running Typescript util scripts

### Directory Structure

The project is structured as a mixed Solidity and Circom workspace.

```
├── circuits  // <-- Circom source code
├── contracts // <- Solidity source code
├── scripts   // <- Typescript utility scripts
```

### Block Hash Oracle

- [Contract interface](contracts/src/IBlockhashOracle.sol) for block hash oracle
- Example [block hash oracle contract implementation](contracts/src/BlockhashOpcodeOracle.sol), checkpointing block hashes via opcode lookup
- ZK-circuit proving link between two blocks via RLP deserialization, with scripts to aid proof generation and corresponding [block hash oracle contract implementation](contracts/src/ZKBlockhashOracle.sol)
- [Helper script](contracts/scripts/generateBlockHashProofTestData.ts) to generate raw data used in the ZK circuit; example of consuming illustrated in [ZKBlockhashOracleTest](contracts/tests/ZKBlockhashOracleTest.ts).

// TODO add details of using the TS helper script to generate ZK circuit data

To run Solidity tests:

```sh
cd contracts
forge test --match-contract "BlockhashOpcodeOracleTest|ZKBlockhashOracleTest"
```

### Randomness Interface and Provider

- [Contract interface](contracts/src/IRandomnessProvider.sol) for randomness provider
- Example [randomness provider implementation](contracts/src/RANDAOProvider.sol), providing randomness from unrolled block headers
- [Helper scripts](contracts/scripts/generate) to generate properly formatted transaction payload to fulfill randomness requests
- [VDF reference implementation](contracts/src/VDFProvider.sol)

To generate test data for the RANDAO-based randomness provider using the Typescript helper script:

```sh
cd scripts
yarn install
yarn ts-node generateBlockInfo.ts --blockNum 15539395 --rpc https://ethereum-mainnet-rpc.allthatnode.com
```

This will write a new JSON testdata file to `contracts/testdata/blockheaderinfo`. To include this block in the test, add the block number to the array similar to [this example](contracts/test/RandomnessProvider.t.sol#L42d).

To run Solidity tests:

```sh
cd contracts
forge test --match-contract "RANDAOOracleTest"
```

### Circuits

// TODO section laying out what's going on in this folder potentially with some links, and then a short example of how to run tests/scripts

## Disclaimer

// TODO

## License

// TODO
