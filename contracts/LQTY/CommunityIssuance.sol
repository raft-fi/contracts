// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../Interfaces/ILQTYToken.sol";
import "../Interfaces/ICommunityIssuance.sol";
import "../Dependencies/BaseMath.sol";
import "../Dependencies/LiquityMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";

contract CommunityIssuance is ICommunityIssuance, Ownable, CheckContract, BaseMath {
    // --- Data ---

    string public constant NAME = "CommunityIssuance";

    uint256 public constant SECONDS_IN_ONE_MINUTE = 60;

    /* The issuance factor F determines the curvature of the issuance curve.
    *
    * Minutes in one year: 60*24*365 = 525600
    *
    * For 50% of remaining tokens issued each year, with minutes as time units, we have:
    *
    * F ** 525600 = 0.5
    *
    * Re-arranging:
    *
    * 525600 * ln(F) = ln(0.5)
    * F = 0.5 ** (1/525600)
    * F = 0.999998681227695000
    */
    uint256 public constant ISSUANCE_FACTOR = 999998681227695000;

    /*
    * The community LQTY supply cap is the starting balance of the Community Issuance contract.
    * It should be minted to this contract by LQTYToken, when the token is deployed.
    *
    * Set to 32M (slightly less than 1/3) of total LQTY supply.
    */
    uint256 public constant LQTYSupplyCap = 32e24; // 32 million

    ILQTYToken public lqtyToken;

    address public stabilityPoolAddress;

    uint256 public totalLQTYIssued;
    uint256 public immutable deploymentTime;

    // --- Functions ---

    constructor() public {
        deploymentTime = block.timestamp;
    }

    function setAddresses(address _lqtyTokenAddress, address _stabilityPoolAddress) external override onlyOwner {
        checkContract(_lqtyTokenAddress);
        checkContract(_stabilityPoolAddress);

        lqtyToken = ILQTYToken(_lqtyTokenAddress);
        stabilityPoolAddress = _stabilityPoolAddress;

        // When LQTYToken deployed, it should have transferred CommunityIssuance's LQTY entitlement
        uint256 LQTYBalance = lqtyToken.balanceOf(address(this));
        assert(LQTYBalance >= LQTYSupplyCap);

        emit LQTYTokenAddressSet(_lqtyTokenAddress);
        emit StabilityPoolAddressSet(_stabilityPoolAddress);

        _renounceOwnership();
    }

    function issueLQTY() external override returns (uint256) {
        _requireCallerIsStabilityPool();

        uint256 latestTotalLQTYIssued = LQTYSupplyCap * _getCumulativeIssuanceFraction() / DECIMAL_PRECISION;
        uint256 issuance = latestTotalLQTYIssued - totalLQTYIssued;

        totalLQTYIssued = latestTotalLQTYIssued;
        emit TotalLQTYIssuedUpdated(latestTotalLQTYIssued);

        return issuance;
    }

    /* Gets 1-f^t    where: f < 1

    f: issuance factor that determines the shape of the curve
    t:  time passed since last LQTY issuance event  */
    function _getCumulativeIssuanceFraction() internal view returns (uint256) {
        // Get the time passed since deployment
        uint256 timePassedInMinutes = (block.timestamp - deploymentTime) / SECONDS_IN_ONE_MINUTE;

        // f^t
        uint256 power = LiquityMath._decPow(ISSUANCE_FACTOR, timePassedInMinutes);

        //  (1 - f^t)
        uint256 cumulativeIssuanceFraction = DECIMAL_PRECISION - power;
        assert(cumulativeIssuanceFraction <= DECIMAL_PRECISION); // must be in range [0,1]

        return cumulativeIssuanceFraction;
    }

    function sendLQTY(address _account, uint256 _LQTYamount) external override {
        _requireCallerIsStabilityPool();

        lqtyToken.transfer(_account, _LQTYamount);
    }

    // --- 'require' functions ---

    function _requireCallerIsStabilityPool() internal view {
        require(msg.sender == stabilityPoolAddress, "CommunityIssuance: caller is not SP");
    }
}
