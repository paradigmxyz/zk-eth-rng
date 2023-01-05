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

// Cleans header fields to the expected RLP format.
export function cleanHeaderFields(header: Block): Block {
    const cleanedHeader = _.mapValues(header, (val: string, key: string) => {
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
