pragma circom 2.0.2;

include "../utils/keccak.circom";
include "../utils/rlp.circom";
include "../utils/mpt.circom";

// DISCLAIMER: This circuit was built on top of Yi Sun's zk-attestor circuits.
// https://github.com/yi-sun/zk-attestor/tree/f4f4b2268f7cf8a0e5ac7f2b5df06a61859f18ca
// We've made our own modifications to extract additional block header fields.

// This simplified zk-SNARK commits the ParentHash for a given valid block hash.
// For any blockhash validated on chain (either through blockhash opcode or other blockhash oracle), 
// running this proof for that block hash will attest to the parentHash of that block.
// An RLP of that parent block's header can then be provided onchain to prove block contents 
// like mixHash (RANDAO) and another parentHash.
// This can be repeated to continue proving the prior block hashes (in linear on chain compute/space).

// This circuit focuses on the input's block hash, height, parent hash, mixhash (block randomness)
template SingleEthBlockHashHex() {
    signal input blockRlpHexs[1112];

    signal output currentHash[64];
    signal output parentHash[64];
    signal output blockNumber[6];
    signal output mixHash[64];
    // see the public.json to get the values of these signals. they are stored as a flattened array,
    // so the first 64 values => current Hash (in hex), next 64 values => parent hash (in hex),
    // next 6 => hex encoded block number, last 64 => mixHash block header for the block

    // RLP circuit, defining length of elements
    component rlp = RlpArrayCheck(1112, 16, 4,
                [64, 64, 40, 64, 64, 64, 512,  0, 0, 0, 0, 0,  0, 64, 16,  0],
				[64, 64, 40, 64, 64, 64, 512, 14, 6, 8, 8, 8, 64, 64, 18, 10]);
    for (var idx = 0; idx < 1112; idx++) {
    	rlp.in[idx] <== blockRlpHexs[idx];
    }  // helper for grabbing specific key/values from the RLP

    var blockRlpHexLen = rlp.totalRlpHexLen;
    component pad = ReorderPad101Hex(1016, 1112, 1360, 13);
    pad.inLen <== blockRlpHexLen;
    for (var idx = 0; idx < 1112; idx++) {
        pad.in[idx] <== blockRlpHexs[idx];
    }

    component leq = LessEqThan(13);
    leq.in[0] <== blockRlpHexLen + 1;
    leq.in[1] <== 1088;
    
    var blockSizeHex = 136 * 2;
    component keccak = Keccak256Hex(5);
    for (var idx = 0; idx < 5 * blockSizeHex; idx++) {
        keccak.inPaddedHex[idx] <== pad.out[idx];
    }
    keccak.rounds <== 5 - leq.out;

    // Set currentHash as keccak over RLP encoded block header.
    for (var idx = 0; idx < 32; idx++) {
        currentHash[2 * idx] <== keccak.out[2 * idx + 1];
        currentHash[2 * idx + 1] <== keccak.out[2 * idx];
    }

    // Extract parentHash and mixHash values from the block header.
    for (var idx = 0; idx < 64; idx++) {
        parentHash[idx] <== rlp.fields[0][idx];
        mixHash[idx] <== rlp.fields[13][idx];
    }

    // Extract blockNumber from the block header.
    for (var idx = 0; idx < 6; idx++) {
        blockNumber[idx] <== rlp.fields[8][idx];
    }
 }

component main = SingleEthBlockHashHex();
