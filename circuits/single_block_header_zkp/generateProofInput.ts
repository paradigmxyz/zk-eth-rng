import { ethers } from "ethers";
import axios from "axios";
import fs from 'fs';

const generateProofInput = async (blocknum: number, rpcURL: string) => {
  // Get block header RLP encoded.
  const rlpHexEncodedHeader = await constructHexRLPHeader(blocknum, rpcURL);

  // Write proof input file.
  const output = {
    blockRlpHexs: rlpHexEncodedHeader,
  };

  // Run script from ciruits directory.
  const dir = `./single_block_header_zkp/proof_data_${blocknum}`;
  if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir);
  }
  const file = `./single_block_header_zkp/proof_data_${blocknum}/input.json`;

  const jsonfile = require("jsonfile");
  jsonfile.writeFileSync(file, output);
  return;
};

// Encodes a block header response from eth_getBlockByNumber into RLP.
const constructHexRLPHeader = async (blockNumber: number, rpcURL: string) => {
  // Construct RLP encoded block header.
  const blockHeaderData = (await axios.post(rpcURL, {
    jsonrpc: "2.0",
    id: 0,
    method: "eth_getBlockByNumber",
    params: [
      blockNumber ? "0x" + blockNumber.toString(16) : "latest", false],
  })).data.result;

  const {
    parentHash,
    sha3Uncles,
    miner, // Coinbase
    stateRoot,
    transactionsRoot,
    receiptsRoot,
    logsBloom,
    difficulty,
    number,
    gasLimit,
    gasUsed,
    timestamp,
    extraData,
    mixHash,
    nonce,
    baseFeePerGas, // For Post 1559 blocks
    hash, // For comparison afterwards
  } = blockHeaderData;

  // Construct bytes like input to RLP encode function
  const blockHeaderInputs: { [key: string]: string } = {
    parentHash,
    sha3Uncles,
    miner,
    stateRoot,
    transactionsRoot,
    receiptsRoot,
    logsBloom,
    difficulty,
    number,
    gasLimit,
    gasUsed,
    timestamp,
    extraData,
    mixHash,
    nonce,
    baseFeePerGas // Post 1559 Blocks
  };

  Object.keys(blockHeaderInputs).map((key: string) => {
    let val = blockHeaderInputs[key];

    // All 0 values for these fields must be 0x
    if (["gasLimit", "gasUsed", "timestamp", "difficulty", "number"].includes(key)) {
      if (parseInt(val, 16) === 0) {
        val = "0x";
      }
    }

    // Pad hex for proper Bytes parsing
    if (val.length % 2 == 1) {
      val = val.substring(0, 2) + "0" + val.substring(2);
    }

    blockHeaderInputs[key] = val;
  });

  let rlpEncodedHeader = ethers.utils.RLP.encode(
    Object.values(blockHeaderInputs)
  );
  const derivedBlockHash = ethers.utils.keccak256(rlpEncodedHeader);

  console.log("=========================");
  console.log("Block Number", number);
  console.log("Mix hash", mixHash);
  console.log("RLP Derived Block Hash", derivedBlockHash);
  console.log("Actual Block Hash", hash);
  if (derivedBlockHash !== hash) {
    throw new Error(`Derived ${derivedBlockHash} doesn't match expected ${hash}`);
  }

  rlpEncodedHeader = rlpEncodedHeader.replace("0x", ""); // Remove 0x prefix.
  const rlpHexEncodedHeader = [...rlpEncodedHeader].map((char) => parseInt(char, 16));

  // Pad to 1112 bytes required by circom circuit.
  const padLen = 1112 - rlpHexEncodedHeader.length;
  for (let i = 0; i<padLen; i++) {
    if (padLen > 0) {
      rlpHexEncodedHeader.push(0);
    }
  }

  return rlpHexEncodedHeader;
};

const main = async () => {
  const { height, rpcURL } = require('minimist')(process.argv.slice(2));
  if (!height) {
    throw new Error("CLI arg 'height' is required!")
  }
  if (!rpcURL) {
    throw new Error("CLI arg 'rpcURL' is required!")
  }
  generateProofInput(height, rpcURL);
}

main();
