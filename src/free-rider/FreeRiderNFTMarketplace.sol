// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DamnValuableNFT} from "../DamnValuableNFT.sol";

contract FreeRiderNFTMarketplace is ReentrancyGuard {
    using Address for address payable;

    DamnValuableNFT public token;
    uint256 public offersCount;

    // tokenId -> price
    mapping(uint256 => uint256) private offers;

    event NFTOffered(address indexed offerer, uint256 tokenId, uint256 price);
    event NFTBought(address indexed buyer, uint256 tokenId, uint256 price);

    error InvalidPricesAmount();
    error InvalidTokensAmount();
    error InvalidPrice();
    error CallerNotOwner(uint256 tokenId);
    error InvalidApproval();
    error TokenNotOffered(uint256 tokenId);
    error InsufficientPayment();

    constructor(uint256 amount) payable {
        DamnValuableNFT _token = new DamnValuableNFT();
        _token.renounceOwnership();
        // mints a specified number of NFTs (6 in this challenge) to the deployer 
        for (uint256 i = 0; i < amount;) {
            _token.safeMint(msg.sender);
            unchecked {
                ++i;
            }
        }
        token = _token;
    }

    // The owner lists NFTs for sale by providing token IDs and corresponding prices
    function offerMany(uint256[] calldata tokenIds, uint256[] calldata prices) external nonReentrant {
        uint256 amount = tokenIds.length;
        if (amount == 0) {
            revert InvalidTokensAmount();
        }

        if (amount != prices.length) {
            revert InvalidPricesAmount();
        }

        for (uint256 i = 0; i < amount; ++i) {
            unchecked {
                _offerOne(tokenIds[i], prices[i]);
            }
        }
    }

    function _offerOne(uint256 tokenId, uint256 price) private {
        DamnValuableNFT _token = token; // gas savings

        if (price == 0) {
            revert InvalidPrice();
        }

        if (msg.sender != _token.ownerOf(tokenId)) {
            revert CallerNotOwner(tokenId);
        }

        // checks the NFT is approved for transfer by the marketplace
        if (_token.getApproved(tokenId) != address(this) && !_token.isApprovedForAll(msg.sender, address(this))) {
            revert InvalidApproval();
        }

        // sets the price in the offers mapping
        offers[tokenId] = price;

        assembly {
            // gas savings
            // increments an offersCount
            sstore(0x02, add(sload(0x02), 0x01))
        }

        emit NFTOffered(msg.sender, tokenId, price);
    }

    // Allows a buyer to purchase multiple NFTs in one transaction by sending ETH
    function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            unchecked {
                _buyOne(tokenIds[i]);
            }
        }
    }

    function _buyOne(uint256 tokenId) private {
        uint256 priceToPay = offers[tokenId];
        if (priceToPay == 0) {
            revert TokenNotOffered(tokenId);
        }

        if (msg.value < priceToPay) {
            revert InsufficientPayment();
        }

        --offersCount;

        // transfer from seller to buyer
        DamnValuableNFT _token = token; // cache for gas savings
        _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller using cached token
        payable(_token.ownerOf(tokenId)).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }

    receive() external payable {}
}

/**
The critical vulnerability lies in the _buyOne function of the FreeRiderNFTMarketplace contract, specifically in the payment logic:

Issue 1: Incorrect Payment Recipient:
- After transferring the NFT to the buyer (msg.sender) via safeTransferFrom, the function calls _token.ownerOf(tokenId) to determine the payment recipient.
- Since the NFT has already been transferred, _token.ownerOf(tokenId) returns the buyer’s address (msg.sender), not the original seller.
- As a result, the marketplace sends the payment (15 ETH per NFT) to the buyer instead of the seller (the deployer).

Issue 2: Insufficient Payment Check:
- The check if (msg.value < priceToPay) ensures that the total ETH sent with the buyMany call (msg.value) is at least the price of each individual NFT (15 ETH).
- However, it does not verify that msg.value covers the total cost of all NFTs being purchased. When buying multiple NFTs, msg.value is reused in each _buyOne call without being reduced or accumulated.
- Thus, sending just 15 ETH allows the purchase of all 6 NFTs (which should cost 90 ETH), because 15 ETH satisfies the check for each individual NFT.

Combined Effect:
- By calling buyMany with token IDs [0, 1, 2, 3, 4, 5] and msg.value = 15 ETH:
    - The buyer pays 15 ETH once to the marketplace.
    - For each of the 6 NFTs, the marketplace sends 15 ETH to the buyer (the new owner), totaling 90 ETH.
-Net result: The buyer pays 15 ETH and receives 90 ETH back, gaining a net profit of 75 ETH, while acquiring all 6 NFTs.

This bug effectively drains the marketplace’s ETH balance (initially 90 ETH) and allows the buyer to acquire the NFTs for a fraction of their intended cost.
 */