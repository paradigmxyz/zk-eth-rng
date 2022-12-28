#!/bin/bash

# High level steps:
# 1. Generates RLP encoded blockheader input for the circuit.
# 2. Compiles the circuit.
# 3. Generates a witness.
# 4. Generates a trusted setup.
# 5. Generates a proof.
# 6. Generates calldata for verifier contract.

# Instructions:
# Run from circuits directory
# Example usage: BLOCK_NUM=8150150 ./single_block_header_zkp/build_single_block.sh
# Outputs to /build and /proof_data_${BLOCK_NUM} directories

# Notes:
# 1. If singleBlockHeader.circom is modified, delete the build folder and rerun this script.
# 2. When encountering errors, try deleting ./single_block_header_zkp/build and/or rerunning this script.

set -e

# Change RPC URL to the desired network
RPC_URL="https://ethereum-goerli-rpc.allthatnode.com"

# Download the powers of tau file from here: https://github.com/iden3/snarkjs#7-prepare-phase-2
# Move to directory specified below
PHASE1=./powers_of_tau/powersOfTau28_hez_final_22.ptau

# Relevant directories.
BUILD_DIR=./single_block_header_zkp/build
COMPILED_DIR=$BUILD_DIR/compiled_circuit
TRUSTED_SETUP_DIR=$BUILD_DIR/trusted_setup
BLOCK_DIR=./single_block_header_zkp/proof_data_${BLOCK_NUM}

CIRCUIT_NAME=singleBlockHeader

echo "BLOCK_NUM: $BLOCK_NUM"
if [[ ! -z "${DEPLOY_ENV}" ]]; then
    echo "Provide BLOCK_NUM environment variable. Exiting..."
    exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "No build directory found. Creating build directory..."
    mkdir "$BUILD_DIR"
fi

if [ ! -d "$COMPILED_DIR" ]; then
    echo "No compiled directory found. Creating compiled circuit directory..."
    mkdir "$COMPILED_DIR"
fi

if [ ! -d "$TRUSTED_SETUP_DIR" ]; then
    echo "No trusted setup directory found. Creating trusted setup directory..."
    mkdir "$TRUSTED_SETUP_DIR"
fi

if [ ! -d "$BLOCK_DIR" ]; then
    echo "No directory found for proof data. Creating a block's proof data directory..."
    mkdir "$BLOCK_DIR"
fi

echo $PWD

echo "****GENERATING INPUT FOR PROOF****"
echo $BLOCK_DIR/input.json
start=`date +%s`
yarn ts-node ./single_block_header_zkp/generateProofInput.ts --blockNum ${BLOCK_NUM} --rpc ${RPC_URL}
end=`date +%s`
echo "DONE ($((end-start))s)"

if [ ! -f "$COMPILED_DIR"/"$CIRCUIT_NAME".r1cs ]; then
    echo "**** COMPILING CIRCUIT $CIRCUIT_NAME.circom ****"
    start=`date +%s`
    circom "./single_block_header_zkp/$CIRCUIT_NAME".circom --O1 --r1cs --wasm --c --sym --output "$COMPILED_DIR"
    end=`date +%s`
    echo "DONE ($((end-start))s)"
fi

echo "****GENERATING WITNESS FOR SAMPLE INPUT****"
echo $BLOCK_DIR/input.json
if [ -f $BLOCK_DIR/input.json ]; then
    echo "Found input file!"
else
    echo "No input file found. Exiting..."
    exit 1
fi

start=`date +%s`
node "$COMPILED_DIR"/"$CIRCUIT_NAME"_js/generate_witness.js \
    "$COMPILED_DIR"/"$CIRCUIT_NAME"_js/"$CIRCUIT_NAME".wasm $BLOCK_DIR/input.json \
    "$BUILD_DIR"/witness.wtns
end=`date +%s`
echo "DONE ($((end-start))s)"

if [ -f "$PHASE1" ]; then
    echo "Found Phase 1 ptau file"
else
    echo "No Phase 1 ptau file found. Exiting..."
    exit 1
fi

# Generates circuit-specific trusted setup if it doesn't exist.
# This step might take a while.
if test ! -f "$TRUSTED_SETUP_DIR/vkey.json"; then
    echo "****GENERATING ZKEY 0****"
    start=`date +%s`
    NODE_OPTIONS="--max-old-space-size=56000" yarn snarkjs groth16 setup "$COMPILED_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$TRUSTED_SETUP_DIR"/"$CIRCUIT_NAME"_0.zkey
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****GENERATING FINAL ZKEY****"
    start=`date +%s`
    NODE_OPTIONS="--max-old-space-size=56000" yarn snarkjs zkey beacon "$TRUSTED_SETUP_DIR"/"$CIRCUIT_NAME"_0.zkey "$TRUSTED_SETUP_DIR"/"$CIRCUIT_NAME".zkey 0102030405060708090a0b0c0d0e0f101112231415161718221a1b1c1d1e1f 10 -n="Final Beacon phase2"
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****VERIFYING FINAL ZKEY****"
    start=`date +%s`
    NODE_OPTIONS="--max-old-space-size=56000" yarn snarkjs zkey verify "$COMPILED_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$TRUSTED_SETUP_DIR"/"$CIRCUIT_NAME".zkey
    end=`date +%s`
    echo "DONE ($((end-start))s)"

    echo "****EXPORTING VKEY****"
    start=`date +%s`
    yarn snarkjs zkey export verificationkey "$TRUSTED_SETUP_DIR"/"$CIRCUIT_NAME".zkey "$TRUSTED_SETUP_DIR"/vkey.json
    end=`date +%s`
    echo "DONE ($((end-start))s)"
fi

echo "****GENERATING PROOF FOR SAMPLE INPUT****"
start=`date +%s`
yarn snarkjs groth16 prove "$TRUSTED_SETUP_DIR"/"$CIRCUIT_NAME".zkey "$BUILD_DIR"/witness.wtns "$BLOCK_DIR"/proof.json "$BLOCK_DIR"/public.json
end=`date +%s`
echo "DONE ($((end-start))s)"
 
# Bug in snarkjs. Error: Scalar size does not match. 
# Verifying via solidity contract works!
# echo "****VERIFYING PROOF FOR SAMPLE INPUT****"
# start=`date +%s`
# yarn snarkjs groth16 verify "$TRUSTED_SETUP_DIR"/vkey.json ./single_block_header_zkp/input.json "$BUILD_DIR"/proof.json
# end=`date +%s`
# echo "DONE ($((end-start))s)"

# Outputs calldata for the verifier contract.
echo "****GENERATING CALLDATA FOR VERIFIER CONTRACT****"
start=`date +%s`
snarkjs zkey export soliditycalldata $BLOCK_DIR/public.json "$BLOCK_DIR"/proof.json > "$BLOCK_DIR"/calldata.txt
end=`date +%s`
echo "DONE ($((end-start))s)"
