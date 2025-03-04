// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

contract PuppetPool is ReentrancyGuard {
    using Address for address payable;

    // users must deposit twice the value of the tokens they borrow.
    uint256 public constant DEPOSIT_FACTOR = 2;
    // Address of the Uniswap V1 pair (ETH/token), used as a price oracle.
    address public immutable uniswapPair;
    DamnValuableToken public immutable token;
    // Tracks ETH deposited by each user.
    mapping(address => uint256) public deposits;

    error NotEnoughCollateral();
    error TransferFailed();

    event Borrowed(address indexed account, address recipient, uint256 depositRequired, uint256 borrowAmount);

    constructor(address tokenAddress, address uniswapPairAddress) {
        token = DamnValuableToken(tokenAddress);
        uniswapPair = uniswapPairAddress;
    }

    // Allows borrowing tokens by first depositing two times their value in ETH
    function borrow(uint256 amount, address recipient) external payable nonReentrant {
        // The required deposit is calculated
        uint256 depositRequired = calculateDepositRequired(amount);

        // If the provided ETH is less than required, the transaction reverts
        if (msg.value < depositRequired) {
            revert NotEnoughCollateral();
        }

        // If extra ETH is sent, the surplus is refunded to the sender.
        if (msg.value > depositRequired) {
            unchecked {
                payable(msg.sender).sendValue(msg.value - depositRequired);
            }
        }

        // The required deposit amount is recorded in the deposits mapping for the sender.
        unchecked {
            deposits[msg.sender] += depositRequired;
        }

        // Fails if the pool doesn't have enough tokens in liquidity
        if (!token.transfer(recipient, amount)) {
            revert TransferFailed();
        }

        emit Borrowed(msg.sender, recipient, depositRequired, amount);
    }

    function calculateDepositRequired(uint256 amount) public view returns (uint256) {
        // Calculates the deposit required by multiplying the borrowed amount with the oracle price (obtained from _computeOraclePrice) and the deposit factor. 
        // The result is scaled down by 10^18 to account for Solidity’s integer arithmetic.
        return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18;
    }

    function _computeOraclePrice() private view returns (uint256) {
        // calculates the price of the token in wei according to Uniswap pair
        // Relies on the Uniswap pair’s current reserves as a spot price oracle.
        return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
    }
}
