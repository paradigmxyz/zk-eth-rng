pragma circom 2.0.2;

include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/multiplexer.circom";

include "./keccak.circom";
include "./rlp.circom";

template LeafCheck(maxKeyHexLen, maxValueHexLen) {
    var maxLeafRlpHexLen = 4 + (maxKeyHexLen + 2) + 4 + maxValueHexLen;
    var LEAF_BITS = log_ceil(maxLeafRlpHexLen);
    var arrayPrefixMaxHexLen = 2 * (LEAF_BITS \ 8 + 1);

    // FIXME: Differentiate between cases where keyLen is 0 and where the prefix+nibble is '1b'
    signal input keyNibbleHexLen;
    signal input keyNibbleHexs[maxKeyHexLen];
    signal input valueHexs[maxValueHexLen];

    // leaf = rlp_prefix           [2]
    //        rlp_length           [0, 2 * ceil(log_8(1 + ceil(log_8(keyHexLen + 2)) + 4 + keyHexLen + 2 + 2 * ceil(log_8(maxValueHexLen)) + maxValueHexLen))]
    //        path_rlp_prefix      [2]
    //        path_rlp_length      [0, 2 * ceil(log_8(keyHexLen + 2))]
    //        path_prefix          [0, 1, 2]
    //        path                 [0, keyHexLen]
    //        value_rlp_prefix     [2]
    //        value_rlp_length     [0, 2 * ceil(log_8(maxValueHexLen))]
    //        value                [0, maxValueHexLen]
    signal input leafRlpHexs[maxLeafRlpHexLen];

    signal input leafPathPrefixHexLen;

    signal output out;
    signal output outLen;
    signal output valueHexLen;

    log(111111100001);
    log(maxKeyHexLen);
    log(maxValueHexLen);

    log(keyNibbleHexLen);
    log(leafPathPrefixHexLen);

    for (var idx = 0; idx < maxKeyHexLen; idx++) {
	log(keyNibbleHexs[idx]);
    }
    for (var idx = 0; idx < maxValueHexLen; idx++) {
	log(valueHexs[idx]);
    }
    for (var idx = 0; idx < maxLeafRlpHexLen; idx++) {
	log(leafRlpHexs[idx]);
    }

    // check input hexes are hexes
    component hexCheck[maxLeafRlpHexLen];
    for (var idx = 0; idx < maxLeafRlpHexLen; idx++) {
	hexCheck[idx] = Num2Bits(4);
	hexCheck[idx].in <== leafRlpHexs[idx];
    }

    // check RLP validity
    component rlp = RlpArrayCheck(maxLeafRlpHexLen, 2, arrayPrefixMaxHexLen,
    	                          [0, 0],
				  [maxKeyHexLen + 2, maxValueHexLen]);
    for (var idx = 0; idx < maxLeafRlpHexLen; idx++) {
        rlp.in[idx] <== leafRlpHexs[idx];
    }
    
    // prefix check
    // if path prefix is even, then must be '20' and total length even
    // if path prefix is odd, then must be '3' and total length even
    // outcome of RlpArrayCheck always has even field sizes
    component pathPrefixOne = IsEqual();
    pathPrefixOne.in[0] <== leafPathPrefixHexLen;
    pathPrefixOne.in[1] <== 1;

    component pathPrefixTwo = IsEqual();
    pathPrefixTwo.in[0] <== leafPathPrefixHexLen;
    pathPrefixTwo.in[1] <== 2;

    component oneCheck = IsEqual();
    oneCheck.in[0] <== rlp.fields[0][0];
    oneCheck.in[1] <== 3;

    component twoCheck_1 = IsEqual();
    twoCheck_1.in[0] <== rlp.fields[0][0];
    twoCheck_1.in[1] <== 2;

    component twoCheck_2 = IsEqual();
    twoCheck_2.in[0] <== rlp.fields[0][1];
    twoCheck_2.in[1] <== 0;

    component oneValid = IsEqual();
    oneValid.in[0] <== pathPrefixOne.out + oneCheck.out;
    oneValid.in[1] <== 2;

    component twoValid = IsEqual();
    twoValid.in[0] <== pathPrefixTwo.out + twoCheck_1.out + twoCheck_2.out;
    twoValid.in[1] <== 3;

    signal prefixValid;
    prefixValid <== oneValid.out + twoValid.out - oneValid.out * twoValid.out;

    // check path matches keyNibbles using rlp.fields[0]
    component leaf_to_path = ShiftLeft(maxLeafRlpHexLen, 0, 2);
    for (var idx = 0; idx < maxLeafRlpHexLen; idx++) {
	leaf_to_path.in[idx] <== rlp.fields[0][idx];
    }
    leaf_to_path.shift <== leafPathPrefixHexLen;

    component key_path_match = ArrayEq(maxKeyHexLen);
    for (var idx = 0; idx < maxKeyHexLen; idx++) {
	key_path_match.a[idx] <== leaf_to_path.out[idx];
	key_path_match.b[idx] <== keyNibbleHexs[idx];
    }
    key_path_match.inLen <== rlp.fieldHexLen[0] - leafPathPrefixHexLen;

    component key_path_len_match = IsEqual();
    key_path_len_match.in[0] <== keyNibbleHexLen;
    key_path_len_match.in[1] <== rlp.fieldHexLen[0] - leafPathPrefixHexLen;

    signal key_path;
    key_path <== key_path_len_match.out * key_path_match.out;
    
    // check value matches valueBits using rlp.fields[1]
    component leaf_value_match = ArrayEq(maxValueHexLen);
    for (var idx = 0; idx < maxValueHexLen; idx++) {
	leaf_value_match.a[idx] <== rlp.fields[1][idx];
	leaf_value_match.b[idx] <== valueHexs[idx];
    }
    leaf_value_match.inLen <== rlp.fieldHexLen[1];

    out <== rlp.out + prefixValid + key_path + leaf_value_match.out;
    outLen <== rlp.totalRlpHexLen;
    valueHexLen <== rlp.fieldHexLen[1];

    log(out);
    log(key_path_len_match.out);
    log(key_path_match.out);
    log(leaf_value_match.out);
}

template ExtensionCheck(maxKeyHexLen, maxNodeRefHexLen) {
    var maxExtensionRlpHexLen = 4 + 2 + maxKeyHexLen + 2 + maxNodeRefHexLen;
    var EXTENSION_BITS = log_ceil(maxExtensionRlpHexLen);
    var arrayPrefixMaxHexLen = 2 * (EXTENSION_BITS \ 8 + 1);

    signal input keyNibbleHexLen;
    signal input keyNibbleHexs[maxKeyHexLen];

    signal input nodeRefHexLen;
    signal input nodeRefHexs[maxNodeRefHexLen];

    // extension = rlp_prefix           [2]
    //             rlp_length           [0, 2 * ceil((...))]
    //             path_rlp_prefix      [2]
    //             path_rlp_length      [0, 2 * ceil(log_8(keyHexLen + 2))]
    //             path_prefix          [1, 2]
    //             path                 [0, keyHexLen]
    //             node_ref_rlp_prefix  [2]
    //             node_ref             [0, 64]
    signal input nodeRlpHexs[maxExtensionRlpHexLen];

    signal input nodePathPrefixHexLen;

    signal output out;
    signal output outLen;	

    log(111111100002);
    log(maxKeyHexLen);
    log(maxNodeRefHexLen);

    log(keyNibbleHexLen);
    log(nodeRefHexLen);
    log(nodePathPrefixHexLen);

    for (var idx = 0; idx < maxKeyHexLen; idx++) {
	log(keyNibbleHexs[idx]);
    }
    for (var idx = 0; idx < maxNodeRefHexLen; idx++) {
	log(nodeRefHexs[idx]);
    }
    for (var idx = 0; idx < maxExtensionRlpHexLen; idx++) {
	log(nodeRlpHexs[idx]);
    }
    
    // check input hexs are hexs
    component hexChecks[maxExtensionRlpHexLen];
    for (var idx = 0; idx < maxExtensionRlpHexLen; idx++) {
	hexChecks[idx] = Num2Bits(4);
	hexChecks[idx].in <== nodeRlpHexs[idx];
    }

    // validity of RLP encoding
    component rlp = RlpArrayCheck(maxExtensionRlpHexLen, 2, arrayPrefixMaxHexLen,
                                  [0, 0],
				  [maxKeyHexLen + 2, maxNodeRefHexLen]);
    for (var idx = 0; idx < maxExtensionRlpHexLen; idx++) {
        rlp.in[idx] <== nodeRlpHexs[idx];
    }

    // prefix validity
    // if path prefix is even, then must be '00' and total length even
    // if path prefix is odd, then must be '1' and total length even
    // output of RlpArrayCheck always has even field sizes
    component pathPrefixOne = IsEqual();
    pathPrefixOne.in[0] <== nodePathPrefixHexLen;
    pathPrefixOne.in[1] <== 1;

    component pathPrefixTwo = IsEqual();
    pathPrefixTwo.in[0] <== nodePathPrefixHexLen;
    pathPrefixTwo.in[1] <== 2;

    component oneCheck = IsEqual();
    oneCheck.in[0] <== rlp.fields[0][0];
    oneCheck.in[1] <== 1;

    component twoCheck_1 = IsEqual();
    twoCheck_1.in[0] <== rlp.fields[0][0];
    twoCheck_1.in[1] <== 0;

    component twoCheck_2 = IsEqual();
    twoCheck_2.in[0] <== rlp.fields[0][1];
    twoCheck_2.in[1] <== 0;

    component oneValid = IsEqual();
    oneValid.in[0] <== pathPrefixOne.out + oneCheck.out;
    oneValid.in[1] <== 2;

    component twoValid = IsEqual();
    twoValid.in[0] <== pathPrefixTwo.out + twoCheck_1.out + twoCheck_2.out;
    twoValid.in[1] <== 3;

    signal prefixValid;
    prefixValid <== oneValid.out + twoValid.out - oneValid.out * twoValid.out;

    // check path contains nibbles of key using rlp.fields[0]
    component extension_to_path = ShiftLeft(maxExtensionRlpHexLen, 0, 2);
    for (var idx = 0; idx < maxExtensionRlpHexLen; idx++) {
	extension_to_path.in[idx] <== rlp.fields[0][idx];
    }
    extension_to_path.shift <== nodePathPrefixHexLen;
    
    component key_path_match = ArrayEq(maxKeyHexLen);
    for (var idx = 0; idx < maxKeyHexLen; idx++) {
	key_path_match.a[idx] <== extension_to_path.out[idx];
	key_path_match.b[idx] <== keyNibbleHexs[idx];
    }
    key_path_match.inLen <== rlp.fieldHexLen[0] - nodePathPrefixHexLen;
    
    component key_path_len_match = IsEqual();
    key_path_len_match.in[0] <== keyNibbleHexLen;
    key_path_len_match.in[1] <== rlp.fieldHexLen[0] - nodePathPrefixHexLen;
    
    signal key_path;
    key_path <== key_path_len_match.out * key_path_match.out;
    
    // check node_ref matches child using rlp.fields[1]
    component node_ref_match = ArrayEq(maxNodeRefHexLen);
    for (var idx = 0; idx < maxNodeRefHexLen; idx++) {
	node_ref_match.a[idx] <== rlp.fields[1][idx];
	node_ref_match.b[idx] <== nodeRefHexs[idx];
    }
    node_ref_match.inLen <== rlp.fieldHexLen[1];
    
    component node_ref_len_match = IsEqual();
    node_ref_len_match.in[0] <== nodeRefHexLen;
    node_ref_len_match.in[1] <== rlp.fieldHexLen[1];

    signal node_ref;
    node_ref <== node_ref_match.out * node_ref_len_match.out;
    
    out <== rlp.out + prefixValid + key_path + node_ref;
    outLen <== rlp.totalRlpHexLen;
    log(out);
    log(key_path_len_match.out);
    log(key_path_match.out);	
    log(node_ref_match.out);
    log(node_ref_len_match.out);	
}

template EmptyVtBranchCheck(maxNodeRefHexLen) {
    var maxBranchRlpHexLen = 1064;
    var BRANCH_BITS = 11;
    
    signal input keyNibble;

    signal input nodeRefHexLen;
    signal input nodeRefHexs[maxNodeRefHexLen];

    // branch = rlp_prefix              [2]
    //          rlp_length              [0, 8]
    //          v0_rlp_prefix           [2]
    //          v0                      [0, 64]
    //          ...
    //          v15_rlp_prefix          [2]
    //          v15                     [0, 64]
    //          vt_rlp_prefix           [2]
    //          vt_rlp_length           [0]
    //          vt                      [0]
    signal input nodeRlpHexs[maxBranchRlpHexLen];
    
    signal output out;
    signal output outLen;

    log(111111100004);
    log(maxNodeRefHexLen);
    
    log(keyNibble);
    log(nodeRefHexLen);

    log(maxBranchRlpHexLen);
    for (var idx = 0; idx < maxNodeRefHexLen; idx++) {
	log(nodeRefHexs[idx]);
    }
    for (var idx = 0; idx < maxBranchRlpHexLen; idx++) {
	log(nodeRlpHexs[idx]);
    }
   
    // check input hexs are hexs
    component keyNibbleCheck = Num2Bits(4);
    keyNibbleCheck.in <== keyNibble;

    component hexChecks[maxBranchRlpHexLen];
    for (var idx = 0; idx < maxBranchRlpHexLen; idx++) {
	hexChecks[idx] = Num2Bits(4);
	hexChecks[idx].in <== nodeRlpHexs[idx];
    }

    // check RLP validity
    component rlp = RlpArrayCheck(maxBranchRlpHexLen, 17, 8,
                                  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	                          [64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 0]);
    for (var idx = 0; idx < maxBranchRlpHexLen; idx++) {
        rlp.in[idx] <== nodeRlpHexs[idx];
    }

    // check node_ref at index of nibble / value matches child / value
    component nodeRefSelector = Multiplexer(64, 16);
    component nodeRefHexLenSelector = Multiplexer(1, 16);
    for (var idx = 0; idx < 16; idx++) {
        for (var j = 0; j < 64; j++) {
	    nodeRefSelector.inp[idx][j] <== rlp.fields[idx][j];
	}
	nodeRefHexLenSelector.inp[idx][0] <== rlp.fieldHexLen[idx];
    }
    nodeRefSelector.sel <== keyNibble;
    nodeRefHexLenSelector.sel <== keyNibble;
    
    component node_ref_match = ArrayEq(maxNodeRefHexLen);
    for (var idx = 0; idx < maxNodeRefHexLen; idx++) {
	node_ref_match.a[idx] <== nodeRefSelector.out[idx];
	node_ref_match.b[idx] <== nodeRefHexs[idx];
    }
    node_ref_match.inLen <== nodeRefHexLen;

    component node_ref_len_match = IsEqual();
    node_ref_len_match.in[0] <== nodeRefHexLen;
    node_ref_len_match.in[1] <== nodeRefHexLenSelector.out[0];

    out <== rlp.out + node_ref_match.out + node_ref_len_match.out + 1;
    outLen <== rlp.totalRlpHexLen;

    log(out);
    log(node_ref_match.out);
    log(node_ref_len_match.out);
}

