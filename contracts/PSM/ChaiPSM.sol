// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRToken } from "../Interfaces/IRToken.sol";
import { IChai } from "./IChai.sol";
import { BasePSM } from "./BasePSM.sol";
import { IPSMFeeCalculator } from "./IPSMFeeCalculator.sol";

/// @dev Implementation of CHAI peg stability module for R.
/// Reserve token is DAI, and all of it is deposited automatically to CHAI.
contract ChaiPSM is BasePSM {
    /// @dev Address of the chai token.
    IChai public immutable chai;

    constructor(
        IERC20 reserveToken_,
        IRToken rToken_,
        IPSMFeeCalculator feeCalculator_,
        IChai chai_
    )
        BasePSM(reserveToken_, rToken_, "R CHAI PSM", "R/CHAI-PSM", feeCalculator_)
    {
        chai = chai_;
        reserveToken_.approve(address(chai_), type(uint256).max);
    }

    function _withdrawReserveToken(uint256 amount) internal virtual override {
        chai.draw(address(this), amount);
    }

    function _depositReserveToken(uint256 amount) internal virtual override {
        chai.join(address(this), amount);
    }
}
