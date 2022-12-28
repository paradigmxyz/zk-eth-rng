import _ from "lodash";
import { ethers } from "ethers";

export type Block = {
    parentHash: string;
    sha3Uncles: string;
    miner: string;
    stateRoot: string;
    transactionsRoot: string;
    receiptsRoot: string;
    logsBloom: string;
    difficulty: string;
    number: string;
    gasLimit: string;
    gasUsed: string;
    timestamp: string;
    extraData: string;
    mixHash: string;
    nonce: string;
    baseFeePerGas: string;
    hash: string;
}

export const BLOCK_HEADER_FIELDS = [
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

// Retrieves block header fields from specified JSON RPC endpoint for a given block number.
export async function getBlockHeaderFields(rpcUrl: string, blockNumber: number): Promise<Block> {
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    const block = await provider.send("eth_getBlockByNumber", [
        ethers.utils.hexValue(blockNumber),
        false,
    ]);

    const blockHeader = _.pick(block, ["hash", ...BLOCK_HEADER_FIELDS]) as Block;
    return blockHeader;
}

// Cleans header fields to conform to the expected RLP format.
export function cleanHeaderFields(header: Block): Block {
    const cleanedHeader = _.mapValues(header, (val, key) => {
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

    return cleanedHeader;
}

const constructBlockSummary = async () => {

}

const writeProofInputFile = async () => {

}

(async () => {
    // Get block data fields from RPC.
    const block = await getBlockHeaderFields("https://ethereum-goerli-rpc.allthatnode.com", 8150150);
    const expectedBlockhash = block.hash;

    // Clean required block header fields for RLP format spec.
    const cleanedHeader = cleanHeaderFields(block);

    // RLP encode header fields.
    const rlp = ethers.utils.RLP.encode(_.at(cleanedHeader, BLOCK_HEADER_FIELDS));

    // Derive blockhash from RLP encoded header.
    const derivedBlockhash = ethers.utils.keccak256(rlp);

    // Sanity check
    if (derivedBlockhash !== expectedBlockhash) {
        throw new Error("Blockhash mismatch, might be computing blockhash for pre-1559 blocks!");
    }
})()

/*
    Get block data
    Clean header fields
        Throw if past 1559 if possible
    RLP encode header fields
    Hash to block hashs
    Sanity check

    1. (RLP Tesdata file) Write into block info json
        Construct block info json

*/