import { ethers } from "ethers";
import fs from 'fs';
import _ from "lodash";
import minimist from "minimist";

import { BLOCK_HEADER_FIELDS, cleanHeaderFields, getBlockHeaderFields } from "./utils";

async function generateProofInput(rpcUrl: string, blockNum: number) {
  // Get block data fields from RPC.
  console.log("Fetching block data from RPC...", {
    rpcUrl,
    blockNum,
  })
  const block = await getBlockHeaderFields(rpcUrl, blockNum);
  const expectedBlockhash = block.hash;

  // Clean required block header fields for RLP format spec.
  console.log("Cleaning block header fields");
  const cleanedHeaderFields = cleanHeaderFields(block);

  // RLP encode header fields.
  console.log("RLP encoding header fields");
  let rlp = ethers.utils.RLP.encode(_.at(cleanedHeaderFields, BLOCK_HEADER_FIELDS));

  // Derive blockhash from RLP encoded header.
  const derivedBlockhash = ethers.utils.keccak256(rlp);
  console.log("Derived blockhash from RLP encoded header", derivedBlockhash);

  // Sanity check derived blockhash matches blockhash from RPC.
  if (derivedBlockhash !== expectedBlockhash) {
    throw new Error("Blockhash mismatch, might be computing blockhash for pre-1559 blocks!");
  }

  // Remove 0x prefix.
  rlp = rlp.replace("0x", "");

  // Convert to hex.
  const rlpHexEncodedHeader = [...rlp].map((char) => parseInt(char, 16));
  console.log("Hex encoded RLP header", rlpHexEncodedHeader)

  // Pad to length 1112 required by circom circuit.
  const padLen = 1112 - rlpHexEncodedHeader.length;
  for (let i = 0; i < padLen; i++) {
    rlpHexEncodedHeader.push(0);
  }

  // Write proof input object.
  const rlpHeaderHex = {
    blockRlpHexs: rlpHexEncodedHeader,
  };

  // Write object to a block specific folder in circuits directory.
  const dir = `../circuits/single_block_header_zkp/proof_data_${blockNum}`;
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir);
  }
  const file = `../circuits/single_block_header_zkp/proof_data_${blockNum}/input.json`;

  console.log("Writing proof input file", {
    file,
    rlpHeaderHex,
  });

  // Write file.
  fs.writeFileSync(
    file,
    JSON.stringify(rlpHeaderHex, null, 2)
  );

  console.log("Finished writing proof input file", file);
}

const argv = minimist(process.argv.slice(2));
const blockNum = parseInt(argv.blockNum || process.env.BLOCK_NUM, 10);
const rpcUrl = argv.rpc || process.env.RPC_URL;

console.log("Parsed inputs", { blockNum, rpcUrl });

if (!blockNum) {
  throw new Error("CLI arg 'blockNum' is required!")
}

if (!rpcUrl) {
  throw new Error("CLI arg 'rpc' is required!")
}

// usage: $ yarn ts-node generateProofInput.ts --blockNum 8150150 --rpc https://ethereum-goerli-rpc.allthatnode.com
generateProofInput(rpcUrl, blockNum);
