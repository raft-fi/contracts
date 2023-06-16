// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import { ERC20PermitSignature, PermitHelper } from "@tempusfinance/tempus-utils/contracts/utils/PermitHelper.sol";
import { IERC20Indexable } from "./Interfaces/IERC20Indexable.sol";
import { IPositionManager } from "./Interfaces/IPositionManager.sol";
import { IWETH, IPositionManagerWETH } from "./Interfaces/IPositionManagerWETH.sol";
import { IRToken } from "./Interfaces/IRToken.sol";
import { PositionManagerDependent } from "./PositionManagerDependent.sol";

contract PositionManagerWETH is IPositionManagerWETH, PositionManagerDependent {
    // --- Immutables ---

    IWETH public immutable override wETH;

    IERC20Indexable private immutable _raftDebtToken;

    IRToken private immutable _rToken;

    // --- Constructor ---

    constructor(address positionManager_, IWETH wETH_) PositionManagerDependent(positionManager_) {
        if (address(wETH_) == address(0)) {
            revert WETHAddressCannotBeZero();
        }
        wETH = wETH_;

        (, _raftDebtToken,,,,,,,,) = IPositionManager(positionManager_).collateralInfo(wETH_);
        _rToken = IPositionManager(positionManager_).rToken();
        wETH_.approve(positionManager_, type(uint256).max); // for deposits
    }

    // --- Functions ---

    function managePositionETH(
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        ERC20PermitSignature calldata permitSignature
    )
        external
        payable
        override
    {
        ERC20PermitSignature memory emptySignature;

        if (!isDebtIncrease) {
            if (debtChange == type(uint256).max) {
                debtChange = _raftDebtToken.balanceOf(msg.sender);
            }
            _applyPermit(_rToken, permitSignature);
            _rToken.transferFrom(msg.sender, address(this), debtChange);
        }

        if (isCollateralIncrease && collateralChange > 0) {
            wETH.deposit{ value: msg.value }();
            collateralChange = msg.value;
        }

        (collateralChange, debtChange) = IPositionManager(positionManager).managePosition(
            wETH,
            msg.sender,
            collateralChange,
            isCollateralIncrease,
            debtChange,
            isDebtIncrease,
            maxFeePercentage,
            emptySignature
        );

        if (!isCollateralIncrease && collateralChange > 0) {
            wETH.withdraw(collateralChange);
            (bool success,) = msg.sender.call{ value: collateralChange }("");
            if (!success) {
                revert SendingEtherFailed();
            }
        }

        if (isDebtIncrease) {
            _rToken.transfer(msg.sender, debtChange);
        }

        emit ETHPositionChanged(msg.sender, collateralChange, isCollateralIncrease, debtChange, isDebtIncrease);
    }

    function _applyPermit(IERC20Permit token, ERC20PermitSignature calldata permitSignature) internal {
        if (address(permitSignature.token) == address(token)) {
            PermitHelper.applyPermit(permitSignature, msg.sender, address(this));
        }
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable { }
}
