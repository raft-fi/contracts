// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { ERC20PermitSignature } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IRToken } from "../Interfaces/IRToken.sol";
import { IPositionManager } from "../Interfaces/IPositionManager.sol";
import { IPSM } from "./IPSM.sol";
import { IPSMFeeCalculator } from "./IPSMFeeCalculator.sol";
import { ILock } from "./ILock.sol";

/// @dev Base implementation of Peg Stability Module.
/// Handles basic reserve token transfers as well as minting R.
/// PSM is also ERC20 that should be added to PositionManager as a collateral with 100% min CR.
/// PSM ERC20 should have constant price feed returning value of 1e18.
/// Min CR of 100% and price of 1e18 menas there cannot be liquidations of such collateral.
/// On top of this, `SplitLiquidationCollateral.split` reverts to make sure no liquidations are possible.
abstract contract BasePSM is IPSM, ERC20, Ownable2Step {
    using SafeERC20 for IERC20;
    using Fixed256x18 for uint256;

    IERC20 public immutable override reserveToken;
    IRToken public immutable override rToken;
    IPositionManager public immutable override positionManager;
    IPSMFeeCalculator public override feeCalculator;

    constructor(
        IERC20 reserveToken_,
        IRToken rToken_,
        string memory name_,
        string memory symbol_,
        IPSMFeeCalculator feeCalculator_
    )
        ERC20(name_, symbol_)
    {
        if (address(reserveToken_) == address(0)) {
            revert ZeroInputProvided();
        }

        reserveToken = reserveToken_;
        rToken = rToken_;
        positionManager = IPositionManager(rToken_.positionManager());

        setFeeCalculator(feeCalculator_);

        _approve(address(this), address(positionManager), type(uint256).max);
    }

    modifier unlockCall() {
        ILock lockContract = ILock(address(positionManager.priceFeed(IERC20(this))));
        lockContract.unlock();
        _;
        lockContract.lock();
    }

    function buyR(uint256 reserveAmount, uint256 minReturn) external returns (uint256 rAmountOut) {
        if (reserveAmount == 0 || minReturn == 0) {
            revert ZeroInputProvided();
        }

        reserveToken.safeTransferFrom(msg.sender, address(this), reserveAmount);
        _depositReserveToken(reserveAmount);

        rAmountOut = reserveAmount - feeCalculator.calculateFee(reserveAmount, true);
        if (rAmountOut < minReturn) {
            revert ReturnLessThanMinimum(rAmountOut, minReturn);
        }
        _mintR(msg.sender, rAmountOut);
    }

    function buyReserveToken(uint256 rAmount, uint256 minReturn) external returns (uint256 reserveAmountOut) {
        if (rAmount == 0 || minReturn == 0) {
            revert ZeroInputProvided();
        }

        _burnR(msg.sender, rAmount);

        reserveAmountOut = rAmount - feeCalculator.calculateFee(rAmount, false);
        if (reserveAmountOut < minReturn) {
            revert ReturnLessThanMinimum(reserveAmountOut, minReturn);
        }
        _withdrawReserveToken(reserveAmountOut);
        reserveToken.safeTransfer(msg.sender, reserveAmountOut);
    }

    function withdrawReserve(address to, uint256 amount) external override onlyOwner {
        if (to == address(0) && amount == 0) {
            revert ZeroInputProvided();
        }
        _withdrawReserveToken(amount);
        reserveToken.safeTransfer(to, amount);
    }

    function recoverTokens(IERC20 token, address to, uint256 amount) external override onlyOwner {
        token.safeTransfer(to, amount);
        emit TokensRecovered(token, to, amount);
    }

    function setFeeCalculator(IPSMFeeCalculator newFeeCalculator) public override onlyOwner {
        if (address(newFeeCalculator) == address(0)) {
            revert ZeroInputProvided();
        }
        feeCalculator = newFeeCalculator;
        emit FeeCalculatorSet(newFeeCalculator);
    }

    function _mintR(address to, uint256 amount) internal unlockCall {
        _mint(address(this), amount);
        ERC20PermitSignature memory emptySignature;
        positionManager.managePosition(
            IERC20(address(this)),
            address(this),
            amount,
            true, // collateral increase
            amount,
            true, // debt increase
            1e18, // 100%
            emptySignature
        );
        rToken.transfer(to, amount);
    }

    function _burnR(address from, uint256 amount) internal unlockCall {
        rToken.transferFrom(from, address(this), amount);
        ERC20PermitSignature memory emptySignature;
        positionManager.managePosition(
            IERC20(address(this)),
            address(this),
            amount,
            false, // collateral decrease
            amount,
            false, // debt decrease
            1e18, // 100%
            emptySignature
        );
        _burn(address(this), amount);
    }

    /// @dev Used by concrete implementations of PSM to withdraw reserves from yield bearing versions.
    /// For example in case of DAI reserve, reserves are withdrawn from DAI savings rate.
    /// @param amount Number of reserve tokens to withdraw.
    function _withdrawReserveToken(uint256 amount) internal virtual;

    /// @dev Used by concrete implementations of PSM to deposit reserves to yield bearing versions.
    /// For example in case of DAI reserve, reserves are deposited into DAI savings rate.
    /// @param amount Number of reserve tokens to deposit.
    function _depositReserveToken(uint256 amount) internal virtual;
}
