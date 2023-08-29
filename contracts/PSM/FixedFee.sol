// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { IPriceFeed } from "../Interfaces/IPriceFeed.sol";
import { IPSMFeeCalculator } from "./IPSMFeeCalculator.sol";

/// @dev Constant fee calculator for PSM.
contract PSMFixedFee is IPSMFeeCalculator, Ownable2Step {
    using Fixed256x18 for uint256;

    /// @dev Fees are set by the owner.
    /// @param buyRFee_ Fee percentage for buying R.
    /// @param buyReserveFee_ Fee percentage for buying reserve.
    event FeesSet(uint256 buyRFee_, uint256 buyReserveFee_);

    /// @dev Price feed contract address was set.
    /// @param priceFeed_ Address of the price feed contract.
    event PriceFeedSet(IPriceFeed priceFeed_);

    /// @dev Price of reserve considered as lowest acceptable price at which trading is allowed.
    /// @param reserveDepegThreshold_ Threshold of the reserve price to consider it depegged.
    event ReserveDepegThresholdSet(uint256 reserveDepegThreshold_);

    /// @dev Thrown in case of setting invalid fee percentage.
    error InvalidFee();

    /// @dev Thrown in case of providing zero address as input.
    error ZeroAddressProvided();

    /// @dev Thrown in case of action is disabled because of reserve depeg.
    /// @param currentReservePrice The current price of reserve found in oracle.
    error DisabledBecauseOfReserveDepeg(uint256 currentReservePrice);

    /// @dev Fee percentage for buying R from PSM.
    uint256 public buyRFee;

    /// @dev Fee percentage for buying reserve token from PSM.
    uint256 public buyReserveFee;

    /// @dev Address of the price feed contract.
    IPriceFeed public priceFeed;

    /// @dev Price of reserve considered as lowest acceptable price at which trading is allowed.
    uint256 public reserveDepegThreshold;

    constructor(uint256 buyRFee_, uint256 buyReserveFee_, IPriceFeed priceFeed_, uint256 reserveDepegThreshold_) {
        setFees(buyRFee_, buyReserveFee_);
        setPriceFeed(priceFeed_);
        setReserveDepegThreshold(reserveDepegThreshold_);
    }

    function calculateFee(uint256 amount, bool isBuyingR) external override returns (uint256 feeAmount) {
        if (isBuyingR) {
            (uint256 currentReservePrice,) = priceFeed.fetchPrice();
            if (currentReservePrice < reserveDepegThreshold) {
                revert DisabledBecauseOfReserveDepeg(currentReservePrice);
            }
            return amount.mulUp(buyRFee);
        }
        return amount.mulUp(buyReserveFee);
    }

    /// @dev Set fees for buying R and reserve token. Callable only by contract owner.
    /// @param buyRFee_ Fee percentage for buying R.
    /// @param buyReserveFee_ Fee percentage for buying reserve.
    function setFees(uint256 buyRFee_, uint256 buyReserveFee_) public onlyOwner {
        if (buyRFee_ > Fixed256x18.ONE || buyReserveFee_ > Fixed256x18.ONE) {
            revert InvalidFee();
        }
        buyRFee = buyRFee_;
        buyReserveFee = buyReserveFee_;
        emit FeesSet(buyRFee_, buyReserveFee_);
    }

    /// @dev Set new price feed contract address. Callable only by contract owner.
    /// @param priceFeed_ Address of the price feed contract.
    function setPriceFeed(IPriceFeed priceFeed_) public onlyOwner {
        if (address(priceFeed_) == address(0)) {
            revert ZeroAddressProvided();
        }
        priceFeed = priceFeed_;
        emit PriceFeedSet(priceFeed_);
    }

    /// @dev Set new price threshold for reserve. Callable only by contract owner.
    /// @param reserveDepegThreshold_ Threshold of the reserve price to consider it depegged.
    function setReserveDepegThreshold(uint256 reserveDepegThreshold_) public onlyOwner {
        reserveDepegThreshold = reserveDepegThreshold_;
        emit ReserveDepegThresholdSet(reserveDepegThreshold_);
    }
}
