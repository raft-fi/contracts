// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Interfaces/IPositionManager.sol";
import "./Interfaces/ISortedPositions.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/CheckContract.sol";

contract HintHelpers is LiquityBase, Ownable2Step, CheckContract {
    string constant public NAME = "HintHelpers";

    ISortedPositions public sortedPositions;
    IPositionManager public positionManager;

    // --- Events ---

    event SortedPositionsAddressChanged(address _sortedPositionsAddress);
    event PositionManagerAddressChanged(address _positionManagerAddress);

    // --- Dependency setters ---

    function setAddresses(
        address _sortedPositionsAddress,
        address _positionManagerAddress
    )
        external
        onlyOwner
    {
        checkContract(_sortedPositionsAddress);
        checkContract(_positionManagerAddress);

        sortedPositions = ISortedPositions(_sortedPositionsAddress);
        positionManager = IPositionManager(_positionManagerAddress);

        emit SortedPositionsAddressChanged(_sortedPositionsAddress);
        emit PositionManagerAddressChanged(_positionManagerAddress);

        renounceOwnership();
    }

    // --- Functions ---

    /* getRedemptionHints() - Helper function for finding the right hints to pass to redeemCollateral().
     *
     * It simulates a redemption of `_rAmount` to figure out where the redemption sequence will start and what state the final Position
     * of the sequence will end up in.
     *
     * Returns three hints:
     *  - `firstRedemptionHint` is the address of the first Position with ICR >= MCR (i.e. the first Position that will be redeemed).
     *  - `partialRedemptionHintNICR` is the final nominal ICR of the last Position of the sequence after being hit by partial redemption,
     *     or zero in case of no partial redemption.
     *  - `truncatedRAmount` is the maximum amount that can be redeemed out of the the provided `_rAmount`. This can be lower than
     *    `_rAmount` when redeeming the full amount would leave the last Position of the redemption sequence with less net debt than the
     *    minimum allowed value (i.e. MIN_NET_DEBT).
     *
     * The number of Positions to consider for redemption can be capped by passing a non-zero value as `_maxIterations`, while passing zero
     * will leave it uncapped.
     */

    function getRedemptionHints(
        uint _rAmount,
        uint _price,
        uint _maxIterations
    )
        external
        view
        returns (
            address firstRedemptionHint,
            uint partialRedemptionHintNICR,
            uint truncatedRAmount
        )
    {
        ISortedPositions sortedPositionsCached = sortedPositions;

        uint remainingR = _rAmount;
        address currentPositionUser = sortedPositionsCached.getLast();

        while (currentPositionUser != address(0) && positionManager.getCurrentICR(currentPositionUser, _price) < MCR) {
            currentPositionUser = sortedPositionsCached.getPrev(currentPositionUser);
        }

        firstRedemptionHint = currentPositionUser;

        if (_maxIterations == 0) {
            _maxIterations = type(uint256).max;
        }

        while (currentPositionUser != address(0) && remainingR > 0 && _maxIterations-- > 0) {
            (uint userDebt,,,,) = positionManager.positions(currentPositionUser);
            uint netRDebt = _getNetDebt(userDebt)
                + positionManager.getPendingRDebtReward(currentPositionUser);

            if (netRDebt > remainingR) {
                if (netRDebt > MIN_NET_DEBT) {
                    uint maxRedeemableR = Math.min(remainingR, netRDebt - MIN_NET_DEBT);

                    (,uint collateralBalance,,,) = positionManager.positions(currentPositionUser);
                    collateralBalance += positionManager.getPendingCollateralTokenReward(currentPositionUser);

                    uint newColl = collateralBalance - maxRedeemableR * DECIMAL_PRECISION / _price;
                    uint newDebt = netRDebt - maxRedeemableR;

                    uint compositeDebt = _getCompositeDebt(newDebt);
                    partialRedemptionHintNICR = LiquityMath._computeNominalCR(newColl, compositeDebt);

                    remainingR -= maxRedeemableR;
                }
                break;
            } else {
                remainingR -= netRDebt;
            }

            currentPositionUser = sortedPositionsCached.getPrev(currentPositionUser);
        }

        truncatedRAmount = _rAmount - remainingR;
    }

    /* getApproxHint() - return address of a Position that is, on average, (length / numTrials) positions away in the
    sortedPositions list from the correct insert position of the Position to be inserted.

    Note: The output address is worst-case O(n) positions away from the correct insert position, however, the function
    is probabilistic. Input can be tuned to guarantee results to a high degree of confidence, e.g:

    Submitting numTrials = k * sqrt(length), with k = 15 makes it very, very likely that the ouput address will
    be <= sqrt(length) positions away from the correct insert position.
    */
    function getApproxHint(uint _CR, uint _numTrials, uint _inputRandomSeed)
        external
        view
        returns (address hintAddress, uint diff, uint latestRandomSeed)
    {
        uint arrayLength = positionManager.getPositionOwnersCount();

        if (arrayLength == 0) {
            return (address(0), 0, _inputRandomSeed);
        }

        hintAddress = sortedPositions.getLast();
        diff = LiquityMath._getAbsoluteDifference(_CR, positionManager.getNominalICR(hintAddress));
        latestRandomSeed = _inputRandomSeed;

        uint i = 1;

        while (i < _numTrials) {
            latestRandomSeed = uint(keccak256(abi.encodePacked(latestRandomSeed)));

            uint arrayIndex = latestRandomSeed % arrayLength;
            address currentAddress = positionManager.getPositionFromPositionOwnersArray(arrayIndex);
            uint currentNICR = positionManager.getNominalICR(currentAddress);

            // check if abs(current - CR) > abs(closest - CR), and update closest if current is closer
            uint currentDiff = LiquityMath._getAbsoluteDifference(currentNICR, _CR);

            if (currentDiff < diff) {
                diff = currentDiff;
                hintAddress = currentAddress;
            }
            i++;
        }
    }

    function computeNominalCR(uint _coll, uint _debt) external pure returns (uint) {
        return LiquityMath._computeNominalCR(_coll, _debt);
    }

    function computeCR(uint _coll, uint _debt, uint _price) external pure returns (uint) {
        return LiquityMath._computeCR(_coll, _debt, _price);
    }
}
