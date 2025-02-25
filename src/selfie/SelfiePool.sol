// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SimpleGovernance} from "./SimpleGovernance.sol";

// This contract is the lending pool. It allows users to take flash loans of DVT tokens and has a governance-controlled emergency exit function.
contract SelfiePool is IERC3156FlashLender, ReentrancyGuard {
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    IERC20 public immutable token;
    SimpleGovernance public immutable governance;

    error RepayFailed();
    error CallerNotGovernance();
    error UnsupportedCurrency();
    error CallbackFailed();

    event EmergencyExit(address indexed receiver, uint256 amount);

    // Ensures that only the governance contract can call this function.
    modifier onlyGovernance() {
        if (msg.sender != address(governance)) {
            revert CallerNotGovernance();
        }
        _;
    }

    // Constructor to initialize the token and governance contract.
    constructor(IERC20 _token, SimpleGovernance _governance) {
        token = _token;
        governance = _governance;
    }

    // Returns the maximum amount of tokens available for a flash loan of the specified token.
    function maxFlashLoan(address _token) external view returns (uint256) {
        if (address(token) == _token) {
            return token.balanceOf(address(this));
        }
        return 0;
    }

    // Returns the fee for a flash loan. In this case, it's always 0.
    function flashFee(address _token, uint256) external view returns (uint256) {
        if (address(token) != _token) {
            revert UnsupportedCurrency();
        }
        return 0;
    }

    function flashLoan(IERC3156FlashBorrower _receiver, address _token, uint256 _amount, bytes calldata _data)
        external
        nonReentrant
        returns (bool)
    {
        // checks if the requested token is the pool's token.
        if (_token != address(token)) {
            revert UnsupportedCurrency();
        }

        // Transfers the requested _amount of tokens to the _receiver.
        token.transfer(address(_receiver), _amount);

        // Calls the onFlashLoan function on the _receiver contract (this is the callback).
        if (_receiver.onFlashLoan(msg.sender, _token, _amount, 0, _data) != CALLBACK_SUCCESS) {
            revert CallbackFailed();
        }

        // After the callback, it attempts to receive the borrowed amount back from the _receiver using token.transferFrom.
        if (!token.transferFrom(address(_receiver), address(this), _amount)) {
            revert RepayFailed();
        }

        return true;
    }

    // This function is designed to allow the governance to withdraw all tokens from the pool to a specified receiver
    // Only the governance contract can call this function
    function emergencyExit(address receiver) external onlyGovernance {
        uint256 amount = token.balanceOf(address(this));
        token.transfer(receiver, amount);

        emit EmergencyExit(receiver, amount);
    }
}
