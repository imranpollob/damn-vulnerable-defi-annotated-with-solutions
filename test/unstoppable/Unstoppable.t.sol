// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {UnstoppableVault, Owned} from "../../src/unstoppable/UnstoppableVault.sol";
import {UnstoppableMonitor} from "../../src/unstoppable/UnstoppableMonitor.sol";

contract UnstoppableChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    uint256 constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 constant INITIAL_PLAYER_TOKEN_BALANCE = 10e18;

    DamnValuableToken public token;
    UnstoppableVault public vault;
    UnstoppableMonitor public monitorContract;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        // Deploy token and vault
        token = new DamnValuableToken();
        vault = new UnstoppableVault({_token: token, _owner: deployer, _feeRecipient: deployer});

        // Deposit tokens to vault
        token.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT, address(deployer));

        // Fund player's account with initial token balance
        token.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);

        // Deploy monitor contract and grant it vault's ownership
        monitorContract = new UnstoppableMonitor(address(vault));
        vault.transferOwnership(address(monitorContract));

        // Monitor checks it's possible to take a flash loan
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(true);
        monitorContract.checkFlashLoan(100e18);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Check initial token balances
        assertEq(token.balanceOf(address(vault)), TOKENS_IN_VAULT);
        assertEq(token.balanceOf(player), INITIAL_PLAYER_TOKEN_BALANCE);

        // Monitor is owned
        assertEq(monitorContract.owner(), deployer);

        // Check vault properties
        assertEq(address(vault.asset()), address(token));
        assertEq(vault.totalAssets(), TOKENS_IN_VAULT);
        assertEq(vault.totalSupply(), TOKENS_IN_VAULT);
        assertEq(vault.maxFlashLoan(address(token)), TOKENS_IN_VAULT);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT - 1), 0);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT), 50000e18);

        // Vault is owned by monitor contract
        assertEq(vault.owner(), address(monitorContract));

        // Vault is not paused
        assertFalse(vault.paused());

        // Cannot pause the vault
        vm.expectRevert("UNAUTHORIZED");
        vault.setPause(true);

        // Cannot call monitor contract
        vm.expectRevert("UNAUTHORIZED");
        monitorContract.checkFlashLoan(100e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_unstoppable() public checkSolvedByPlayer {
        /**
         * The vulnerability in the UnstoppableVault contract has a critical check in the flashLoan function
         * 
         * if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();
         * 
         * This line of code is intended to ensure that the amount of tokens the vault thinks it has (calculated by converting the totalSupply of shares back into token units) matches the actual token balance (balanceBefore) held by the contract. 
         * 
         * totalSupply represents the total number of shares that have been issued by the vault. These shares are proportional to the amount of the underlying token (asset) deposited by users.
         * 
         * convertToShares(totalSupply) converts the total shares back into the equivalent amount of tokens, based on the current share-to-token conversion rate.
         * 
         * balanceBefore is the actual balance of tokens held by the vault at the time the flash loan is requested.
         * 
         * 
         * Normally, every deposit into the vault results in new shares being minted, and every withdrawal results in shares being burned, ensuring that totalSupply of shares and the actual token balance remain aligned.
         * 
         * However, if tokens are directly transferred to the vault's address without going through the vault's deposit function (i.e., without minting new shares), this alignment is disrupted. The totalAssets() (reflected by balanceBefore) increases due to the additional tokens, but the totalSupply remains unchanged because no new shares were issued for the transferred tokens.
         */
        
        token.transfer(address(vault), 123);
        /**
         * Demonstrates this exploit by directly transferring 123 tokens to the vault. This increases the totalAssets() without affecting the totalSupply, thereby ensuring that convertToShares(totalSupply) will not equal balanceBefore.
         * 
         * When a flash loan request is made after this direct transfer it causes the InvalidBalance revert condition to trigger, thereby failing the flash loan.
         */
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private {
        // Flashloan check must fail
        vm.prank(deployer);
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(false);
        monitorContract.checkFlashLoan(100e18);

        // And now the monitor paused the vault and transferred ownership to deployer
        assertTrue(vault.paused(), "Vault is not paused");
        assertEq(vault.owner(), deployer, "Vault did not change owner");
    }
}
