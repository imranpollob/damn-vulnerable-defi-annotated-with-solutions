// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

// Tracks the state of token distributions.
struct Distribution {
    uint256 remaining; // The remaining amount of tokens to distribute.
    uint256 nextBatchNumber; // The next batch number for distribution.
    mapping(uint256 batchNumber => bytes32 root) roots; // A mapping of batch numbers to Merkle roots.
    mapping(address claimer => mapping(uint256 word => uint256 bits)) claims; // A nested mapping to track which addresses have claimed rewards for specific batches.
}

// Represents a single claim by a beneficiary.
struct Claim {
    uint256 batchNumber;
    uint256 amount;
    uint256 tokenIndex; // The index of the token in the inputTokens array.
    bytes32[] proof; // The Merkle proof for the claim.
}

/**
 * An efficient token distributor contract based on Merkle proofs and bitmaps
 */
contract TheRewarderDistributor {
    using BitMaps for BitMaps.BitMap;

    address public immutable owner = msg.sender;

    mapping(IERC20 token => Distribution) public distributions; // A mapping of tokens (e.g., DVT, WETH)

    error StillDistributing();
    error InvalidRoot();
    error AlreadyClaimed();
    error InvalidProof();
    error NotEnoughTokensToDistribute();

    event NewDistribution(IERC20 token, uint256 batchNumber, bytes32 newMerkleRoot, uint256 totalAmount);

    function getRemaining(address token) external view returns (uint256) {
        return distributions[IERC20(token)].remaining;
    }

    function getNextBatchNumber(address token) external view returns (uint256) {
        return distributions[IERC20(token)].nextBatchNumber;
    }

    function getRoot(address token, uint256 batchNumber) external view returns (bytes32) {
        return distributions[IERC20(token)].roots[batchNumber];
    }

    function createDistribution(IERC20 token, bytes32 newRoot, uint256 amount) external {
        // Validates the amount and newRoot.
        if (amount == 0) revert NotEnoughTokensToDistribute();
        if (newRoot == bytes32(0)) revert InvalidRoot();
        if (distributions[token].remaining != 0) revert StillDistributing();

        // Initializes the Distribution struct for the token.
        distributions[token].remaining = amount;

        uint256 batchNumber = distributions[token].nextBatchNumber;
        distributions[token].roots[batchNumber] = newRoot;
        distributions[token].nextBatchNumber++;

        // Transfers the tokens from the owner to the contract.
        SafeTransferLib.safeTransferFrom(address(token), msg.sender, address(this), amount);

        emit NewDistribution(token, batchNumber, newRoot, amount);
    }

    // Allows the owner to recover any remaining tokens after a distribution is complete.
    function clean(IERC20[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            if (distributions[token].remaining == 0) {
                token.transfer(owner, token.balanceOf(address(this)));
            }
        }
    }

    /**
     * Allow claiming rewards of multiple tokens in a single transaction
     * 
     * @param inputClaims An array of Claim structs, each representing a claim for a specific token and batch.
     * @param inputTokens An array of tokens (e.g., DVT and WETH) that correspond to the claims.
     */
    function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
        Claim memory inputClaim;
        IERC20 token;
        uint256 bitsSet; // accumulator for bitmap
        uint256 amount; // accumulator for total amount

        for (uint256 i = 0; i < inputClaims.length; i++) {
            inputClaim = inputClaims[i];

            // Calculate word and bit positions for the bitmap
            uint256 wordPosition = inputClaim.batchNumber / 256;
            uint256 bitPosition = inputClaim.batchNumber % 256;

            if (token != inputTokens[inputClaim.tokenIndex]) {
                // If the claim is for a new token (different from the previous one)
                if (address(token) != address(0)) {
                    // Marks the previous token's claims as processed using _setClaimed
                    if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
                }

                // Reset for the new token
                token = inputTokens[inputClaim.tokenIndex];
                bitsSet = 1 << bitPosition; // set bit at given position
                amount = inputClaim.amount;
            } else {
                // Accumulate bits and amount for the same token
                bitsSet = bitsSet | 1 << bitPosition;
                amount += inputClaim.amount;
            }

            // For the last claim, process the current token's claims
            if (i == inputClaims.length - 1) {
                if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
            }

            // Constructs a Merkle leaf using the beneficiary's address (msg.sender) and the claim amount.
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, inputClaim.amount));
            // Verifies the provided Merkle proof against the stored Merkle root for the batch.
            bytes32 root = distributions[token].roots[inputClaim.batchNumber];
            // Verify the Merkle proof
            if (!MerkleProof.verify(inputClaim.proof, root, leaf)) revert InvalidProof();

            // Transfer the claimed tokens to the beneficiary
            inputTokens[inputClaim.tokenIndex].transfer(msg.sender, inputClaim.amount);
        }
    }
    /**
     * if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
     * 
     * This line is responsible for updating the bitmap and marking claims as processed. 
     * However, the issue is when and how often this check is performed.
     * 
     * claimRewards accumulates multiple claims for the same token and batch before calling _setClaimed.
     * For example, if there are 10 identical claims for the same token and batch, the function will:
     * - Accumulate the bitsSet and amount for all 10 claims.
     * - Only call _setClaimed once after processing all 10 claims.
     * 
     * Because this check is only performed after accumulating all claims, 
     * the function does not detect that the same claim is being processed multiple times.
     * 
     * As a result, the contract processes all claims as if they are valid, sums their amounts, and transfers the total to the beneficiary.
     * This allows an attacker to claim the same reward multiple times in a single transaction.
     */

    function _setClaimed(IERC20 token, uint256 amount, uint256 wordPosition, uint256 newBits) private returns (bool) {
        uint256 currentWord = distributions[token].claims[msg.sender][wordPosition];
        if ((currentWord & newBits) != 0) return false;

        // update state
        distributions[token].claims[msg.sender][wordPosition] = currentWord | newBits;
        distributions[token].remaining -= amount;

        return true;
    }
}
