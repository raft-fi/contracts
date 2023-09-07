// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Fixed256x18 } from "@tempusfinance/tempus-utils/contracts/math/Fixed256x18.sol";
import { ERC20, ERC20Capped } from "../common/ERC20Capped.sol";
import { ERC20Indexable } from "../ERC20Indexable.sol";
import { PositionManagerDependent } from "../PositionManagerDependent.sol";
import { IInterestRatePositionManager } from "./IInterestRatePositionManager.sol";

contract InterestRateDebtToken is ERC20Indexable {
    // --- Types ---

    using Fixed256x18 for uint256;

    // --- Events ---

    event IndexIncreasePerSecondSet(uint256 indexIncreasePerSecond);

    // --- Immutables ---

    IERC20 immutable collateralToken;

    // --- Variables ---

    uint256 internal storedIndexUpdatedAt;

    uint256 public indexIncreasePerSecond;

    // --- Constructor ---

    constructor(
        address positionManager_,
        string memory name_,
        string memory symbol_,
        IERC20 collateralToken_,
        uint256 cap_,
        uint256 indexIncreasePerSecond_
    )
        ERC20Indexable(positionManager_, name_, symbol_, cap_)
    {
        storedIndexUpdatedAt = block.timestamp;
        collateralToken = collateralToken_;
        setIndexIncreasePerSecond(indexIncreasePerSecond_);
    }

    // --- Functions ---

    function mint(address to, uint256 amount) public virtual override {
        updateIndexAndPayFees();
        super.mint(to, amount);
    }

    function burn(address from, uint256 amount) public virtual override {
        updateIndexAndPayFees();
        super.burn(from, amount);
    }

    function currentIndex() public view virtual override returns (uint256) {
        return storedIndex.mulUp(INDEX_PRECISION + indexIncreasePerSecond * (block.timestamp - storedIndexUpdatedAt));
    }

    function updateIndexAndPayFees() public {
        uint256 currentIndex_ = currentIndex();
        _payFees(currentIndex_);
        storedIndexUpdatedAt = block.timestamp;
        storedIndex = currentIndex_;
        emit IndexUpdated(currentIndex_);
    }

    function setIndex(uint256 backingAmount) public virtual override {
        _payFees(currentIndex());
        storedIndexUpdatedAt = block.timestamp;
        super.setIndex(backingAmount);
    }

    function setIndexIncreasePerSecond(uint256 indexIncreasePerSecond_) public onlyOwner {
        indexIncreasePerSecond = indexIncreasePerSecond_;
        emit IndexIncreasePerSecondSet(indexIncreasePerSecond_);
    }

    function unpaidFees() external view returns (uint256) {
        return _unpaidFees(currentIndex());
    }

    function _unpaidFees(uint256 currentIndex_) private view returns (uint256) {
        return totalSupply().mulDown(currentIndex_ - storedIndex);
    }

    function _payFees(uint256 currentIndex_) private {
        IInterestRatePositionManager(positionManager).mintFees(collateralToken, _unpaidFees(currentIndex_));
    }
}
