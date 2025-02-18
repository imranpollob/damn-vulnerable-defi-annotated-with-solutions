// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

contract SideEntranceLenderPool {
    mapping(address => uint256) public balances;

    error RepayFailed();

    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address indexed who, uint256 amount);

    function deposit() external payable {
        // The addition is done in an unchecked block, meaning it won’t revert on overflow
        unchecked {
            balances[msg.sender] += msg.value;
        }
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw() external {
        // Retrieves the caller’s deposited balance.
        uint256 amount = balances[msg.sender];
        // Resets their balance to zero (using delete).
        delete balances[msg.sender];
        emit Withdraw(msg.sender, amount);

        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;
        // Call the execute() function on the caller 
        // (who must implement the IFlashLoanEtherReceiver interface), 
        // sending the requested amount of ETH.
        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        if (address(this).balance < balanceBefore) {
            revert RepayFailed();
        }
    }
}
