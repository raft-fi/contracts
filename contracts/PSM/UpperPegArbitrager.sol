// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC3156FlashBorrower } from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import { IERC3156FlashLender } from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OneInchV5AMM } from "../AMMs/OneInchV5AMM.sol";
import { IPSM } from "./IPSM.sol";
import { IPSMFeeCalculator } from "./IPSMFeeCalculator.sol";
import { IUpperPegArbitrager } from "./IUpperPegArbitrager.sol";

contract UpperPegArbitrager is IUpperPegArbitrager, IERC3156FlashBorrower, OneInchV5AMM, Ownable2Step {
    using SafeERC20 for IERC20;

    enum Action {
        NORMAL,
        OTHER
    }

    IERC3156FlashLender public override lender;
    IERC20 public override borrowToken;
    IPSM public override psm;
    IPSMFeeCalculator public override feeCalculator;

    bytes private _dataForOneInchSwap;

    constructor(
        IERC3156FlashLender lender_,
        IERC20 borrowToken_,
        IPSM psm_,
        address _aggregationRouter
    )
        OneInchV5AMM(_aggregationRouter)
    {
        if (address(lender_) == address(0)) {
            revert ZeroInputProvided();
        }
        if (address(borrowToken_) == address(0)) {
            revert ZeroInputProvided();
        }
        if (address(psm_) == address(0)) {
            revert ZeroInputProvided();
        }

        lender = lender_;
        borrowToken = borrowToken_;
        psm = psm_;
        feeCalculator = psm.feeCalculator();

        borrowToken_.approve(address(psm), type(uint256).max);
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256,
        bytes calldata data
    )
        external
        override
        returns (bytes32)
    {
        if (msg.sender != address(lender)) {
            revert UntrustedLender(msg.sender);
        }
        if (initiator != address(this)) {
            revert UntrustedLoanInitiator(initiator);
        }

        (Action action) = abi.decode(data, (Action));
        if (action == Action.NORMAL) {
            if (IERC20(token).balanceOf(address(this)) < amount) {
                revert InsufficientBalanceAfterFlashLoan();
            }

            // Buy R from PSM
            _buyR(amount);

            // OneInch swap R -> DAI
            _executeSwap(IERC20(psm.rToken()), IERC20(psm.rToken()).balanceOf(address(this)), 0, _dataForOneInchSwap);
        } else {
            revert ActionNotSupported();
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @dev Initiate a flash loan
    function flashBorrow(uint256 amount, bytes memory extraData) external override {
        _dataForOneInchSwap = extraData;
        bytes memory data = abi.encode(Action.NORMAL);
        uint256 _allowance = borrowToken.allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(address(borrowToken), amount);
        uint256 _repayment = amount + _fee;
        borrowToken.approve(address(lender), _allowance + _repayment);
        lender.flashLoan(this, address(borrowToken), amount, data);

        emit FlashBorrowed(borrowToken, amount, _fee);
    }

    function rescueTokens(IERC20 token, address to) external override onlyOwner {
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);

        emit TokensRescued(token, to, amount);
    }

    function _buyR(uint256 amount) internal {
        uint256 fee = feeCalculator.calculateFee(amount, true);
        psm.buyR(amount, amount - fee);
    }
}
