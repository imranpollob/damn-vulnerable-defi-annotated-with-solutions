// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib, ERC4626, ERC20} from "solmate/tokens/ERC4626.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC3156FlashBorrower, IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156.sol";

/**
 * An ERC4626-compliant tokenized vault offering flashloans for a fee.
 * An owner can pause the contract and execute arbitrary changes.
 * IERC3156FlashLender for flash loan functionality, 
 * Owned for ownership management
 * ERC4626 for tokenized vault operations 
 * Pausable for pausing and unpausing contract functions in case of emergencies
 */
contract UnstoppableVault is IERC3156FlashLender, ReentrancyGuard, Owned, ERC4626, Pausable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    // A constant used to calculate the flash loan fee.
    uint256 public constant FEE_FACTOR = 0.05 ether;
    // after this period, special fee logic applies
    uint64 public constant GRACE_PERIOD = 30 days;
    // The timestamp marking the end of the grace period.
    uint64 public immutable end = uint64(block.timestamp) + GRACE_PERIOD;
    // The address that receives the fees collected from flash loans.
    address public feeRecipient;

    error InvalidAmount(uint256 amount);
    error InvalidBalance();
    error CallbackFailed();
    error UnsupportedCurrency();

    event FeeRecipientUpdated(address indexed newFeeRecipient);

    constructor(ERC20 _token, address _owner, address _feeRecipient)
        ERC4626(_token, "Too Damn Valuable Token", "tDVT")
        Owned(_owner)
    {
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
    // Returns the maximum amount available for a flash loan for a specific token
    function maxFlashLoan(address _token) public view nonReadReentrant returns (uint256) {
        // asset is inherited from the ERC4626 tokenized vault standard, which is designed to manage a single type of token.
        if (address(asset) != _token) {
            return 0;
        }

        return totalAssets();
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
    // Computes the fee for a flash loan
    function flashFee(address _token, uint256 _amount) public view returns (uint256 fee) {
        if (address(asset) != _token) {
            revert UnsupportedCurrency();
        }

        //  During the grace period and for amounts less than the available maximum, the fee is zero; otherwise, it is calculated based on the FEE_FACTOR.
        if (block.timestamp < end && _amount < maxFlashLoan(_token)) {
            return 0;
        } else {
            return _amount.mulWadUp(FEE_FACTOR);
        }
    }

    /**
     * @inheritdoc ERC4626
     */
    function totalAssets() public view override nonReadReentrant returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @inheritdoc IERC3156FlashLender
     */
    // Facilitates the flash loan process.
    // It follows ERC3156 standard that outlines a protocol for flash loan operations, allowing loans of ERC20 tokens to be issued and repaid within a single transaction.
    function flashLoan(IERC3156FlashBorrower receiver, address _token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        if (amount == 0) revert InvalidAmount(0); // fail early
        if (address(asset) != _token) revert UnsupportedCurrency(); // enforce ERC3156 requirement
        uint256 balanceBefore = totalAssets();
        // It checks if the internal vault accounting (conversion of the total token supply to shares using convertToShares(totalSupply)) matches the actual token balance (balanceBefore). 
        if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance(); // enforce ERC4626 requirement

        // transfer tokens out + execute callback on receiver
        ERC20(_token).safeTransfer(address(receiver), amount);

        // callback must return magic value, otherwise assume it failed
        uint256 fee = flashFee(_token, amount);
        // The borrower's callback method must return a specific "magic value" (keccak256("IERC3156FlashBorrower.onFlashLoan")) to confirm successful handling of the flash loan. If this value is not returned correctly, the function reverts with a CallbackFailed error. This mechanism ensures that the borrower adheres to the flash loan protocol correctly and securely.
        if (
            receiver.onFlashLoan(msg.sender, address(asset), amount, fee, data)
                != keccak256("IERC3156FlashBorrower.onFlashLoan")
        ) {
            revert CallbackFailed();
        }

        // pull amount + fee from receiver, then pay the fee to the recipient
        // Assuming the callback is successful, the borrower is then required to return the loan amount plus a fee. The fee is calculated based on the flashFee function, which might vary depending on the contract's fee policy.
        ERC20(_token).safeTransferFrom(address(receiver), address(this), amount + fee);
        ERC20(_token).safeTransfer(feeRecipient, fee);

        return true;
    }

    /**
     * @inheritdoc ERC4626
     */
    function beforeWithdraw(uint256 assets, uint256 shares) internal override nonReentrant {}

    /**
     * @inheritdoc ERC4626
     */
    function afterDeposit(uint256 assets, uint256 shares) internal override nonReentrant whenNotPaused {}

    // Allows the owner to update the address that receives fees from flash loans.
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient != address(this)) {
            feeRecipient = _feeRecipient;
            emit FeeRecipientUpdated(_feeRecipient);
        }
    }

    // Allow owner to execute arbitrary changes when paused
    function execute(address target, bytes memory data) external onlyOwner whenPaused {
        (bool success,) = target.delegatecall(data);
        require(success);
    }

    // Allow owner pausing/unpausing this contract
    function setPause(bool flag) external onlyOwner {
        if (flag) _pause();
        else _unpause();
    }
}
