# zk-eth-rng: Utilities for Randomness On Ethereum

![Github Actions](https://github.com/paradigmxyz/zk-eth-rng/workflows/Tests/badge.svg)

This repository contains contracts, circuits, and scripts related to generating and providing randomness for Ethereum's execution layer.

Meant to accompany the [eth-rng blog post](https://www.paradigm.xyz/2023/01/eth-rng).

## Getting Started

To get started with this repo, you will need to have the following set up on your machine:

- [Foundry](https://github.com/foundry-rs/foundry) to compile contracts and run Solidity tests
- [Yarn](https://yarnpkg.com/) and [Node.js](https://nodejs.org/) for running Typescript util scripts
- [Circom](https://docs.circom.io/getting-started/installation/) to interact with our circuits

### Setup

#### Circuit setup

```sh
cd circuits && yarn install
```

This automatically downloads a [powers of tau file](https://github.com/iden3/snarkjs#7-prepare-phase-2) required for generating ZKPs. This download might take a while.

#### Script setup
```sh
cd scripts && yarn install
```

### Directory Structure

The project is structured as a mixed Solidity, Circom, and Typescript workspace.

```
├── circuits  // <-- Circom source code
├── contracts // <-- Solidity source code
├── scripts   // <-- Block header & proof generation utils
```

### Block Hash Oracle

- [Blockhash oracle interface contract](contracts/src/IBlockhashOracle.sol)
- [Blockhash opcode based oracle contract implementation](contracts/src/BlockhashOpcodeOracle.sol), checkpointing block hashes via opcode lookup
- [ZK circuit](circuits/single_block_header_zkp/singleBlockHeader.circom) proving the parent blockhash of an already verified block via RLP deserialization, with [script](scripts/run_single_block_zkp.sh) to aid proof generation and corresponding [block hash oracle contract implementation](contracts/src/ZKBlockhashOracle.sol)
- [Helper script](scripts/run_single_block_zkp.sh) to generate raw data used in the ZK circuit; example of consuming illustrated in [ZKBlockhashOracleTest](contracts/test/ZKBlockhashOracle.t.sol)

To run Solidity tests:

```sh
cd contracts
forge test --match-contract "BlockhashOpcodeOracleTest|ZKBlockhashOracleTest"
```

To generate proof calldata for the ZK blockhash oracle contract:
```sh
# The circuit proves the parent hash of the specified BLOCK_NUM.
cd scripts
BLOCK_NUM=8150150 RPC_URL=https://ethereum-goerli-rpc.allthatnode.com ./run_single_block_zkp.sh
```

### Randomness Interface and Provider

- [Randomness provider interface](contracts/src/IRandomnessProvider.sol)
- [RANDAO randomness provider implementation](contracts/src/IRandomnessProvider.sol)
- [Helper scripts](contracts/scripts/generate) to generate properly formatted block data to fulfill randomness requests
- [VDF reference implementation](contracts/src/VDFProvider.sol)

To run Solidity tests:

```sh
cd contracts
forge test --match-contract "RANDAOOracleTest"
```

Optional: To generate new test data for the RANDAO-based randomness provider use the Typescript helper script:

```sh
cd scripts
yarn install
yarn ts-node generateBlockInfo.ts --blockNum 15539395 --rpc https://ethereum-mainnet-rpc.allthatnode.com
```

This will write a new JSON testdata file to `contracts/testdata/blockheaderinfo`. To include this block in the test, add the block number to the array similar to [this example](contracts/test/RandomnessProvider.t.sol#L42d).

## License

ZK related circuits & contracts and their tests are licensed under [GPL 3.0](LICENSE-GPL3.0) due to [circom's license](https://github.com/iden3/circom):

- [singleBlockHeader.circom](circuits/single_block_header_zkp/singleBlockHeader.circom)
- [SingleBlockHeaderVerifier.sol](contracts/src/SingleBlockHeaderVerifier.sol)
- [ZKBlockhashOracle.sol](contracts/src/ZKBlockhashOracle.sol)

These contracts and their tests are licensed under [MIT](LICENSE-MIT):

- [IBlockhashOracle.sol](contracts/src/IBlockhashOracle.sol)
- [BlockhashOpcodeOracle.sol](contracts/src/BlockhashOpcodeOracle.sol)
- [IRandomnessProvider.sol](contracts/src/IRandomnessProvider.sol)
- [RANDAOProvider.sol](contracts/src/RANDAOProvider.sol)

All code under [scripts](scripts) is licensed under [MIT](LICENSE-MIT).

## Disclaimer

Contracts and circuits are unoptimized, unaudited, and experimental — use at your own risk! Issues and pull requests are welcome.
