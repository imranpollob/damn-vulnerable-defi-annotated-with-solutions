// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TrustfulOracle} from "./TrustfulOracle.sol";
import {DamnValuableNFT} from "../DamnValuableNFT.sol";

contract Exchange is ReentrancyGuard {
    using Address for address payable;

    // Instance of the NFT contract
    DamnValuableNFT public immutable token;
    // Instance of the Price Oracle contract
    TrustfulOracle public immutable oracle;

    error InvalidPayment();
    error SellerNotOwner(uint256 id);
    error TransferNotApproved();
    error NotEnoughFunds();

    event TokenBought(address indexed buyer, uint256 tokenId, uint256 price);
    event TokenSold(address indexed seller, uint256 tokenId, uint256 price);

    constructor(address _oracle) payable {
        token = new DamnValuableNFT();
        token.renounceOwnership();
        oracle = TrustfulOracle(_oracle);
    }

    // Allows users to buy NFTs. It fetches the price from the oracle and mints a new NFT if sufficient payment is provided.
    function buyOne() external payable nonReentrant returns (uint256 id) {
        if (msg.value == 0) {
            revert InvalidPayment();
        }

        // Price should be in [wei / NFT]
        // Fetches median price from the oracle
        uint256 price = oracle.getMedianPrice(token.symbol());

        // Reverts if sent ETH is less than the price
        if (msg.value < price) {
            revert InvalidPayment();
        }

        // Mints a new NFT to the buyer
        id = token.safeMint(msg.sender);

        unchecked {
            // Refunds any excess ETH paid
            payable(msg.sender).sendValue(msg.value - price);
        }

        emit TokenBought(msg.sender, id, price);
    }

    // Allows users to sell NFTs back to the exchange. It fetches the price from the oracle, checks for approval and exchange balance, transfers the NFT to the exchange, burns the NFT, and pays the seller.
    function sellOne(uint256 id) external nonReentrant {
        // Reverts if seller is not the NFT owner
        if (msg.sender != token.ownerOf(id)) {
            revert SellerNotOwner(id);
        }

        // Reverts if Exchange is not approved to transfer NFT
        if (token.getApproved(id) != address(this)) {
            revert TransferNotApproved();
        }

        // Price should be in [wei / NFT]
        // Fetches median price from the oracle
        uint256 price = oracle.getMedianPrice(token.symbol());

        // Reverts if Exchange doesn't have enough ETH to buy back
        if (address(this).balance < price) {
            revert NotEnoughFunds();
        }

        // Transfers NFT to the Exchange
        token.transferFrom(msg.sender, address(this), id);
        // Burns the NFT after purchase by Exchange
        token.burn(id);

        // Sends ETH to the seller
        payable(msg.sender).sendValue(price);

        emit TokenSold(msg.sender, id, price);
    }

    // Allows Exchange to receive ETH
    receive() external payable {}
}
