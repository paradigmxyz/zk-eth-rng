

// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

/**
 * @title Turbo Plonk proof verification contract
 * @dev Top level Plonk proof verification contract, which allows Plonk proof to be verified
 *
 * Copyright 2020 Spilsbury Holdings Ltd
 *
 * Licensed under the GNU General Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
contract TurboVerifier {
    using Bn254Crypto for Types.G1Point;
    using Bn254Crypto for Types.G2Point;
    using Transcript for Transcript.TranscriptData;

    /**
        Calldata formatting:

        0x00 - 0x04 : function signature
        0x04 - 0x24 : proof_data pointer (location in calldata that contains the proof_data array)
        0x44 - 0x64 : length of `proof_data` array
        0x64 - ???? : array containing our zk proof data
    **/
    /**
     * @dev Verify a Plonk proof
     * @param - array of serialized proof data
     */
    function verifyVDFProof(bytes calldata)
        public
        view
        returns (bool result)
    {

        Types.VerificationKey memory vk = get_verification_key();
        uint256 num_public_inputs = vk.num_inputs;

        // parse the input calldata and construct a Proof object
        Types.Proof memory decoded_proof = deserialize_proof(
            num_public_inputs,
            vk
        );

        Transcript.TranscriptData memory transcript;
        transcript.generate_initial_challenge(vk.circuit_size, vk.num_inputs);

        // reconstruct the beta, gamma, alpha and zeta challenges
        Types.ChallengeTranscript memory challenges;
        transcript.generate_beta_gamma_challenges(challenges, vk.num_inputs);
        transcript.generate_alpha_challenge(challenges, decoded_proof.Z);
        transcript.generate_zeta_challenge(
            challenges,
            decoded_proof.T1,
            decoded_proof.T2,
            decoded_proof.T3,
            decoded_proof.T4
        );

        /**
         * Compute all inverses that will be needed throughout the program here.
         *
         * This is an efficiency improvement - it allows us to make use of the batch inversion Montgomery trick,
         * which allows all inversions to be replaced with one inversion operation, at the expense of a few
         * additional multiplications
         **/
        (uint256 r_0, uint256 L1) = evalaute_field_operations(
            decoded_proof,
            vk,
            challenges
        );
        decoded_proof.r_0 = r_0;

        // reconstruct the nu and u challenges
        // Need to change nu and u according to the simplified Plonk
        transcript.generate_nu_challenges(challenges, vk.num_inputs);

        transcript.generate_separator_challenge(
            challenges,
            decoded_proof.PI_Z,
            decoded_proof.PI_Z_OMEGA
        );

        //reset 'alpha base'
        challenges.alpha_base = challenges.alpha;
        // Computes step 9 -> [D]_1
        Types.G1Point memory linearised_contribution = PolynomialEval
            .compute_linearised_opening_terms(
                challenges,
                L1,
                vk,
                decoded_proof
            );
        // Computes step 10 -> [F]_1
        Types.G1Point memory batch_opening_commitment = PolynomialEval
            .compute_batch_opening_commitment(
                challenges,
                vk,
                linearised_contribution,
                decoded_proof
            );

        uint256 batch_evaluation_g1_scalar = PolynomialEval
            .compute_batch_evaluation_scalar_multiplier(
                decoded_proof,
                challenges
            );

        result = perform_pairing(
            batch_opening_commitment,
            batch_evaluation_g1_scalar,
            challenges,
            decoded_proof,
            vk
        );
        require(result, "Proof failed");
    }

    
    function get_verification_key() internal pure returns (Types.VerificationKey memory) {
        Types.VerificationKey memory vk;

        assembly {
            mstore(add(vk, 0x00), 262144) // vk.circuit_size
            mstore(add(vk, 0x20), 64) // vk.num_inputs
            mstore(add(vk, 0x40),0x19ddbcaf3a8d46c15c0176fbb5b95e4dc57088ff13f4d1bd84c6bfa57dcdc0e0) // vk.work_root
            mstore(add(vk, 0x60),0x30644259cd94e7dd5045d7a27013b7fcd21c9e3b7fa75222e7bda49b729b0401) // vk.domain_inverse
            mstore(add(vk, 0x80),0x036853f083780e87f8d7c71d111119c57dbe118c22d5ad707a82317466c5174c) // vk.work_root_inverse
            mstore(mload(add(vk, 0xa0)), 0x0df87c1836c8442d4748d8f565dceaa78c366fa4f0cef59f91deb2f3e2b76855)//vk.Q1
            mstore(add(mload(add(vk, 0xa0)), 0x20), 0x13476c0c697c1f56be05586d5b359c1664373477f8a4dbe2a9e78d356fb49360)
            mstore(mload(add(vk, 0xc0)), 0x21dc73424a00c3247c6b60271fa45127c67b445c97fc13a0528cf2ab9a7a2c89)//vk.Q2
            mstore(add(mload(add(vk, 0xc0)), 0x20), 0x12df9b0fe039a67657fb79a2fbd4353fc4779e5f0c00a2950be306d339752861)
            mstore(mload(add(vk, 0xe0)), 0x226ceb14f59cf7163e232c645a9ef75073e9adb11ca5de55a2d2ec0d331fc0e2)//vk.Q3
            mstore(add(mload(add(vk, 0xe0)), 0x20), 0x16212438aff1fd2a255366fd4fae9b57028ada8b30130e29da2953032f25f5e9)
            mstore(mload(add(vk, 0x100)), 0x1d3974ff684ea76836b6c118d426438fa93cf4c6dca65bd41f89b356f35eb492)//vk.Q4
            mstore(add(mload(add(vk, 0x100)), 0x20), 0x0b247e14147f51e74d8f832a0181a79d33b0711c40ddb5ff19f90894e238f318)
            mstore(mload(add(vk, 0x120)), 0x25844f31d5eabd709b9c07091dc3bd303570d8bc3f3989ab62611d5bb5878f25)//vk.Q5
            mstore(add(mload(add(vk, 0x120)), 0x20), 0x0451f3eed8a6fe3cc644eb4373667c6ba8874e95b524131ccd5e1ae9ad69ab75)
            mstore(mload(add(vk, 0x140)), 0x2ff1d5e4940dbe92cebb02615904868e0c8ce3ae9ee17fa068a2d91097c70953)//vk.QM
            mstore(add(mload(add(vk, 0x140)), 0x20), 0x01557a24239b77f5432dffb3d61b5ff73ad8785fda6f21db5d85f3047e04b9e3)
            mstore(mload(add(vk, 0x160)), 0x007b1475aff77d5fac21b8b979a648bde908839c168c6d87c8804b768b4eb616)//vk.QC
            mstore(add(mload(add(vk, 0x160)), 0x20), 0x0a744eb10b6dfee8d36ed982231eff7a08c05deefba49466e8e1d202ec009112)
            mstore(mload(add(vk, 0x180)), 0x1afcfd9d4d1a3be34f75458f905ddac72bb64566608b3412b89b3f887c55926b)//vk.QARITH
            mstore(add(mload(add(vk, 0x180)), 0x20), 0x2731f2beed9989af99169c58c412fecdb30f6180f16cbc8f91469f835462a395)
            mstore(mload(add(vk, 0x1a0)), 0x10dda338df9d1b781b208e7cb5c2477c2994119e47e30f78ea45ae95dc386e33)//vk.QECC
            mstore(add(mload(add(vk, 0x1a0)), 0x20), 0x278cb8fca7ce878132b738b972fd06c726f95624ba075e3d27d4979f8fa00840)
            mstore(mload(add(vk, 0x1c0)), 0x134ac745c722a4536cf48ead5850c19e99d716f6e09f8f74c95874dc7d2143e1)//vk.QRANGE
            mstore(add(mload(add(vk, 0x1c0)), 0x20), 0x1c06e5b374c8a4452bee9e371083cc70db46405aae6cb920255186f835fe44c4)
            mstore(mload(add(vk, 0x1e0)), 0x2250e9bcb321fb86adf049b43bd79e9f9015150037792399b8e0b1d9eec54994)//vk.QLOGIC
            mstore(add(mload(add(vk, 0x1e0)), 0x20), 0x23e6e3333f96284cbef0ab931357ac149277cc38e861c66b2b6d73c900c6b5e7)
            mstore(mload(add(vk, 0x200)), 0x2df6906010901ec945c4f8f0c558408cf43139893a87ccf4e9f3840ddd150b6e)//vk.SIGMA1
            mstore(add(mload(add(vk, 0x200)), 0x20), 0x0db63d1b1c494019346cfce5bf4a0cd6afbd96f71e57366e8affd7ec218742b7)
            mstore(mload(add(vk, 0x220)), 0x13db41af89deb06b57eb6522d48eb12a9b89dab10a560023f3d0f1cbfb3371f3)//vk.SIGMA2
            mstore(add(mload(add(vk, 0x220)), 0x20), 0x1bf4cd59938aeda94061d00a4781c1f7b7bb0776f9ba00b25204714852cc35eb)
            mstore(mload(add(vk, 0x240)), 0x10b14ab323e6d092bd7363eb7d726818f29e5e40451e364fc991c0a9194c7345)//vk.SIGMA3
            mstore(add(mload(add(vk, 0x240)), 0x20), 0x021cd9b356903fdbf289e59cf97334c89750dd5541a9991b6230a6cf7bf69fd7)
            mstore(mload(add(vk, 0x260)), 0x0bb26826f4ab6f420f69432ae42d2ea88cfbd2e27f463f4068cc66dd69c99736)//vk.SIGMA4
            mstore(add(mload(add(vk, 0x260)), 0x20), 0x269dc2b3f51873c3d84fec183b7683d3c9e19c4575afa32d5a562e8fee393420)
            mstore(add(vk, 0x280), 0x00) // vk.contains_recursive_proof
            mstore(add(vk, 0x2a0), 0) // vk.recursive_proof_public_input_indices
            mstore(mload(add(vk, 0x2c0)), 0x260e01b251f6f1c7e7ff4e580791dee8ea51d87a358e038b4efe30fac09383c1) // vk.g2_x.X.c1
            mstore(add(mload(add(vk, 0x2c0)), 0x20), 0x0118c4d5b837bcc2bc89b5b398b5974e9f5944073b32078b7e231fec938883b0) // vk.g2_x.X.c0
            mstore(add(mload(add(vk, 0x2c0)), 0x40), 0x04fc6369f7110fe3d25156c1bb9a72859cf2a04641f99ba4ee413c80da6a5fe4) // vk.g2_x.Y.c1
            mstore(add(mload(add(vk, 0x2c0)), 0x60), 0x22febda3c0c0632a56475b4214e5615e11e6dd3f96e6cea2854a87d4dacc5e55) // vk.g2_x.Y.c0
        }
        return vk;
    }


    /**
     * @dev Compute partial state of the verifier, specifically: public input delta evaluation, zero polynomial
     * evaluation, the lagrange evaluations and the quotient polynomial evaluations
     *
     * Note: This uses the batch inversion Montgomery trick to reduce the number of
     * inversions, and therefore the number of calls to the bn128 modular exponentiation
     * precompile.
     *
     * Specifically, each function call: compute_public_input_delta() etc. at some point needs to invert a
     * value to calculate a denominator in a fraction. Instead of performing this inversion as it is needed, we
     * instead 'save up' the denominator calculations. The inputs to this are returned from the various functions
     * and then we perform all necessary inversions in one go at the end of `evalaute_field_operations()`. This
     * gives us the various variables that need to be returned.
     *
     * @param decoded_proof - deserialised proof
     * @param vk - verification key
     * @param challenges - all challenges (alpha, beta, gamma, zeta, nu[NUM_NU_CHALLENGES], u) stored in
     * ChallengeTranscript struct form
     * @return quotient polynomial evaluation (field element) and lagrange 1 evaluation (field element)
     */
    function evalaute_field_operations(
        Types.Proof memory decoded_proof,
        Types.VerificationKey memory vk,
        Types.ChallengeTranscript memory challenges
    ) internal view returns (uint256, uint256) {
        uint256 public_input_delta;
        uint256 zero_polynomial_eval;
        uint256 l_start;
        uint256 l_end;
        {
            (
                uint256 public_input_numerator,
                uint256 public_input_denominator
            ) = PolynomialEval.compute_public_input_delta(challenges, vk);

            (
                uint256 vanishing_numerator,
                uint256 vanishing_denominator,
                uint256 lagrange_numerator,
                uint256 l_start_denominator,
                uint256 l_end_denominator
            ) = PolynomialEval.compute_lagrange_and_vanishing_fractions(
                    vk,
                    challenges.zeta
                );

            (
                zero_polynomial_eval,
                public_input_delta,
                l_start,
                l_end
            ) = PolynomialEval.compute_batch_inversions(
                public_input_numerator,
                public_input_denominator,
                vanishing_numerator,
                vanishing_denominator,
                lagrange_numerator,
                l_start_denominator,
                l_end_denominator
            );
            vk.zero_polynomial_eval = zero_polynomial_eval;
        }

        uint256 r_0 = PolynomialEval.compute_linear_polynomial_constant(
            zero_polynomial_eval,
            public_input_delta,
            challenges,
            l_start,
            l_end,
            decoded_proof
        );

        return (r_0, l_start);
    }

    /**
     * @dev Perform the pairing check
     * @param batch_opening_commitment - G1 point representing the calculated batch opening commitment
     * @param batch_evaluation_g1_scalar - uint256 representing the batch evaluation scalar multiplier to be applied to the G1 generator point
     * @param challenges - all challenges (alpha, beta, gamma, zeta, nu[NUM_NU_CHALLENGES], u) stored in
     * ChallengeTranscript struct form
     * @param vk - verification key
     * @param decoded_proof - deserialised proof
     * @return bool specifying whether the pairing check was successful
     */
    function perform_pairing(
        Types.G1Point memory batch_opening_commitment,
        uint256 batch_evaluation_g1_scalar,
        Types.ChallengeTranscript memory challenges,
        Types.Proof memory decoded_proof,
        Types.VerificationKey memory vk
    ) internal view returns (bool) {
        uint256 u = challenges.u;
        bool success;
        uint256 p = Bn254Crypto.r_mod;
        Types.G1Point memory rhs;
        Types.G1Point memory PI_Z_OMEGA = decoded_proof.PI_Z_OMEGA;
        Types.G1Point memory PI_Z = decoded_proof.PI_Z;
        PI_Z.validateG1Point();
        PI_Z_OMEGA.validateG1Point();

        // rhs = zeta.[PI_Z] + u.zeta.omega.[PI_Z_OMEGA] + [batch_opening_commitment] - batch_evaluation_g1_scalar.[1]
        // scope this block to prevent stack depth errors
        {
            uint256 zeta = challenges.zeta;
            uint256 pi_z_omega_scalar = vk.work_root;
            assembly {
                pi_z_omega_scalar := mulmod(pi_z_omega_scalar, zeta, p)
                pi_z_omega_scalar := mulmod(pi_z_omega_scalar, u, p)
                batch_evaluation_g1_scalar := sub(p, batch_evaluation_g1_scalar)

                // store accumulator point at mptr
                let mPtr := mload(0x40)

                // set accumulator = batch_opening_commitment
                mstore(mPtr, mload(batch_opening_commitment))
                mstore(
                    add(mPtr, 0x20),
                    mload(add(batch_opening_commitment, 0x20))
                )

                // compute zeta.[PI_Z] and add into accumulator
                mstore(add(mPtr, 0x40), mload(PI_Z))
                mstore(add(mPtr, 0x60), mload(add(PI_Z, 0x20)))
                mstore(add(mPtr, 0x80), zeta)
                success := staticcall(
                    gas(),
                    7,
                    add(mPtr, 0x40),
                    0x60,
                    add(mPtr, 0x40),
                    0x40
                )
                success := and(
                    success,
                    staticcall(gas(), 6, mPtr, 0x80, mPtr, 0x40)
                )

                // compute u.zeta.omega.[PI_Z_OMEGA] and add into accumulator
                mstore(add(mPtr, 0x40), mload(PI_Z_OMEGA))
                mstore(add(mPtr, 0x60), mload(add(PI_Z_OMEGA, 0x20)))
                mstore(add(mPtr, 0x80), pi_z_omega_scalar)
                success := and(
                    success,
                    staticcall(
                        gas(),
                        7,
                        add(mPtr, 0x40),
                        0x60,
                        add(mPtr, 0x40),
                        0x40
                    )
                )
                success := and(
                    success,
                    staticcall(gas(), 6, mPtr, 0x80, mPtr, 0x40)
                )

                // compute -batch_evaluation_g1_scalar.[1]
                mstore(add(mPtr, 0x40), 0x01) // hardcoded generator point (1, 2)
                mstore(add(mPtr, 0x60), 0x02)
                mstore(add(mPtr, 0x80), batch_evaluation_g1_scalar)
                success := and(
                    success,
                    staticcall(
                        gas(),
                        7,
                        add(mPtr, 0x40),
                        0x60,
                        add(mPtr, 0x40),
                        0x40
                    )
                )

                // add -batch_evaluation_g1_scalar.[1] and the accumulator point, write result into rhs
                success := and(
                    success,
                    staticcall(gas(), 6, mPtr, 0x80, rhs, 0x40)
                )
            }
        }

        Types.G1Point memory lhs;
        assembly {
            // store accumulator point at mptr
            let mPtr := mload(0x40)

            // copy [PI_Z] into mPtr
            mstore(mPtr, mload(PI_Z))
            mstore(add(mPtr, 0x20), mload(add(PI_Z, 0x20)))

            // compute u.[PI_Z_OMEGA] and write to (mPtr + 0x40)
            mstore(add(mPtr, 0x40), mload(PI_Z_OMEGA))
            mstore(add(mPtr, 0x60), mload(add(PI_Z_OMEGA, 0x20)))
            mstore(add(mPtr, 0x80), u)
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(mPtr, 0x40),
                    0x60,
                    add(mPtr, 0x40),
                    0x40
                )
            )

            // add [PI_Z] + u.[PI_Z_OMEGA] and write result into lhs
            success := and(success, staticcall(gas(), 6, mPtr, 0x80, lhs, 0x40))
        }

        // negate lhs y-coordinate
        uint256 q = Bn254Crypto.p_mod;
        assembly {
            mstore(add(lhs, 0x20), sub(q, mload(add(lhs, 0x20))))
        }

        if (vk.contains_recursive_proof) {
            // If the proof itself contains an accumulated proof,
            // we will have extracted two G1 elements `recursive_P1`, `recursive_p2` from the public inputs

            // We need to evaluate that e(recursive_P1, [x]_2) == e(recursive_P2, [1]_2) to finish verifying the inner proof
            // We do this by creating a random linear combination between (lhs, recursive_P1) and (rhs, recursivee_P2)
            // That way we still only need to evaluate one pairing product

            // We use `challenge.u * challenge.u` as the randomness to create a linear combination
            // challenge.u is produced by hashing the entire transcript, which contains the public inputs (and by extension the recursive proof)

            // i.e. [lhs] = [lhs] + u.u.[recursive_P1]
            //      [rhs] = [rhs] + u.u.[recursive_P2]
            Types.G1Point memory recursive_P1 = decoded_proof.recursive_P1;
            Types.G1Point memory recursive_P2 = decoded_proof.recursive_P2;
            recursive_P1.validateG1Point();
            recursive_P2.validateG1Point();
            assembly {
                let mPtr := mload(0x40)

                // compute u.u.[recursive_P1]
                mstore(mPtr, mload(recursive_P1))
                mstore(add(mPtr, 0x20), mload(add(recursive_P1, 0x20)))
                mstore(add(mPtr, 0x40), mulmod(u, u, p)) // separator_challenge = u * u
                success := and(
                    success,
                    staticcall(gas(), 7, mPtr, 0x60, add(mPtr, 0x60), 0x40)
                )

                // compute u.u.[recursive_P2] (u*u is still in memory at (mPtr + 0x40), no need to re-write it)
                mstore(mPtr, mload(recursive_P2))
                mstore(add(mPtr, 0x20), mload(add(recursive_P2, 0x20)))
                success := and(
                    success,
                    staticcall(gas(), 7, mPtr, 0x60, mPtr, 0x40)
                )

                // compute u.u.[recursiveP2] + rhs and write into rhs
                mstore(add(mPtr, 0xa0), mload(rhs))
                mstore(add(mPtr, 0xc0), mload(add(rhs, 0x20)))
                success := and(
                    success,
                    staticcall(gas(), 6, add(mPtr, 0x60), 0x80, rhs, 0x40)
                )

                // compute u.u.[recursiveP1] + lhs and write into lhs
                mstore(add(mPtr, 0x40), mload(lhs))
                mstore(add(mPtr, 0x60), mload(add(lhs, 0x20)))
                success := and(
                    success,
                    staticcall(gas(), 6, mPtr, 0x80, lhs, 0x40)
                )
            }
        }

        require(success, "perform_pairing G1 operations preamble fail");

        return Bn254Crypto.pairingProd2(rhs, Bn254Crypto.P2(), lhs, vk.g2_x);
    }

    /**
     * @dev Deserialize a proof into a Proof struct
     * @param num_public_inputs - number of public inputs in the proof. Taken from verification key
     * @return proof - proof deserialized into the proof struct
     */
    function deserialize_proof(
        uint256 num_public_inputs,
        Types.VerificationKey memory vk
    ) internal pure returns (Types.Proof memory proof) {
        uint256 p = Bn254Crypto.r_mod;
        uint256 q = Bn254Crypto.p_mod;
        uint256 data_ptr;
        uint256 proof_ptr;
        // first 32 bytes of bytes array contains length, skip it
        assembly {
            data_ptr := add(calldataload(0x04), 0x24)
            proof_ptr := proof
        }

        if (vk.contains_recursive_proof) {
            uint256 index_counter = vk.recursive_proof_indices * 32;
            uint256 x0 = 0;
            uint256 y0 = 0;
            uint256 x1 = 0;
            uint256 y1 = 0;
            assembly {
                index_counter := add(index_counter, data_ptr)
                x0 := calldataload(index_counter)
                x0 := add(x0, shl(68, calldataload(add(index_counter, 0x20))))
                x0 := add(x0, shl(136, calldataload(add(index_counter, 0x40))))
                x0 := add(x0, shl(204, calldataload(add(index_counter, 0x60))))
                y0 := calldataload(add(index_counter, 0x80))
                y0 := add(y0, shl(68, calldataload(add(index_counter, 0xa0))))
                y0 := add(y0, shl(136, calldataload(add(index_counter, 0xc0))))
                y0 := add(y0, shl(204, calldataload(add(index_counter, 0xe0))))
                x1 := calldataload(add(index_counter, 0x100))
                x1 := add(x1, shl(68, calldataload(add(index_counter, 0x120))))
                x1 := add(x1, shl(136, calldataload(add(index_counter, 0x140))))
                x1 := add(x1, shl(204, calldataload(add(index_counter, 0x160))))
                y1 := calldataload(add(index_counter, 0x180))
                y1 := add(y1, shl(68, calldataload(add(index_counter, 0x1a0))))
                y1 := add(y1, shl(136, calldataload(add(index_counter, 0x1c0))))
                y1 := add(y1, shl(204, calldataload(add(index_counter, 0x1e0))))
            }

            proof.recursive_P1 = Bn254Crypto.new_g1(x0, y0);
            proof.recursive_P2 = Bn254Crypto.new_g1(x1, y1);
        }

        assembly {
            let public_input_byte_length := mul(num_public_inputs, 0x20)
            data_ptr := add(data_ptr, public_input_byte_length)

            // proof.W1
            mstore(mload(proof_ptr), mod(calldataload(add(data_ptr, 0x20)), q))
            mstore(add(mload(proof_ptr), 0x20), mod(calldataload(data_ptr), q))

            // proof.W2
            mstore(
                mload(add(proof_ptr, 0x20)),
                mod(calldataload(add(data_ptr, 0x60)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0x20)), 0x20),
                mod(calldataload(add(data_ptr, 0x40)), q)
            )

            // proof.W3
            mstore(
                mload(add(proof_ptr, 0x40)),
                mod(calldataload(add(data_ptr, 0xa0)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0x40)), 0x20),
                mod(calldataload(add(data_ptr, 0x80)), q)
            )

            // proof.W4
            mstore(
                mload(add(proof_ptr, 0x60)),
                mod(calldataload(add(data_ptr, 0xe0)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0x60)), 0x20),
                mod(calldataload(add(data_ptr, 0xc0)), q)
            )

            // proof.Z
            mstore(
                mload(add(proof_ptr, 0x80)),
                mod(calldataload(add(data_ptr, 0x120)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0x80)), 0x20),
                mod(calldataload(add(data_ptr, 0x100)), q)
            )

            // proof.T1
            mstore(
                mload(add(proof_ptr, 0xa0)),
                mod(calldataload(add(data_ptr, 0x160)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0xa0)), 0x20),
                mod(calldataload(add(data_ptr, 0x140)), q)
            )

            // proof.T2
            mstore(
                mload(add(proof_ptr, 0xc0)),
                mod(calldataload(add(data_ptr, 0x1a0)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0xc0)), 0x20),
                mod(calldataload(add(data_ptr, 0x180)), q)
            )

            // proof.T3
            mstore(
                mload(add(proof_ptr, 0xe0)),
                mod(calldataload(add(data_ptr, 0x1e0)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0xe0)), 0x20),
                mod(calldataload(add(data_ptr, 0x1c0)), q)
            )

            // proof.T4
            mstore(
                mload(add(proof_ptr, 0x100)),
                mod(calldataload(add(data_ptr, 0x220)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0x100)), 0x20),
                mod(calldataload(add(data_ptr, 0x200)), q)
            )

            // proof.w1 to proof.w4
            mstore(
                add(proof_ptr, 0x120),
                mod(calldataload(add(data_ptr, 0x240)), p)
            )
            mstore(
                add(proof_ptr, 0x140),
                mod(calldataload(add(data_ptr, 0x260)), p)
            )
            mstore(
                add(proof_ptr, 0x160),
                mod(calldataload(add(data_ptr, 0x280)), p)
            )
            mstore(
                add(proof_ptr, 0x180),
                mod(calldataload(add(data_ptr, 0x2a0)), p)
            )

            // proof.sigma1
            mstore(
                add(proof_ptr, 0x1a0),
                mod(calldataload(add(data_ptr, 0x2c0)), p)
            )

            // proof.sigma2
            mstore(
                add(proof_ptr, 0x1c0),
                mod(calldataload(add(data_ptr, 0x2e0)), p)
            )

            // proof.sigma3
            mstore(
                add(proof_ptr, 0x1e0),
                mod(calldataload(add(data_ptr, 0x300)), p)
            )

            // proof.q_arith
            mstore(
                add(proof_ptr, 0x200),
                mod(calldataload(add(data_ptr, 0x320)), p)
            )

            // proof.q_ecc
            mstore(
                add(proof_ptr, 0x220),
                mod(calldataload(add(data_ptr, 0x340)), p)
            )

            // proof.q_c
            mstore(
                add(proof_ptr, 0x240),
                mod(calldataload(add(data_ptr, 0x360)), p)
            )

            // proof.linearization_polynomial
            // mstore(add(proof_ptr, 0x260), mod(calldataload(add(data_ptr, 0x380)), p))

            // proof.grand_product_at_z_omega
            mstore(
                add(proof_ptr, 0x260),
                mod(calldataload(add(data_ptr, 0x380)), p)
            )

            // proof.w1_omega to proof.w4_omega
            mstore(
                add(proof_ptr, 0x280),
                mod(calldataload(add(data_ptr, 0x3a0)), p)
            )
            mstore(
                add(proof_ptr, 0x2a0),
                mod(calldataload(add(data_ptr, 0x3c0)), p)
            )
            mstore(
                add(proof_ptr, 0x2c0),
                mod(calldataload(add(data_ptr, 0x3e0)), p)
            )
            mstore(
                add(proof_ptr, 0x2e0),
                mod(calldataload(add(data_ptr, 0x400)), p)
            )

            // proof.PI_Z
            //Order of x and y coordinate are reverse in case of serialization
            mstore(
                mload(add(proof_ptr, 0x300)),
                mod(calldataload(add(data_ptr, 0x440)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0x300)), 0x20),
                mod(calldataload(add(data_ptr, 0x420)), q)
            )

            // proof.PI_Z_OMEGA
            mstore(
                mload(add(proof_ptr, 0x320)),
                mod(calldataload(add(data_ptr, 0x480)), q)
            )
            mstore(
                add(mload(add(proof_ptr, 0x320)), 0x20),
                mod(calldataload(add(data_ptr, 0x460)), q)
            )
        }
    }
}





/**
 * @title Bn254Crypto library used for the fr, g1 and g2 point types
 * @dev Used to manipulate fr, g1, g2 types, perform modular arithmetic on them and call
 * the precompiles add, scalar mul and pairing
 *
 * Notes on optimisations
 * 1) Perform addmod, mulmod etc. in assembly - removes the check that Solidity performs to confirm that
 * the supplied modulus is not 0. This is safe as the modulus's used (r_mod, q_mod) are hard coded
 * inside the contract and not supplied by the user
 */
library Types {
    uint256 constant PROGRAM_WIDTH = 4;
    uint256 constant NUM_NU_CHALLENGES = 11;

    uint256 constant coset_generator0 =
        0x0000000000000000000000000000000000000000000000000000000000000005;
    uint256 constant coset_generator1 =
        0x0000000000000000000000000000000000000000000000000000000000000006;
    uint256 constant coset_generator2 =
        0x0000000000000000000000000000000000000000000000000000000000000007;

    // TODO: add external_coset_generator() method to compute this
    uint256 constant coset_generator7 =
        0x000000000000000000000000000000000000000000000000000000000000000c;

    struct G1Point {
        uint256 x;
        uint256 y;
    }

    // G2 group element where x \in Fq2 = x0 * z + x1
    struct G2Point {
        uint256 x0;
        uint256 x1;
        uint256 y0;
        uint256 y1;
    }

    // N>B. Do not re-order these fields! They must appear in the same order as they
    // appear in the proof data
    struct Proof {
        G1Point W1;
        G1Point W2;
        G1Point W3;
        G1Point W4;
        G1Point Z;
        G1Point T1;
        G1Point T2;
        G1Point T3;
        G1Point T4;
        uint256 w1;
        uint256 w2;
        uint256 w3;
        uint256 w4;
        uint256 sigma1;
        uint256 sigma2;
        uint256 sigma3;
        uint256 q_arith;
        uint256 q_ecc;
        uint256 q_c;
        // uint256 linearization_polynomial;
        uint256 grand_product_at_z_omega;
        uint256 w1_omega;
        uint256 w2_omega;
        uint256 w3_omega;
        uint256 w4_omega;
        G1Point PI_Z;
        G1Point PI_Z_OMEGA;
        G1Point recursive_P1;
        G1Point recursive_P2;
        //    uint256 quotient_polynomial_eval;
        uint256 r_0;
    }

    struct ChallengeTranscript {
        uint256 alpha_base;
        uint256 alpha;
        uint256 zeta;
        uint256 beta;
        uint256 gamma;
        uint256 u;
        uint256 v0;
        uint256 v1;
        uint256 v2;
        uint256 v3;
        uint256 v4;
        uint256 v5;
        uint256 v6;
        uint256 v7;
        uint256 v8;
        uint256 v9;
        uint256 v10;
    }

    struct VerificationKey {
        uint256 circuit_size;
        uint256 num_inputs;
        uint256 work_root;
        uint256 domain_inverse;
        uint256 work_root_inverse;
        G1Point Q1;
        G1Point Q2;
        G1Point Q3;
        G1Point Q4;
        G1Point Q5;
        G1Point QM;
        G1Point QC;
        G1Point QARITH;
        G1Point QECC;
        G1Point QRANGE;
        G1Point QLOGIC;
        G1Point SIGMA1;
        G1Point SIGMA2;
        G1Point SIGMA3;
        G1Point SIGMA4;
        bool contains_recursive_proof;
        uint256 recursive_proof_indices;
        G2Point g2_x;
        // zeta challenge raised to the power of the circuit size.
        // Not actually part of the verification key, but we put it here to prevent stack depth errors
        uint256 zeta_pow_n;
        // necessary fot the simplified plonk
        uint256 zero_polynomial_eval;
    }
}


    
    


/**
 * @title Bn254 elliptic curve crypto
 * @dev Provides some basic methods to compute bilinear pairings, construct group elements and misc numerical methods
 */
library Bn254Crypto {
    uint256 constant p_mod =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint256 constant r_mod =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    // Perform a modular exponentiation. This method is ideal for small exponents (~64 bits or less), as
    // it is cheaper than using the pow precompile
    function pow_small(
        uint256 base,
        uint256 exponent,
        uint256 modulus
    ) internal pure returns (uint256) {
        uint256 result = 1;
        uint256 input = base;
        uint256 count = 1;

        assembly {
            let endpoint := add(exponent, 0x01)
            for {

            } lt(count, endpoint) {
                count := add(count, count)
            } {
                if and(exponent, count) {
                    result := mulmod(result, input, modulus)
                }
                input := mulmod(input, input, modulus)
            }
        }

        return result;
    }

    function invert(uint256 fr) internal view returns (uint256) {
        uint256 output;
        bool success;
        uint256 p = r_mod;
        assembly {
            let mPtr := mload(0x40)
            mstore(mPtr, 0x20)
            mstore(add(mPtr, 0x20), 0x20)
            mstore(add(mPtr, 0x40), 0x20)
            mstore(add(mPtr, 0x60), fr)
            mstore(add(mPtr, 0x80), sub(p, 2))
            mstore(add(mPtr, 0xa0), p)
            success := staticcall(gas(), 0x05, mPtr, 0xc0, 0x00, 0x20)
            output := mload(0x00)
        }
        require(success, "pow precompile call failed!");
        return output;
    }

    function new_g1(uint256 x, uint256 y)
        internal
        pure
        returns (Types.G1Point memory)
    {
        uint256 xValue;
        uint256 yValue;
        assembly {
            xValue := mod(x, r_mod)
            yValue := mod(y, r_mod)
        }
        return Types.G1Point(xValue, yValue);
    }

    function new_g2(
        uint256 x0,
        uint256 x1,
        uint256 y0,
        uint256 y1
    ) internal pure returns (Types.G2Point memory) {
        return Types.G2Point(x0, x1, y0, y1);
    }

    function P1() internal pure returns (Types.G1Point memory) {
        return Types.G1Point(1, 2);
    }

    function P2() internal pure returns (Types.G2Point memory) {
        return
            Types.G2Point({
                x0: 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2,
                x1: 0x1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed,
                y0: 0x090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b,
                y1: 0x12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa
            });
    }

    /// Evaluate the following pairing product:
    /// e(a1, a2).e(-b1, b2) == 1
    function pairingProd2(
        Types.G1Point memory a1,
        Types.G2Point memory a2,
        Types.G1Point memory b1,
        Types.G2Point memory b2
    ) internal view returns (bool) {
        validateG1Point(a1);
        validateG1Point(b1);
        bool success;
        uint256 out;
        assembly {
            let mPtr := mload(0x40)
            mstore(mPtr, mload(a1))
            mstore(add(mPtr, 0x20), mload(add(a1, 0x20)))
            mstore(add(mPtr, 0x40), mload(a2))
            mstore(add(mPtr, 0x60), mload(add(a2, 0x20)))
            mstore(add(mPtr, 0x80), mload(add(a2, 0x40)))
            mstore(add(mPtr, 0xa0), mload(add(a2, 0x60)))

            mstore(add(mPtr, 0xc0), mload(b1))
            mstore(add(mPtr, 0xe0), mload(add(b1, 0x20)))
            mstore(add(mPtr, 0x100), mload(b2))
            mstore(add(mPtr, 0x120), mload(add(b2, 0x20)))
            mstore(add(mPtr, 0x140), mload(add(b2, 0x40)))
            mstore(add(mPtr, 0x160), mload(add(b2, 0x60)))
            success := staticcall(gas(), 8, mPtr, 0x180, 0x00, 0x20)
            out := mload(0x00)
        }
        require(success, "Pairing check failed!");
        return (out != 0);
    }

    /**
     * validate the following:
     *   x != 0
     *   y != 0
     *   x < p
     *   y < p
     *   y^2 = x^3 + 3 mod p
     */
    function validateG1Point(Types.G1Point memory point) internal pure {
        bool is_well_formed;
        uint256 p = p_mod;
        assembly {
            let x := mload(point)
            let y := mload(add(point, 0x20))

            is_well_formed := and(
                and(and(lt(x, p), lt(y, p)), not(or(iszero(x), iszero(y)))),
                eq(mulmod(y, y, p), addmod(mulmod(x, mulmod(x, x, p), p), 3, p))
            )
        }
        require(
            is_well_formed,
            "Bn254: G1 point not on curve, or is malformed"
        );
    }
}

    


/**
 * @title Turbo Plonk polynomial evaluation
 * @dev Implementation of Turbo Plonk's polynomial evaluation algorithms
 *
 * Expected to be inherited by `TurboPlonk.sol`
 *
 * Copyright 2020 Spilsbury Holdings Ltd
 *
 * Licensed under the GNU General Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
library PolynomialEval {
    using Bn254Crypto for Types.G1Point;
    using Bn254Crypto for Types.G2Point;

    /**
     * @dev Use batch inversion (so called Montgomery's trick). Circuit size is the domain
     * Allows multiple inversions to be performed in one inversion, at the expense of additional multiplications
     *
     * Returns a struct containing the inverted elements
     */
    function compute_batch_inversions(
        uint256 public_input_delta_numerator,
        uint256 public_input_delta_denominator,
        uint256 vanishing_numerator,
        uint256 vanishing_denominator,
        uint256 lagrange_numerator,
        uint256 l_start_denominator,
        uint256 l_end_denominator
    )
        internal
        view
        returns (
            uint256 zero_polynomial_eval,
            uint256 public_input_delta,
            uint256 l_start,
            uint256 l_end
        )
    {
        uint256 mPtr;
        uint256 p = Bn254Crypto.r_mod;
        uint256 accumulator = 1;
        assembly {
            mPtr := mload(0x40)
            mstore(0x40, add(mPtr, 0x200))
        }

        // store denominators in mPtr -> mPtr + 0x80
        assembly {
            mstore(mPtr, public_input_delta_denominator) // store denominator
            mstore(add(mPtr, 0x20), vanishing_denominator) // store denominator
            mstore(add(mPtr, 0x40), l_start_denominator) // store denominator
            mstore(add(mPtr, 0x60), l_end_denominator) // store denominator

            // store temporary product terms at mPtr + 0x80 -> mPtr + 0x100
            mstore(add(mPtr, 0x80), accumulator)
            accumulator := mulmod(accumulator, mload(mPtr), p)
            mstore(add(mPtr, 0xa0), accumulator)
            accumulator := mulmod(accumulator, mload(add(mPtr, 0x20)), p)
            mstore(add(mPtr, 0xc0), accumulator)
            accumulator := mulmod(accumulator, mload(add(mPtr, 0x40)), p)
            mstore(add(mPtr, 0xe0), accumulator)
            accumulator := mulmod(accumulator, mload(add(mPtr, 0x60)), p)
        }

        accumulator = Bn254Crypto.invert(accumulator);
        assembly {
            let intermediate := mulmod(accumulator, mload(add(mPtr, 0xe0)), p)
            accumulator := mulmod(accumulator, mload(add(mPtr, 0x60)), p)
            mstore(add(mPtr, 0x60), intermediate)

            intermediate := mulmod(accumulator, mload(add(mPtr, 0xc0)), p)
            accumulator := mulmod(accumulator, mload(add(mPtr, 0x40)), p)
            mstore(add(mPtr, 0x40), intermediate)

            intermediate := mulmod(accumulator, mload(add(mPtr, 0xa0)), p)
            accumulator := mulmod(accumulator, mload(add(mPtr, 0x20)), p)
            mstore(add(mPtr, 0x20), intermediate)

            intermediate := mulmod(accumulator, mload(add(mPtr, 0x80)), p)
            accumulator := mulmod(accumulator, mload(mPtr), p)
            mstore(mPtr, intermediate)

            public_input_delta := mulmod(
                public_input_delta_numerator,
                mload(mPtr),
                p
            )

            zero_polynomial_eval := mulmod(
                vanishing_numerator,
                mload(add(mPtr, 0x20)),
                p
            )

            l_start := mulmod(lagrange_numerator, mload(add(mPtr, 0x40)), p)

            l_end := mulmod(lagrange_numerator, mload(add(mPtr, 0x60)), p)
        }
    }

    function compute_public_input_delta(
        Types.ChallengeTranscript memory challenges,
        Types.VerificationKey memory vk
    ) internal pure returns (uint256, uint256) {
        uint256 gamma = challenges.gamma;
        uint256 work_root = vk.work_root;

        uint256 endpoint = (vk.num_inputs * 0x20) - 0x20;
        uint256 public_inputs;
        uint256 root_1 = challenges.beta;
        uint256 root_2 = challenges.beta;
        uint256 numerator_value = 1;
        uint256 denominator_value = 1;

        // we multiply length by 0x20 because our loop step size is 0x20 not 0x01
        // we subtract 0x20 because our loop is unrolled 2 times an we don't want to overshoot

        // perform this computation in assembly to improve efficiency. We are sensitive to the cost of this loop as
        // it scales with the number of public inputs
        uint256 p = Bn254Crypto.r_mod;
        bool valid = true;
        assembly {
            root_1 := mulmod(root_1, 0x05, p)
            root_2 := mulmod(root_2, 0x07, p)
            public_inputs := add(calldataload(0x04), 0x24)

            // get public inputs from calldata. N.B. If Contract ABI Changes this code will need to be updated!
            endpoint := add(endpoint, public_inputs)
            // Do some loop unrolling to reduce number of conditional jump operations
            for {

            } lt(public_inputs, endpoint) {

            } {
                let input0 := calldataload(public_inputs)
                let N0 := add(root_1, add(input0, gamma))
                let D0 := add(root_2, N0) // 4x overloaded

                root_1 := mulmod(root_1, work_root, p)
                root_2 := mulmod(root_2, work_root, p)

                let input1 := calldataload(add(public_inputs, 0x20))
                let N1 := add(root_1, add(input1, gamma))

                denominator_value := mulmod(
                    mulmod(D0, denominator_value, p),
                    add(N1, root_2),
                    p
                )
                numerator_value := mulmod(mulmod(N1, N0, p), numerator_value, p)

                root_1 := mulmod(root_1, work_root, p)
                root_2 := mulmod(root_2, work_root, p)

                valid := and(valid, and(lt(input0, p), lt(input1, p)))
                public_inputs := add(public_inputs, 0x40)
            }

            endpoint := add(endpoint, 0x20)
            for {

            } lt(public_inputs, endpoint) {
                public_inputs := add(public_inputs, 0x20)
            } {
                let input0 := calldataload(public_inputs)
                valid := and(valid, lt(input0, p))
                let T0 := addmod(input0, gamma, p)
                numerator_value := mulmod(
                    numerator_value,
                    add(root_1, T0), // 0x05 = coset_generator0
                    p
                )
                denominator_value := mulmod(
                    denominator_value,
                    add(add(root_1, root_2), T0), // 0x0c = coset_generator7
                    p
                )
                root_1 := mulmod(root_1, work_root, p)
                root_2 := mulmod(root_2, work_root, p)
            }
        }
        require(valid, "public inputs are greater than circuit modulus");
        return (numerator_value, denominator_value);
    }

    /**
     * @dev Computes the vanishing polynoimal and lagrange evaluations L1 and Ln.
     * @return Returns fractions as numerators and denominators. We combine with the public input fraction and compute inverses as a batch
     */
    function compute_lagrange_and_vanishing_fractions(
        Types.VerificationKey memory vk,
        uint256 zeta
    )
        internal
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 p = Bn254Crypto.r_mod;
        uint256 vanishing_numerator = Bn254Crypto.pow_small(
            zeta,
            vk.circuit_size,
            p
        );
        vk.zeta_pow_n = vanishing_numerator;
        assembly {
            vanishing_numerator := addmod(vanishing_numerator, sub(p, 1), p)
        }

        uint256 accumulating_root = vk.work_root_inverse;
        uint256 work_root = vk.work_root_inverse;
        uint256 vanishing_denominator;
        uint256 domain_inverse = vk.domain_inverse;
        uint256 l_start_denominator;
        uint256 l_end_denominator;
        uint256 z = zeta; // copy input var to prevent stack depth errors
        assembly {
            // vanishing_denominator = (z - w^{n-1})(z - w^{n-2})(z - w^{n-3})(z - w^{n-4})
            // we need to cut 4 roots of unity out of the vanishing poly, the last 4 constraints are not satisfied due to randomness
            // added to ensure the proving system is zero-knowledge
            vanishing_denominator := addmod(z, sub(p, work_root), p)
            work_root := mulmod(work_root, accumulating_root, p)
            vanishing_denominator := mulmod(
                vanishing_denominator,
                addmod(z, sub(p, work_root), p),
                p
            )
            work_root := mulmod(work_root, accumulating_root, p)
            vanishing_denominator := mulmod(
                vanishing_denominator,
                addmod(z, sub(p, work_root), p),
                p
            )
            work_root := mulmod(work_root, accumulating_root, p)
            vanishing_denominator := mulmod(
                vanishing_denominator,
                addmod(z, sub(p, work_root), p),
                p
            )
        }

        work_root = vk.work_root;
        uint256 lagrange_numerator;
        assembly {
            lagrange_numerator := mulmod(vanishing_numerator, domain_inverse, p)
            // l_start_denominator = z - 1
            // l_end_denominator = z * \omega^5 - 1
            l_start_denominator := addmod(z, sub(p, 1), p)

            accumulating_root := mulmod(work_root, work_root, p)
            accumulating_root := mulmod(accumulating_root, accumulating_root, p)
            accumulating_root := mulmod(accumulating_root, work_root, p)

            l_end_denominator := addmod(
                mulmod(accumulating_root, z, p),
                sub(p, 1),
                p
            )
        }

        return (
            vanishing_numerator,
            vanishing_denominator,
            lagrange_numerator,
            l_start_denominator,
            l_end_denominator
        );
    }

    function compute_arithmetic_gate_quotient_contribution(
        Types.ChallengeTranscript memory challenges,
        Types.Proof memory proof
    ) internal view returns (uint256) {
        uint256 q_arith = proof.q_arith;
        uint256 wire3 = proof.w3;
        uint256 wire4 = proof.w4;
        uint256 alpha_base = challenges.alpha_base;
        uint256 alpha = challenges.alpha;
        uint256 t1;
        uint256 p = Bn254Crypto.r_mod;
        assembly {
            t1 := addmod(mulmod(q_arith, q_arith, p), sub(p, q_arith), p)

            let t2 := addmod(sub(p, mulmod(wire4, 0x04, p)), wire3, p)

            let t3 := mulmod(mulmod(t2, t2, p), 0x02, p)

            let t4 := mulmod(t2, 0x09, p)
            t4 := addmod(t4, addmod(sub(p, t3), sub(p, 0x07), p), p)

            t2 := mulmod(t2, t4, p)

            t1 := mulmod(mulmod(t1, t2, p), alpha_base, p)

            alpha_base := mulmod(alpha_base, alpha, p)
            alpha_base := mulmod(alpha_base, alpha, p)
        }

        challenges.alpha_base = alpha_base;

        return t1;
    }

    function compute_pedersen_gate_quotient_contribution(
        Types.ChallengeTranscript memory challenges,
        Types.Proof memory proof
    ) internal view returns (uint256) {
        uint256 alpha = challenges.alpha;
        uint256 gate_id = 0;
        uint256 alpha_base = challenges.alpha_base;

        {
            uint256 p = Bn254Crypto.r_mod;
            uint256 delta = 0;

            uint256 wire_t0 = proof.w4; // w4
            uint256 wire_t1 = proof.w4_omega; // w4_omega
            uint256 wire_t2 = proof.w3_omega; // w3_omega
            assembly {
                let wire4_neg := sub(p, wire_t0)
                delta := addmod(wire_t1, mulmod(wire4_neg, 0x04, p), p)

                gate_id := mulmod(
                    mulmod(
                        mulmod(
                            mulmod(add(delta, 0x01), add(delta, 0x03), p),
                            add(delta, sub(p, 0x01)),
                            p
                        ),
                        add(delta, sub(p, 0x03)),
                        p
                    ),
                    alpha_base,
                    p
                )
                alpha_base := mulmod(alpha_base, alpha, p)

                gate_id := addmod(
                    gate_id,
                    sub(p, mulmod(wire_t2, alpha_base, p)),
                    p
                )

                alpha_base := mulmod(alpha_base, alpha, p)
            }

            uint256 selector_value = proof.q_ecc;

            wire_t0 = proof.w1; // w1
            wire_t1 = proof.w1_omega; // w1_omega
            wire_t2 = proof.w2; // w2
            uint256 wire_t3 = proof.w3_omega; // w3_omega
            uint256 t0;
            uint256 t1;
            uint256 t2;
            assembly {
                t0 := addmod(wire_t1, addmod(wire_t0, wire_t3, p), p)

                t1 := addmod(wire_t3, sub(p, wire_t0), p)
                t1 := mulmod(t1, t1, p)

                t0 := mulmod(t0, t1, p)

                t1 := mulmod(wire_t3, mulmod(wire_t3, wire_t3, p), p)

                t2 := mulmod(wire_t2, wire_t2, p)

                t1 := sub(p, addmod(addmod(t1, t2, p), sub(p, 17), p))

                t2 := mulmod(mulmod(delta, wire_t2, p), selector_value, p)
                t2 := addmod(t2, t2, p)

                t0 := mulmod(addmod(t0, addmod(t1, t2, p), p), alpha_base, p)
                gate_id := addmod(gate_id, t0, p)

                alpha_base := mulmod(alpha_base, alpha, p)
            }

            wire_t0 = proof.w1; // w1
            wire_t1 = proof.w2_omega; // w2_omega
            wire_t2 = proof.w2; // w2
            wire_t3 = proof.w3_omega; // w3_omega
            uint256 wire_t4 = proof.w1_omega; // w1_omega
            assembly {
                t0 := mulmod(
                    addmod(wire_t1, wire_t2, p),
                    addmod(wire_t3, sub(p, wire_t0), p),
                    p
                )

                t1 := addmod(wire_t0, sub(p, wire_t4), p)

                t2 := addmod(
                    sub(p, mulmod(selector_value, delta, p)),
                    wire_t2,
                    p
                )

                gate_id := addmod(
                    gate_id,
                    mulmod(add(t0, mulmod(t1, t2, p)), alpha_base, p),
                    p
                )

                alpha_base := mulmod(alpha_base, alpha, p)
            }

            selector_value = proof.q_c;

            wire_t1 = proof.w4; // w4
            wire_t2 = proof.w3; // w3
            assembly {
                let acc_init_id := addmod(wire_t1, sub(p, 0x01), p)

                t1 := addmod(acc_init_id, sub(p, wire_t2), p)

                acc_init_id := mulmod(acc_init_id, mulmod(t1, alpha_base, p), p)
                acc_init_id := mulmod(acc_init_id, selector_value, p)

                gate_id := addmod(gate_id, acc_init_id, p)

                alpha_base := mulmod(alpha_base, alpha, p)
            }

            assembly {
                let x_init_id := sub(
                    p,
                    mulmod(
                        mulmod(wire_t0, selector_value, p),
                        mulmod(wire_t2, alpha_base, p),
                        p
                    )
                )

                gate_id := addmod(gate_id, x_init_id, p)

                alpha_base := mulmod(alpha_base, alpha, p)
            }

            wire_t0 = proof.w2; // w2
            wire_t1 = proof.w3; // w3
            wire_t2 = proof.w4; // w4
            assembly {
                let y_init_id := mulmod(
                    add(0x01, sub(p, wire_t2)),
                    selector_value,
                    p
                )

                t1 := sub(p, mulmod(wire_t0, wire_t1, p))

                y_init_id := mulmod(
                    add(y_init_id, t1),
                    mulmod(alpha_base, selector_value, p),
                    p
                )

                gate_id := addmod(gate_id, y_init_id, p)

                alpha_base := mulmod(alpha_base, alpha, p)
            }
            selector_value = proof.q_ecc;
            assembly {
                gate_id := mulmod(gate_id, selector_value, p)
            }
        }
        challenges.alpha_base = alpha_base;
        return gate_id;
    }

    function compute_permutation_quotient_contribution(
        uint256 public_input_delta,
        Types.ChallengeTranscript memory challenges,
        uint256 lagrange_start,
        uint256 lagrange_end,
        Types.Proof memory proof
    ) internal view returns (uint256) {
        uint256 numerator_collector;
        uint256 alpha = challenges.alpha;
        uint256 beta = challenges.beta;
        uint256 p = Bn254Crypto.r_mod;
        uint256 grand_product = proof.grand_product_at_z_omega;
        {
            uint256 gamma = challenges.gamma;
            uint256 wire1 = proof.w1;
            uint256 wire2 = proof.w2;
            uint256 wire3 = proof.w3;
            uint256 wire4 = proof.w4;
            uint256 sigma1 = proof.sigma1;
            uint256 sigma2 = proof.sigma2;
            uint256 sigma3 = proof.sigma3;
            assembly {
                let t0 := add(add(wire1, gamma), mulmod(beta, sigma1, p))

                let t1 := add(add(wire2, gamma), mulmod(beta, sigma2, p))

                let t2 := add(add(wire3, gamma), mulmod(beta, sigma3, p))

                t0 := mulmod(t0, mulmod(t1, t2, p), p)

                t0 := mulmod(t0, add(wire4, gamma), p)

                t0 := mulmod(t0, grand_product, p)

                t0 := mulmod(t0, alpha, p)

                numerator_collector := sub(p, t0)
            }
        }

        uint256 alpha_base = challenges.alpha_base;
        {
            uint256 lstart = lagrange_start;
            uint256 lend = lagrange_end;
            uint256 public_delta = public_input_delta;
            assembly {
                let alpha_squared := mulmod(alpha, alpha, p)
                let alpha_cubed := mulmod(alpha, alpha_squared, p)

                let t0 := mulmod(lstart, alpha_cubed, p)
                let t1 := mulmod(lend, alpha_squared, p)
                let t2 := addmod(grand_product, sub(p, public_delta), p)
                t1 := mulmod(t1, t2, p)

                numerator_collector := addmod(
                    numerator_collector,
                    sub(p, t0),
                    p
                )
                numerator_collector := addmod(numerator_collector, t1, p)
                alpha_base := mulmod(alpha_base, alpha_cubed, p)
            }
        }

        challenges.alpha_base = alpha_base;

        return numerator_collector;
    }

    // compute_r_0
    function compute_linear_polynomial_constant(
        uint256 zero_poly_inverse,
        uint256 public_input_delta,
        Types.ChallengeTranscript memory challenges,
        uint256 lagrange_start,
        uint256 lagrange_end,
        Types.Proof memory proof
    ) internal view returns (uint256) {
        uint256 t0 = compute_permutation_quotient_contribution(
            public_input_delta,
            challenges,
            lagrange_start,
            lagrange_end,
            proof
        );

        uint256 t1 = compute_arithmetic_gate_quotient_contribution(
            challenges,
            proof
        );

        uint256 t2 = compute_pedersen_gate_quotient_contribution(
            challenges,
            proof
        );

        uint256 r_0;
        uint256 p = Bn254Crypto.r_mod;
        assembly {
            r_0 := addmod(t0, addmod(t1, t2, p), p)
            // r_0 := mulmod(r_0, zero_poly_inverse, p) // not necessary for the simplified Plonk
        }
        return r_0;
    }

    function compute_linearised_opening_terms(
        Types.ChallengeTranscript memory challenges,
        uint256 L1_fr,
        Types.VerificationKey memory vk,
        Types.Proof memory proof
    ) internal view returns (Types.G1Point memory) {
        Types.G1Point
            memory accumulator = compute_grand_product_opening_group_element(
                proof,
                vk,
                challenges,
                L1_fr
            );
        Types.G1Point
            memory arithmetic_term = compute_arithmetic_selector_opening_group_element(
                proof,
                vk,
                challenges
            );
        uint256 range_multiplier = compute_range_gate_opening_scalar(
            proof,
            challenges
        );
        uint256 logic_multiplier = compute_logic_gate_opening_scalar(
            proof,
            challenges
        );

        Types.G1Point memory QRANGE = vk.QRANGE;
        Types.G1Point memory QLOGIC = vk.QLOGIC;
        QRANGE.validateG1Point();
        QLOGIC.validateG1Point();

        // compute range_multiplier.[QRANGE] + logic_multiplier.[QLOGIC] + [accumulator] + [grand_product_term]
        bool success;
        assembly {
            let mPtr := mload(0x40)

            // range_multiplier.[QRANGE]
            mstore(mPtr, mload(QRANGE))
            mstore(add(mPtr, 0x20), mload(add(QRANGE, 0x20)))
            mstore(add(mPtr, 0x40), range_multiplier)
            success := staticcall(gas(), 7, mPtr, 0x60, mPtr, 0x40)

            // add scalar mul output into accumulator
            // we use mPtr to store accumulated point
            mstore(add(mPtr, 0x40), mload(accumulator))
            mstore(add(mPtr, 0x60), mload(add(accumulator, 0x20)))
            success := and(
                success,
                staticcall(gas(), 6, mPtr, 0x80, mPtr, 0x40)
            )

            // logic_multiplier.[QLOGIC]
            mstore(add(mPtr, 0x40), mload(QLOGIC))
            mstore(add(mPtr, 0x60), mload(add(QLOGIC, 0x20)))
            mstore(add(mPtr, 0x80), logic_multiplier)
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(mPtr, 0x40),
                    0x60,
                    add(mPtr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(gas(), 6, mPtr, 0x80, mPtr, 0x40)
            )

            // add arithmetic into accumulator
            mstore(add(mPtr, 0x40), mload(arithmetic_term))
            mstore(add(mPtr, 0x60), mload(add(arithmetic_term, 0x20)))
            success := and(
                success,
                staticcall(gas(), 6, mPtr, 0x80, accumulator, 0x40)
            )
        }
        require(
            success,
            "compute_linearised_opening_terms group operations fail"
        );

        return accumulator;
    }

    function compute_batch_opening_commitment(
        Types.ChallengeTranscript memory challenges,
        Types.VerificationKey memory vk,
        Types.G1Point memory partial_opening_commitment,
        Types.Proof memory proof
    ) internal view returns (Types.G1Point memory) {
        // Computes the Kate opening proof group operations, for commitments that are not linearised
        bool success;
        // Reserve 0xa0 bytes of memory to perform group operations
        uint256 accumulator_ptr;
        uint256 p = Bn254Crypto.r_mod;
        assembly {
            accumulator_ptr := mload(0x40)
            mstore(0x40, add(accumulator_ptr, 0xa0))
        }
        // For the simplified plonk, we need to multiply -Z_H(z) with [T1],
        // proof.zero_poly_eval = Z_H(z)
        uint256 zero_poly_eval_neg = p - vk.zero_polynomial_eval;
        // [T2], [T3], [T4]
        // first term
        Types.G1Point memory work_point = proof.T1;
        work_point.validateG1Point();
        assembly {
            mstore(accumulator_ptr, mload(work_point))
            mstore(add(accumulator_ptr, 0x20), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x40), zero_poly_eval_neg)
            // computing zero_poly_eval_neg * [T1]
            success := staticcall(
                gas(),
                7,
                accumulator_ptr,
                0x60,
                accumulator_ptr,
                0x40
            )
        }

        // second term
        uint256 scalar_multiplier = vk.zeta_pow_n; // zeta_pow_n is computed in compute_lagrange_and_vanishing_fractions
        uint256 zeta_n = scalar_multiplier;
        work_point = proof.T2;
        work_point.validateG1Point();
        assembly {
            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(
                add(accumulator_ptr, 0x80),
                mulmod(scalar_multiplier, zero_poly_eval_neg, p)
            )

            // compute zero_poly_eval_neg * zeta_n * [T2]
            success := staticcall(
                gas(),
                7,
                add(accumulator_ptr, 0x40),
                0x60,
                add(accumulator_ptr, 0x40),
                0x40
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // third term
        work_point = proof.T3;
        work_point.validateG1Point();
        assembly {
            scalar_multiplier := mulmod(scalar_multiplier, scalar_multiplier, p)

            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(
                add(accumulator_ptr, 0x80),
                mulmod(scalar_multiplier, zero_poly_eval_neg, p)
            )

            // compute zero_poly_eval_neg * zeta_n^2 * [T3]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // fourth term
        work_point = proof.T4;
        work_point.validateG1Point();
        assembly {
            scalar_multiplier := mulmod(scalar_multiplier, zeta_n, p)

            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(
                add(accumulator_ptr, 0x80),
                mulmod(scalar_multiplier, zero_poly_eval_neg, p)
            )

            // compute zero_poly_eval_neg * zeta_n^3 * [T4]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // fifth term
        work_point = partial_opening_commitment;
        work_point.validateG1Point();
        assembly {
            // add partial opening commitment into accumulator
            mstore(
                add(accumulator_ptr, 0x40),
                mload(partial_opening_commitment)
            )
            mstore(
                add(accumulator_ptr, 0x60),
                mload(add(partial_opening_commitment, 0x20))
            )
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        uint256 u_plus_one = challenges.u;
        uint256 v_challenge = challenges.v0;

        // W1
        work_point = proof.W1;
        work_point.validateG1Point();
        assembly {
            u_plus_one := addmod(u_plus_one, 0x01, p)

            scalar_multiplier := mulmod(v_challenge, u_plus_one, p)

            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v0(u + 1).[W1]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // W2
        v_challenge = challenges.v1;
        work_point = proof.W2;
        work_point.validateG1Point();
        assembly {
            scalar_multiplier := mulmod(v_challenge, u_plus_one, p)

            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v1(u + 1).[W2]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // W3
        v_challenge = challenges.v2;
        work_point = proof.W3;
        work_point.validateG1Point();
        assembly {
            scalar_multiplier := mulmod(v_challenge, u_plus_one, p)

            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v2(u + 1).[W3]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // W4
        v_challenge = challenges.v3;
        work_point = proof.W4;
        work_point.validateG1Point();
        assembly {
            scalar_multiplier := mulmod(v_challenge, u_plus_one, p)

            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v3(u + 1).[W4]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // SIGMA1
        scalar_multiplier = challenges.v4;
        work_point = vk.SIGMA1;
        work_point.validateG1Point();
        assembly {
            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v4.[SIGMA1]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // SIGMA2
        scalar_multiplier = challenges.v5;
        work_point = vk.SIGMA2;
        work_point.validateG1Point();
        assembly {
            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v5.[SIGMA2]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // SIGMA3
        scalar_multiplier = challenges.v6;
        work_point = vk.SIGMA3;
        work_point.validateG1Point();
        assembly {
            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v6.[SIGMA3]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        // QARITH
        scalar_multiplier = challenges.v7;
        work_point = vk.QARITH;
        work_point.validateG1Point();
        assembly {
            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v7.[QARITH]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into accumulator
            success := and(
                success,
                staticcall(
                    gas(),
                    6,
                    accumulator_ptr,
                    0x80,
                    accumulator_ptr,
                    0x40
                )
            )
        }

        Types.G1Point memory output;
        // QECC
        scalar_multiplier = challenges.v8;
        work_point = vk.QECC;
        work_point.validateG1Point();
        assembly {
            mstore(add(accumulator_ptr, 0x40), mload(work_point))
            mstore(add(accumulator_ptr, 0x60), mload(add(work_point, 0x20)))
            mstore(add(accumulator_ptr, 0x80), scalar_multiplier)

            // compute v8.[QECC]
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(accumulator_ptr, 0x40),
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )
            )

            // add scalar mul output into output point
            success := and(
                success,
                staticcall(gas(), 6, accumulator_ptr, 0x80, output, 0x40)
            )
        }

        require(
            success,
            "compute_batch_opening_commitment group operations error"
        );

        return output;
    }

    function compute_batch_evaluation_scalar_multiplier(
        Types.Proof memory proof,
        Types.ChallengeTranscript memory challenges
    ) internal view returns (uint256) {
        uint256 p = Bn254Crypto.r_mod;
        uint256 opening_scalar;
        uint256 lhs; // stores nu challenges
        uint256 rhs; // stores evaluations of polynomials

        lhs = challenges.v0;
        rhs = proof.w1;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v1;
        rhs = proof.w2;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v2;
        rhs = proof.w3;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v3;
        rhs = proof.w4;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v4;
        rhs = proof.sigma1;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v5;
        rhs = proof.sigma2;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v6;
        rhs = proof.sigma3;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v7;
        rhs = proof.q_arith;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v8;
        rhs = proof.q_ecc;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        lhs = challenges.v9;
        rhs = proof.q_c;
        assembly {
            opening_scalar := addmod(opening_scalar, mulmod(lhs, rhs, p), p)
        }

        // lhs = 1;    //challenges.v10; (should be -1 for simplified Plonk)
        rhs = proof.r_0; // linearization_polynomial should be r_0 for simplified Plonk
        assembly {
            opening_scalar := addmod(opening_scalar, sub(p, rhs), p)
        }
        // should be removed for simplified Plonk
        // lhs = proof.quotient_polynomial_eval;
        // assembly {
        //     opening_scalar := addmod(opening_scalar, lhs, p)
        // }

        lhs = challenges.v0;
        rhs = proof.w1_omega;
        uint256 shifted_opening_scalar;
        assembly {
            shifted_opening_scalar := mulmod(lhs, rhs, p)
        }

        lhs = challenges.v1;
        rhs = proof.w2_omega;
        assembly {
            shifted_opening_scalar := addmod(
                shifted_opening_scalar,
                mulmod(lhs, rhs, p),
                p
            )
        }

        lhs = challenges.v2;
        rhs = proof.w3_omega;
        assembly {
            shifted_opening_scalar := addmod(
                shifted_opening_scalar,
                mulmod(lhs, rhs, p),
                p
            )
        }

        lhs = challenges.v3;
        rhs = proof.w4_omega;
        assembly {
            shifted_opening_scalar := addmod(
                shifted_opening_scalar,
                mulmod(lhs, rhs, p),
                p
            )
        }

        lhs = proof.grand_product_at_z_omega;
        assembly {
            shifted_opening_scalar := addmod(shifted_opening_scalar, lhs, p)
        }

        lhs = challenges.u;
        assembly {
            shifted_opening_scalar := mulmod(shifted_opening_scalar, lhs, p)

            opening_scalar := addmod(opening_scalar, shifted_opening_scalar, p)
        }

        return opening_scalar;
    }

    // Compute kate opening scalar for arithmetic gate selectors and pedersen gate selectors
    // (both the arithmetic gate and pedersen hash gate reuse the same selectors)
    function compute_arithmetic_selector_opening_group_element(
        Types.Proof memory proof,
        Types.VerificationKey memory vk,
        Types.ChallengeTranscript memory challenges
    ) internal view returns (Types.G1Point memory) {
        uint256 q_arith = proof.q_arith;
        uint256 q_ecc = proof.q_ecc;
        uint256 alpha_base = challenges.alpha_base;
        uint256 scaling_alpha = challenges.alpha_base;
        uint256 alpha = challenges.alpha;
        uint256 p = Bn254Crypto.r_mod;
        uint256 scalar_multiplier;
        uint256 accumulator_ptr; // reserve 0xa0 bytes of memory to multiply and add points
        assembly {
            accumulator_ptr := mload(0x40)
            mstore(0x40, add(accumulator_ptr, 0xa0))
        }
        {
            uint256 delta;
            // Q1 Selector
            {
                {
                    uint256 w4 = proof.w4;
                    uint256 w4_omega = proof.w4_omega;
                    assembly {
                        delta := addmod(
                            w4_omega,
                            sub(p, mulmod(w4, 0x04, p)),
                            p
                        )
                    }
                }
                uint256 w1 = proof.w1;

                assembly {
                    scalar_multiplier := w1
                    scalar_multiplier := mulmod(
                        scalar_multiplier,
                        alpha_base,
                        p
                    )
                    scalar_multiplier := mulmod(scalar_multiplier, q_arith, p)

                    scaling_alpha := mulmod(scaling_alpha, alpha, p)
                    scaling_alpha := mulmod(scaling_alpha, alpha, p)
                    scaling_alpha := mulmod(scaling_alpha, alpha, p)
                    let t0 := mulmod(delta, delta, p)
                    t0 := mulmod(t0, q_ecc, p)
                    t0 := mulmod(t0, scaling_alpha, p)

                    scalar_multiplier := addmod(scalar_multiplier, t0, p)
                }
                Types.G1Point memory Q1 = vk.Q1;
                Q1.validateG1Point();
                bool success;
                assembly {
                    let mPtr := mload(0x40)
                    mstore(mPtr, mload(Q1))
                    mstore(add(mPtr, 0x20), mload(add(Q1, 0x20)))
                    mstore(add(mPtr, 0x40), scalar_multiplier)
                    success := staticcall(
                        gas(),
                        7,
                        mPtr,
                        0x60,
                        accumulator_ptr,
                        0x40
                    )
                }
                require(success, "G1 point multiplication failed!");
            }

            // Q2 Selector
            {
                uint256 w2 = proof.w2;
                assembly {
                    scalar_multiplier := w2
                    scalar_multiplier := mulmod(
                        scalar_multiplier,
                        alpha_base,
                        p
                    )
                    scalar_multiplier := mulmod(scalar_multiplier, q_arith, p)

                    let t0 := mulmod(scaling_alpha, q_ecc, p)
                    scalar_multiplier := addmod(scalar_multiplier, t0, p)
                }

                Types.G1Point memory Q2 = vk.Q2;
                Q2.validateG1Point();
                bool success;
                assembly {
                    let mPtr := mload(0x40)
                    mstore(mPtr, mload(Q2))
                    mstore(add(mPtr, 0x20), mload(add(Q2, 0x20)))
                    mstore(add(mPtr, 0x40), scalar_multiplier)

                    // write scalar mul output 0x40 bytes ahead of accumulator
                    success := staticcall(
                        gas(),
                        7,
                        mPtr,
                        0x60,
                        add(accumulator_ptr, 0x40),
                        0x40
                    )

                    // add scalar mul output into accumulator
                    success := and(
                        success,
                        staticcall(
                            gas(),
                            6,
                            accumulator_ptr,
                            0x80,
                            accumulator_ptr,
                            0x40
                        )
                    )
                }
                require(success, "G1 point multiplication failed!");
            }

            // Q3 Selector
            {
                {
                    uint256 w3 = proof.w3;
                    assembly {
                        scalar_multiplier := w3
                        scalar_multiplier := mulmod(
                            scalar_multiplier,
                            alpha_base,
                            p
                        )
                        scalar_multiplier := mulmod(
                            scalar_multiplier,
                            q_arith,
                            p
                        )
                    }
                }
                {
                    uint256 t1;
                    {
                        uint256 w3_omega = proof.w3_omega;
                        assembly {
                            t1 := mulmod(delta, w3_omega, p)
                        }
                    }
                    {
                        uint256 w2 = proof.w2;
                        assembly {
                            scaling_alpha := mulmod(scaling_alpha, alpha, p)

                            t1 := mulmod(t1, w2, p)
                            t1 := mulmod(t1, scaling_alpha, p)
                            t1 := addmod(t1, t1, p)
                            t1 := mulmod(t1, q_ecc, p)

                            scalar_multiplier := addmod(
                                scalar_multiplier,
                                t1,
                                p
                            )
                        }
                    }
                }
                uint256 t0 = proof.w1_omega;
                {
                    uint256 w1 = proof.w1;
                    assembly {
                        scaling_alpha := mulmod(scaling_alpha, alpha, p)
                        t0 := addmod(t0, sub(p, w1), p)
                        t0 := mulmod(t0, delta, p)
                    }
                }
                uint256 w3_omega = proof.w3_omega;
                assembly {
                    t0 := mulmod(t0, w3_omega, p)
                    t0 := mulmod(t0, scaling_alpha, p)

                    t0 := mulmod(t0, q_ecc, p)

                    scalar_multiplier := addmod(scalar_multiplier, t0, p)
                }
            }

            Types.G1Point memory Q3 = vk.Q3;
            Q3.validateG1Point();
            bool success;
            assembly {
                let mPtr := mload(0x40)
                mstore(mPtr, mload(Q3))
                mstore(add(mPtr, 0x20), mload(add(Q3, 0x20)))
                mstore(add(mPtr, 0x40), scalar_multiplier)

                // write scalar mul output 0x40 bytes ahead of accumulator
                success := staticcall(
                    gas(),
                    7,
                    mPtr,
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )

                // add scalar mul output into accumulator
                success := and(
                    success,
                    staticcall(
                        gas(),
                        6,
                        accumulator_ptr,
                        0x80,
                        accumulator_ptr,
                        0x40
                    )
                )
            }
            require(success, "G1 point multiplication failed!");
        }

        // Q4 Selector
        {
            uint256 w3 = proof.w3;
            uint256 w4 = proof.w4;
            uint256 q_c = proof.q_c;
            assembly {
                scalar_multiplier := w4
                scalar_multiplier := mulmod(scalar_multiplier, alpha_base, p)
                scalar_multiplier := mulmod(scalar_multiplier, q_arith, p)

                scaling_alpha := mulmod(
                    scaling_alpha,
                    mulmod(alpha, alpha, p),
                    p
                )
                let t0 := mulmod(w3, q_ecc, p)
                t0 := mulmod(t0, q_c, p)
                t0 := mulmod(t0, scaling_alpha, p)

                scalar_multiplier := addmod(scalar_multiplier, t0, p)
            }

            Types.G1Point memory Q4 = vk.Q4;
            Q4.validateG1Point();
            bool success;
            assembly {
                let mPtr := mload(0x40)
                mstore(mPtr, mload(Q4))
                mstore(add(mPtr, 0x20), mload(add(Q4, 0x20)))
                mstore(add(mPtr, 0x40), scalar_multiplier)

                // write scalar mul output 0x40 bytes ahead of accumulator
                success := staticcall(
                    gas(),
                    7,
                    mPtr,
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )

                // add scalar mul output into accumulator
                success := and(
                    success,
                    staticcall(
                        gas(),
                        6,
                        accumulator_ptr,
                        0x80,
                        accumulator_ptr,
                        0x40
                    )
                )
            }
            require(success, "G1 point multiplication failed!");
        }

        // Q5 Selector
        {
            uint256 w4 = proof.w4;
            uint256 q_c = proof.q_c;
            assembly {
                let neg_w4 := sub(p, w4)
                scalar_multiplier := mulmod(w4, w4, p)
                scalar_multiplier := addmod(scalar_multiplier, neg_w4, p)
                scalar_multiplier := mulmod(
                    scalar_multiplier,
                    addmod(w4, sub(p, 2), p),
                    p
                )
                scalar_multiplier := mulmod(scalar_multiplier, alpha_base, p)
                scalar_multiplier := mulmod(scalar_multiplier, alpha, p)
                scalar_multiplier := mulmod(scalar_multiplier, q_arith, p)

                let t0 := addmod(0x01, neg_w4, p)
                t0 := mulmod(t0, q_ecc, p)
                t0 := mulmod(t0, q_c, p)
                t0 := mulmod(t0, scaling_alpha, p)

                scalar_multiplier := addmod(scalar_multiplier, t0, p)
            }

            Types.G1Point memory Q5 = vk.Q5;
            Q5.validateG1Point();
            bool success;
            assembly {
                let mPtr := mload(0x40)
                mstore(mPtr, mload(Q5))
                mstore(add(mPtr, 0x20), mload(add(Q5, 0x20)))
                mstore(add(mPtr, 0x40), scalar_multiplier)

                // write scalar mul output 0x40 bytes ahead of accumulator
                success := staticcall(
                    gas(),
                    7,
                    mPtr,
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )

                // add scalar mul output into accumulator
                success := and(
                    success,
                    staticcall(
                        gas(),
                        6,
                        accumulator_ptr,
                        0x80,
                        accumulator_ptr,
                        0x40
                    )
                )
            }
            require(success, "G1 point multiplication failed!");
        }

        // QM Selector
        {
            {
                uint256 w1 = proof.w1;
                uint256 w2 = proof.w2;

                assembly {
                    scalar_multiplier := mulmod(w1, w2, p)
                    scalar_multiplier := mulmod(
                        scalar_multiplier,
                        alpha_base,
                        p
                    )
                    scalar_multiplier := mulmod(scalar_multiplier, q_arith, p)
                }
            }
            uint256 w3 = proof.w3;
            uint256 q_c = proof.q_c;
            assembly {
                scaling_alpha := mulmod(scaling_alpha, alpha, p)
                let t0 := mulmod(w3, q_ecc, p)
                t0 := mulmod(t0, q_c, p)
                t0 := mulmod(t0, scaling_alpha, p)

                scalar_multiplier := addmod(scalar_multiplier, t0, p)
            }

            Types.G1Point memory QM = vk.QM;
            QM.validateG1Point();
            bool success;
            assembly {
                let mPtr := mload(0x40)
                mstore(mPtr, mload(QM))
                mstore(add(mPtr, 0x20), mload(add(QM, 0x20)))
                mstore(add(mPtr, 0x40), scalar_multiplier)

                // write scalar mul output 0x40 bytes ahead of accumulator
                success := staticcall(
                    gas(),
                    7,
                    mPtr,
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )

                // add scalar mul output into accumulator
                success := and(
                    success,
                    staticcall(
                        gas(),
                        6,
                        accumulator_ptr,
                        0x80,
                        accumulator_ptr,
                        0x40
                    )
                )
            }
            require(success, "G1 point multiplication failed!");
        }

        Types.G1Point memory output;
        // QC Selector
        {
            uint256 q_c_challenge = challenges.v9;
            assembly {
                scalar_multiplier := alpha_base
                scalar_multiplier := mulmod(scalar_multiplier, q_arith, p)

                // TurboPlonk requires an explicit evaluation of q_c
                scalar_multiplier := addmod(scalar_multiplier, q_c_challenge, p)

                alpha_base := mulmod(scaling_alpha, alpha, p)
            }

            Types.G1Point memory QC = vk.QC;
            QC.validateG1Point();
            bool success;
            assembly {
                let mPtr := mload(0x40)
                mstore(mPtr, mload(QC))
                mstore(add(mPtr, 0x20), mload(add(QC, 0x20)))
                mstore(add(mPtr, 0x40), scalar_multiplier)

                // write scalar mul output 0x40 bytes ahead of accumulator
                success := staticcall(
                    gas(),
                    7,
                    mPtr,
                    0x60,
                    add(accumulator_ptr, 0x40),
                    0x40
                )

                // add scalar mul output into output point
                success := and(
                    success,
                    staticcall(gas(), 6, accumulator_ptr, 0x80, output, 0x40)
                )
            }
            require(success, "G1 point multiplication failed!");
        }
        challenges.alpha_base = alpha_base;

        return output;
    }

    // Compute kate opening scalar for logic gate opening scalars
    // This method evalautes the polynomial identity used to evaluate either
    // a 2-bit AND or XOR operation in a single constraint
    function compute_logic_gate_opening_scalar(
        Types.Proof memory proof,
        Types.ChallengeTranscript memory challenges
    ) internal pure returns (uint256) {
        uint256 identity = 0;
        uint256 p = Bn254Crypto.r_mod;
        {
            uint256 delta_sum = 0;
            uint256 delta_squared_sum = 0;
            uint256 t0 = 0;
            uint256 t1 = 0;
            uint256 t2 = 0;
            uint256 t3 = 0;
            {
                uint256 wire1_omega = proof.w1_omega;
                uint256 wire1 = proof.w1;
                assembly {
                    t0 := addmod(wire1_omega, sub(p, mulmod(wire1, 0x04, p)), p)
                }
            }

            {
                uint256 wire2_omega = proof.w2_omega;
                uint256 wire2 = proof.w2;
                assembly {
                    t1 := addmod(wire2_omega, sub(p, mulmod(wire2, 0x04, p)), p)

                    delta_sum := addmod(t0, t1, p)
                    t2 := mulmod(t0, t0, p)
                    t3 := mulmod(t1, t1, p)
                    delta_squared_sum := addmod(t2, t3, p)
                    identity := mulmod(delta_sum, delta_sum, p)
                    identity := addmod(identity, sub(p, delta_squared_sum), p)
                }
            }

            uint256 t4 = 0;
            uint256 alpha = challenges.alpha;

            {
                uint256 wire3 = proof.w3;
                assembly {
                    t4 := mulmod(wire3, 0x02, p)
                    identity := addmod(identity, sub(p, t4), p)
                    identity := mulmod(identity, alpha, p)
                }
            }

            assembly {
                t4 := addmod(t4, t4, p)
                t2 := addmod(t2, sub(p, t0), p)
                t0 := mulmod(t0, 0x04, p)
                t0 := addmod(t2, sub(p, t0), p)
                t0 := addmod(t0, 0x06, p)

                t0 := mulmod(t0, t2, p)
                identity := addmod(identity, t0, p)
                identity := mulmod(identity, alpha, p)

                t3 := addmod(t3, sub(p, t1), p)
                t1 := mulmod(t1, 0x04, p)
                t1 := addmod(t3, sub(p, t1), p)
                t1 := addmod(t1, 0x06, p)

                t1 := mulmod(t1, t3, p)
                identity := addmod(identity, t1, p)
                identity := mulmod(identity, alpha, p)

                t0 := mulmod(delta_sum, 0x03, p)

                t1 := mulmod(t0, 0x03, p)

                delta_sum := addmod(t1, t1, p)

                t2 := mulmod(delta_sum, 0x04, p)
                t1 := addmod(t1, t2, p)

                t2 := mulmod(delta_squared_sum, 0x03, p)

                delta_squared_sum := mulmod(t2, 0x06, p)

                delta_sum := addmod(t4, sub(p, delta_sum), p)
                delta_sum := addmod(delta_sum, 81, p)

                t1 := addmod(delta_squared_sum, sub(p, t1), p)
                t1 := addmod(t1, 83, p)
            }

            {
                uint256 wire3 = proof.w3;
                assembly {
                    delta_sum := mulmod(delta_sum, wire3, p)

                    delta_sum := addmod(delta_sum, t1, p)
                    delta_sum := mulmod(delta_sum, wire3, p)
                }
            }
            {
                uint256 wire4 = proof.w4;
                assembly {
                    t2 := mulmod(wire4, 0x04, p)
                }
            }
            {
                uint256 wire4_omega = proof.w4_omega;
                assembly {
                    t2 := addmod(wire4_omega, sub(p, t2), p)
                }
            }
            {
                uint256 q_c = proof.q_c;
                assembly {
                    t3 := addmod(t2, t2, p)
                    t2 := addmod(t2, t3, p)

                    t3 := addmod(t2, t2, p)
                    t3 := addmod(t3, t2, p)

                    t3 := addmod(t3, sub(p, t0), p)
                    t3 := mulmod(t3, q_c, p)

                    t2 := addmod(t2, t0, p)
                    delta_sum := addmod(delta_sum, delta_sum, p)
                    t2 := addmod(t2, sub(p, delta_sum), p)

                    t2 := addmod(t2, t3, p)

                    identity := addmod(identity, t2, p)
                }
            }
            uint256 alpha_base = challenges.alpha_base;

            assembly {
                identity := mulmod(identity, alpha_base, p)
            }
        }
        // update alpha
        uint256 alpha_base = challenges.alpha_base;
        uint256 alpha = challenges.alpha;
        assembly {
            alpha := mulmod(alpha, alpha, p)
            alpha := mulmod(alpha, alpha, p)
            alpha_base := mulmod(alpha_base, alpha, p)
        }
        challenges.alpha_base = alpha_base;

        return identity;
    }

    // Compute kate opening scalar for arithmetic gate selectors
    function compute_range_gate_opening_scalar(
        Types.Proof memory proof,
        Types.ChallengeTranscript memory challenges
    ) internal pure returns (uint256) {
        uint256 wire1 = proof.w1;
        uint256 wire2 = proof.w2;
        uint256 wire3 = proof.w3;
        uint256 wire4 = proof.w4;
        uint256 wire4_omega = proof.w4_omega;
        uint256 alpha = challenges.alpha;
        uint256 alpha_base = challenges.alpha_base;
        uint256 range_acc;
        uint256 p = Bn254Crypto.r_mod;
        assembly {
            let delta_1 := addmod(wire3, sub(p, mulmod(wire4, 0x04, p)), p)
            let delta_2 := addmod(wire2, sub(p, mulmod(wire3, 0x04, p)), p)
            let delta_3 := addmod(wire1, sub(p, mulmod(wire2, 0x04, p)), p)
            let delta_4 := addmod(
                wire4_omega,
                sub(p, mulmod(wire1, 0x04, p)),
                p
            )

            let t0 := mulmod(delta_1, delta_1, p)
            t0 := addmod(t0, sub(p, delta_1), p)
            let t1 := addmod(delta_1, sub(p, 2), p)
            t0 := mulmod(t0, t1, p)
            t1 := addmod(delta_1, sub(p, 3), p)
            t0 := mulmod(t0, t1, p)
            t0 := mulmod(t0, alpha_base, p)

            range_acc := t0
            alpha_base := mulmod(alpha_base, alpha, p)

            t0 := mulmod(delta_2, delta_2, p)
            t0 := addmod(t0, sub(p, delta_2), p)
            t1 := addmod(delta_2, sub(p, 2), p)
            t0 := mulmod(t0, t1, p)
            t1 := addmod(delta_2, sub(p, 3), p)
            t0 := mulmod(t0, t1, p)
            t0 := mulmod(t0, alpha_base, p)
            range_acc := addmod(range_acc, t0, p)
            alpha_base := mulmod(alpha_base, alpha, p)

            t0 := mulmod(delta_3, delta_3, p)
            t0 := addmod(t0, sub(p, delta_3), p)
            t1 := addmod(delta_3, sub(p, 2), p)
            t0 := mulmod(t0, t1, p)
            t1 := addmod(delta_3, sub(p, 3), p)
            t0 := mulmod(t0, t1, p)
            t0 := mulmod(t0, alpha_base, p)
            range_acc := addmod(range_acc, t0, p)
            alpha_base := mulmod(alpha_base, alpha, p)

            t0 := mulmod(delta_4, delta_4, p)
            t0 := addmod(t0, sub(p, delta_4), p)
            t1 := addmod(delta_4, sub(p, 2), p)
            t0 := mulmod(t0, t1, p)
            t1 := addmod(delta_4, sub(p, 3), p)
            t0 := mulmod(t0, t1, p)
            t0 := mulmod(t0, alpha_base, p)
            range_acc := addmod(range_acc, t0, p)
            alpha_base := mulmod(alpha_base, alpha, p)
        }

        challenges.alpha_base = alpha_base;
        return range_acc;
    }

    // Compute grand product opening scalar and perform kate verification scalar multiplication
    function compute_grand_product_opening_group_element(
        Types.Proof memory proof,
        Types.VerificationKey memory vk,
        Types.ChallengeTranscript memory challenges,
        uint256 L1_fr
    ) internal view returns (Types.G1Point memory) {
        uint256 beta = challenges.beta;
        uint256 zeta = challenges.zeta;
        uint256 gamma = challenges.gamma;
        uint256 p = Bn254Crypto.r_mod;

        uint256 partial_grand_product;
        uint256 sigma_multiplier;

        {
            uint256 w1 = proof.w1;
            uint256 sigma1 = proof.sigma1;
            assembly {
                let witness_term := addmod(w1, gamma, p)
                partial_grand_product := addmod(
                    mulmod(beta, zeta, p),
                    witness_term,
                    p
                )
                sigma_multiplier := addmod(
                    mulmod(sigma1, beta, p),
                    witness_term,
                    p
                )
            }
        }
        {
            uint256 w2 = proof.w2;
            uint256 sigma2 = proof.sigma2;
            assembly {
                let witness_term := addmod(w2, gamma, p)
                partial_grand_product := mulmod(
                    partial_grand_product,
                    addmod(
                        mulmod(mulmod(zeta, 0x05, p), beta, p),
                        witness_term,
                        p
                    ),
                    p
                )
                sigma_multiplier := mulmod(
                    sigma_multiplier,
                    addmod(mulmod(sigma2, beta, p), witness_term, p),
                    p
                )
            }
        }
        {
            uint256 w3 = proof.w3;
            uint256 sigma3 = proof.sigma3;
            assembly {
                let witness_term := addmod(w3, gamma, p)
                partial_grand_product := mulmod(
                    partial_grand_product,
                    addmod(
                        mulmod(mulmod(zeta, 0x06, p), beta, p),
                        witness_term,
                        p
                    ),
                    p
                )

                sigma_multiplier := mulmod(
                    sigma_multiplier,
                    addmod(mulmod(sigma3, beta, p), witness_term, p),
                    p
                )
            }
        }
        {
            uint256 w4 = proof.w4;
            assembly {
                partial_grand_product := mulmod(
                    partial_grand_product,
                    addmod(
                        addmod(
                            mulmod(mulmod(zeta, 0x07, p), beta, p),
                            gamma,
                            p
                        ),
                        w4,
                        p
                    ),
                    p
                )
            }
        }
        {
            uint256 alpha_base = challenges.alpha_base;
            uint256 alpha = challenges.alpha;
            uint256 separator_challenge = challenges.u;
            uint256 grand_product_at_z_omega = proof.grand_product_at_z_omega;
            uint256 l_start = L1_fr;
            assembly {
                partial_grand_product := mulmod(
                    partial_grand_product,
                    alpha_base,
                    p
                )

                sigma_multiplier := mulmod(
                    sub(
                        p,
                        mulmod(
                            mulmod(
                                sigma_multiplier,
                                grand_product_at_z_omega,
                                p
                            ),
                            alpha_base,
                            p
                        )
                    ),
                    beta,
                    p
                )

                alpha_base := mulmod(mulmod(alpha_base, alpha, p), alpha, p)

                partial_grand_product := addmod(
                    addmod(
                        partial_grand_product,
                        mulmod(l_start, alpha_base, p),
                        p
                    ),
                    separator_challenge,
                    p
                )

                alpha_base := mulmod(alpha_base, alpha, p)
            }
            challenges.alpha_base = alpha_base;
        }
        //Need to understand the below code:
        Types.G1Point memory Z = proof.Z;
        Types.G1Point memory SIGMA4 = vk.SIGMA4;
        Types.G1Point memory accumulator;
        Z.validateG1Point();
        SIGMA4.validateG1Point();
        bool success;
        assembly {
            let mPtr := mload(0x40)
            mstore(mPtr, mload(Z))
            mstore(add(mPtr, 0x20), mload(add(Z, 0x20)))
            mstore(add(mPtr, 0x40), partial_grand_product)
            success := staticcall(gas(), 7, mPtr, 0x60, mPtr, 0x40)

            mstore(add(mPtr, 0x40), mload(SIGMA4))
            mstore(add(mPtr, 0x60), mload(add(SIGMA4, 0x20)))
            mstore(add(mPtr, 0x80), sigma_multiplier)
            success := and(
                success,
                staticcall(
                    gas(),
                    7,
                    add(mPtr, 0x40),
                    0x60,
                    add(mPtr, 0x40),
                    0x40
                )
            )

            // mload(mPtr) : (partial_grand_product * [Z]).x
            // mload(mPtr + 32) : (partial_grand_product * [Z]).y
            // mload(mPtr + 64) : (sigma_multiplier * [SIGMA_4]).x
            // mload(mPtr + 96) : (sigma_multiplier * [SIGMA_4]).y

            success := and(
                success,
                staticcall(gas(), 6, mPtr, 0x80, accumulator, 0x40)
            )
        }

        require(
            success,
            "compute_grand_product_opening_scalar group operations failure"
        );
        return accumulator;
    }
}


    
    
    

/**
 * @title Transcript library
 * @dev Generates Plonk random challenges
 */
library Transcript {
    struct TranscriptData {
        bytes32 current_challenge;
    }

    /**
     * Compute keccak256 hash of 2 4-byte variables (circuit_size, num_public_inputs)
     */
    function generate_initial_challenge(
        TranscriptData memory self,
        uint256 circuit_size,
        uint256 num_public_inputs
    ) internal pure {
        bytes32 challenge;
        assembly {
            let mPtr := mload(0x40)
            mstore8(add(mPtr, 0x20), shr(24, circuit_size))
            mstore8(add(mPtr, 0x21), shr(16, circuit_size))
            mstore8(add(mPtr, 0x22), shr(8, circuit_size))
            mstore8(add(mPtr, 0x23), circuit_size)
            mstore8(add(mPtr, 0x24), shr(24, num_public_inputs))
            mstore8(add(mPtr, 0x25), shr(16, num_public_inputs))
            mstore8(add(mPtr, 0x26), shr(8, num_public_inputs))
            mstore8(add(mPtr, 0x27), num_public_inputs)
            challenge := keccak256(add(mPtr, 0x20), 0x08)
        }
        self.current_challenge = challenge;
    }

    /**
     * We treat the beta challenge as a special case, because it includes the public inputs.
     * The number of public inputs can be extremely large for rollups and we want to minimize mem consumption.
     * => we directly allocate memory to hash the public inputs, in order to prevent the global memory pointer from increasing
     */
    function generate_beta_gamma_challenges(
        TranscriptData memory self,
        Types.ChallengeTranscript memory challenges,
        uint256 num_public_inputs
    ) internal pure {
        bytes32 challenge;
        bytes32 old_challenge = self.current_challenge;
        uint256 p = Bn254Crypto.r_mod;
        uint256 reduced_challenge;
        assembly {
            let m_ptr := mload(0x40)
            // N.B. If the calldata ABI changes this code will need to change!
            // We can copy all of the public inputs, followed by the wire commitments, into memory
            // using calldatacopy
            mstore(m_ptr, old_challenge)
            m_ptr := add(m_ptr, 0x20)
            let inputs_start := add(calldataload(0x04), 0x24)
            // num_calldata_bytes = public input size + 256 bytes for the 4 wire commitments
            let num_calldata_bytes := add(0x100, mul(num_public_inputs, 0x20))
            calldatacopy(m_ptr, inputs_start, num_calldata_bytes)

            let start := mload(0x40)
            let length := add(num_calldata_bytes, 0x20)

            challenge := keccak256(start, length)
            reduced_challenge := mod(challenge, p)
        }
        challenges.beta = reduced_challenge;

        // get gamma challenge by appending 1 to the beta challenge and hash
        assembly {
            mstore(0x00, challenge)
            mstore8(0x20, 0x01)
            challenge := keccak256(0, 0x21)
            reduced_challenge := mod(challenge, p)
        }
        challenges.gamma = reduced_challenge;
        self.current_challenge = challenge;
    }

    function generate_alpha_challenge(
        TranscriptData memory self,
        Types.ChallengeTranscript memory challenges,
        Types.G1Point memory Z
    ) internal pure {
        bytes32 challenge;
        bytes32 old_challenge = self.current_challenge;
        uint256 p = Bn254Crypto.r_mod;
        uint256 reduced_challenge;
        assembly {
            let m_ptr := mload(0x40)
            mstore(m_ptr, old_challenge)
            mstore(add(m_ptr, 0x20), mload(add(Z, 0x20)))
            mstore(add(m_ptr, 0x40), mload(Z))
            challenge := keccak256(m_ptr, 0x60)
            reduced_challenge := mod(challenge, p)
        }
        challenges.alpha = reduced_challenge;
        challenges.alpha_base = reduced_challenge;
        self.current_challenge = challenge;
    }

    function generate_zeta_challenge(
        TranscriptData memory self,
        Types.ChallengeTranscript memory challenges,
        Types.G1Point memory T1,
        Types.G1Point memory T2,
        Types.G1Point memory T3,
        Types.G1Point memory T4
    ) internal pure {
        bytes32 challenge;
        bytes32 old_challenge = self.current_challenge;
        uint256 p = Bn254Crypto.r_mod;
        uint256 reduced_challenge;
        assembly {
            let m_ptr := mload(0x40)
            mstore(m_ptr, old_challenge)
            mstore(add(m_ptr, 0x20), mload(add(T1, 0x20)))
            mstore(add(m_ptr, 0x40), mload(T1))
            mstore(add(m_ptr, 0x60), mload(add(T2, 0x20)))
            mstore(add(m_ptr, 0x80), mload(T2))
            mstore(add(m_ptr, 0xa0), mload(add(T3, 0x20)))
            mstore(add(m_ptr, 0xc0), mload(T3))
            mstore(add(m_ptr, 0xe0), mload(add(T4, 0x20)))
            mstore(add(m_ptr, 0x100), mload(T4))
            challenge := keccak256(m_ptr, 0x120)
            reduced_challenge := mod(challenge, p)
        }
        challenges.zeta = reduced_challenge;
        self.current_challenge = challenge;
    }

    /**
     * We compute our initial nu challenge by hashing the following proof elements (with the current challenge):
     *
     * w1, w2, w3, w4, sigma1, sigma2, sigma3, q_arith, q_ecc, q_c, linearization_poly, grand_product_at_z_omega,
     * w1_omega, w2_omega, w3_omega, w4_omega
     *
     * These values are placed linearly in the proofData, we can extract them with a calldatacopy call
     *
     */
    function generate_nu_challenges(
        TranscriptData memory self,
        Types.ChallengeTranscript memory challenges,
        // uint256 quotient_poly_eval,
        uint256 num_public_inputs
    ) internal pure {
        uint256 p = Bn254Crypto.r_mod;
        bytes32 current_challenge = self.current_challenge;
        uint256 base_v_challenge;
        uint256 updated_v;

        // We want to copy SIXTEEN field elements from calldata into memory to hash
        // But we start by adding the quotient poly evaluation to the hash transcript
        assembly {
            // get a calldata pointer that points to the start of the data we want to copy
            let calldata_ptr := add(calldataload(0x04), 0x24)
            // skip over the public inputs
            calldata_ptr := add(calldata_ptr, mul(num_public_inputs, 0x20))
            // There are NINE G1 group elements added into the transcript in the `beta` round, that we need to skip over
            calldata_ptr := add(calldata_ptr, 0x240) // 9 * 0x40 = 0x240

            let m_ptr := mload(0x40)
            mstore(m_ptr, current_challenge)
            // mstore(add(m_ptr, 0x20), quotient_poly_eval)
            calldatacopy(add(m_ptr, 0x20), calldata_ptr, 0x1e0) // 15 * 0x20 = 0x1e0
            base_v_challenge := keccak256(m_ptr, 0x200) // hash length = 0x200, we include the previous challenge in the hash
            updated_v := mod(base_v_challenge, p)
        }

        // assign the first challenge value
        challenges.v0 = updated_v;

        // for subsequent challenges we iterate 10 times.
        // At each iteration i \in [1, 10] we compute challenges.vi = keccak256(base_v_challenge, byte(i))
        assembly {
            mstore(0x00, base_v_challenge)
            mstore8(0x20, 0x01)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v1 = updated_v;
        assembly {
            mstore8(0x20, 0x02)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v2 = updated_v;
        assembly {
            mstore8(0x20, 0x03)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v3 = updated_v;
        assembly {
            mstore8(0x20, 0x04)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v4 = updated_v;
        assembly {
            mstore8(0x20, 0x05)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v5 = updated_v;
        assembly {
            mstore8(0x20, 0x06)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v6 = updated_v;
        assembly {
            mstore8(0x20, 0x07)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v7 = updated_v;
        assembly {
            mstore8(0x20, 0x08)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v8 = updated_v;
        assembly {
            mstore8(0x20, 0x09)
            updated_v := mod(keccak256(0x00, 0x21), p)
        }
        challenges.v9 = updated_v;

        // update the current challenge when computing the final nu challenge
        bytes32 challenge;
        assembly {
            mstore8(0x20, 0x0a)
            challenge := keccak256(0x00, 0x21)
            updated_v := mod(challenge, p)
        }
        challenges.v10 = updated_v;

        self.current_challenge = challenge;
    }

    function generate_separator_challenge(
        TranscriptData memory self,
        Types.ChallengeTranscript memory challenges,
        Types.G1Point memory PI_Z,
        Types.G1Point memory PI_Z_OMEGA
    ) internal pure {
        bytes32 challenge;
        bytes32 old_challenge = self.current_challenge;
        uint256 p = Bn254Crypto.r_mod;
        uint256 reduced_challenge;
        assembly {
            let m_ptr := mload(0x40)
            mstore(m_ptr, old_challenge)
            mstore(add(m_ptr, 0x20), mload(add(PI_Z, 0x20)))
            mstore(add(m_ptr, 0x40), mload(PI_Z))
            mstore(add(m_ptr, 0x60), mload(add(PI_Z_OMEGA, 0x20)))
            mstore(add(m_ptr, 0x80), mload(PI_Z_OMEGA))
            challenge := keccak256(m_ptr, 0xa0)
            reduced_challenge := mod(challenge, p)
        }
        challenges.u = reduced_challenge;
        self.current_challenge = challenge;
    }
}

    
    
    