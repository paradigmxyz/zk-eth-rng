import fs from "fs";
import _ from "lodash";
import { ethers } from "ethers";
import minimist from "minimist";

import { BLOCK_HEADER_FIELDS, cleanHeaderFields, getBlockHeaderFields } from "./utils";

async function generateBlockInfo(rpcUrl: string, blockNum: number) {
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
    const rlp = ethers.utils.RLP.encode(_.at(cleanedHeaderFields, BLOCK_HEADER_FIELDS));

    // Derive blockhash from RLP encoded header.
    const derivedBlockhash = ethers.utils.keccak256(rlp);
    console.log("Derived blockhash from RLP encoded header", derivedBlockhash);

    // Sanity check derived blockhash matches blockhash from RPC.
    if (derivedBlockhash !== expectedBlockhash) {
        throw new Error("Blockhash mismatch, might be computing blockhash for pre-1559 blocks!");
    }

    // Construct block info object
    const blockInfo = {
        cleanedHeaderFields,
        rlp,
        goldenHash: block.hash,
        calculatedHash: ethers.utils.keccak256(rlp),
    };
    console.log("Block info:", blockInfo);

    // Write object
    fs.writeFileSync(
        `../contracts/testdata/blockheaderinfo/${blockNum}.json`,
        JSON.stringify(blockInfo, null, 2)
    );
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

// usage: $ yarn ts-node generateBlockInfo.ts --blockNum 15539395 --rpc https://ethereum-mainnet-rpc.allthatnode.com
generateBlockInfo(rpcUrl, blockNum);
