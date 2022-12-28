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
├── circuits // <-- Circom source code
├── contracts // <- Solidity source code
```

### Block Hash Oracle

- [Contract interface](contracts/src/IBlockhashOracle.sol) for block hash oracle
- Example [block hash oracle contract implementation](contracts/src/BlockhashOpcodeOracle.sol), checkpointing block hashes via opcode lookup
- ZK-circuit proving link between two blocks via RLP deserialization, with scripts to aid proof generation and corresponding [block hash oracle contract implementation](contracts/src/ZKBlockhashOracle.sol)
- [Helper script](contracts/scripts/generateBlockHashProofTestData.ts) to generate raw data used in the ZK circuit; example of consuming illustrated in [ZKBlockhashOracleTest](contracts/tests/ZKBlockhashOracleTest.ts).

To generate test data for the zk-based oracle, using the Typescript helper scripts:

```sh
cd contracts
yarn install
// TODO(sina) update this section as the code finalizes
yarn ts-node ./scripts/generateBlockHashProofTestData.ts
```

To run Solidity tests:

```sh
cd contracts
forge test --match-contract "BlockhashOpcodeOracleTest|ZKBlockhashOracleTest"
```

### Randomness Interface and Provider

- Contract interface for randomness provider
- Example randomness provider implementation, providing randomness from unrolled block headers
- Helper scripts to generate properly formatted transaction payload to fulfill randomness requests
- Stub VDF implementation

To run Solidity tests:

```sh
cd contracts
forge test --match-contract "RANDAOOracleTest"
```

## Usage (// TODO(sina) tighten this section as the code finalizes)

To run the contract tests:

```sh
forge test --filter=blockhashoracle
```

To generate a sample ZKP of the link between two blockhashes:

```sh
TODO some nodejs script, or some bash scripts?
```

// TODO(sina) add examples of how to run each of the js helpers and what to do with their outputs

## Disclaimer

// TODO

## License

// TODO
