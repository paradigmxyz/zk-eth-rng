import fs from "fs";
import _ from "lodash";
import { ethers } from "ethers";
import minimist from "minimist";

const argv = minimist(process.argv.slice(2));
// usage: $yarn run getBlockInfo -- --blocknum 15705750 --rpc https://mainnet.infura.io/v3/<redac>

const FIRST_MERGE_BLOCK = 15537394;
const BLOCK_HEADER_FIELDS = [
    "parentHash",
    "sha3Uncles",
    "miner",
    "stateRoot",
    "transactionsRoot",
    "receiptsRoot",
    "logsBloom",
    "difficulty",
    "number",
    "gasLimit",
    "gasUsed",
    "timestamp",
    "extraData",
    "mixHash",
    "nonce",
    "baseFeePerGas",
];

const writeBlockHeaderRlp = async (
    blockNum: number,
    provider: ethers.providers.JsonRpcProvider
) => {
    // Get block header fields from RPC.
    const block = await provider.send("eth_getBlockByNumber", [
        ethers.utils.hexValue(blockNum),
        false,
    ]);
    const headerFields = _.pick(block, BLOCK_HEADER_FIELDS);
    // Clean header fields.
    const cleanedHeaderFields = _.mapValues(headerFields, (val, key) => {
        // Zero values should just be 0x, unless it's for the nonce.
        if (parseInt(val, 16) === 0 && key !== "nonce") {
            return "0x";
        }
        // Pad hex for proper Bytes parsing.
        if (val.length % 2 == 1) {
            return val.substring(0, 2) + "0" + val.substring(2);
        }
        return val;
    });

    const rlp = ethers.utils.RLP.encode(
        _.at(cleanedHeaderFields, BLOCK_HEADER_FIELDS)
    );

    const finalObj = {
        cleanedHeaderFields,
        rlp,
        goldenHash: block.hash,
        calculatedHash: ethers.utils.keccak256(rlp),
    };

    fs.writeFileSync(
        `../solidity/testdata/blockheaderinfo/${blockNum}.json`,
        JSON.stringify(finalObj, null, 2)
    );
};

const blockNum = parseInt(argv.blocknum, 10);
const rpcUrl = argv.rpc || process.env.RPC_URL;
console.log({ msg: "parsed inputs", blockNum, rpcUrl });
if (!blockNum || blockNum < FIRST_MERGE_BLOCK || !rpcUrl) {
    throw new Error("Got bad args");
}
const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

writeBlockHeaderRlp(blockNum, provider);
