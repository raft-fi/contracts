////////////////////////////////////////////////////////////////////////////
//                                Methods                                 //
////////////////////////////////////////////////////////////////////////////
/*
    Declaration of methods that are used in the rules. envfree indicate that
    the method is not dependent on the environment (msg.value, msg.sender).
    Methods that are not declared here are assumed to be dependent on env.
*/
methods {                            
    function collateralInfo(address)  external returns (address,address,address,address,bool,uint256,uint256,uint256,uint256,uint256)   envfree;
    function collateralTokenForPosition(address)                                            external returns (address)                  envfree;
    function computeICR(address,uint256)                                                    external returns (uint256)                  envfree;

    function managePosition(address,address,uint256,bool,uint256,bool,uint256,PositionManagerHarness.ERC20PermitSignature) external;
    function redeemCollateral(address,uint256,uint256)                                                                     external;
    function liquidate(address)                                                                                            external;

    function _.name()                                                                       external                => DISPATCHER(true);
    function _.symbol()                                                                     external                => DISPATCHER(true);
    function _.balanceOf(address)                                                           external                => DISPATCHER(true);
    function _.totalSupply()                                                                external                => DISPATCHER(true);
    function _.transfer(address,uint256)                                                    external                => DISPATCHER(true);
    function _.safeTransfer(address,uint256)                                                external                => DISPATCHER(true);
    function _.transferFrom(address,address,uint256)                                        external                => DISPATCHER(true);
    function _.safeTransferFrom(address,address,uint256)                                    external                => DISPATCHER(true);
    function _.mint(address,uint256)                                                        external                => DISPATCHER(true);
    function _.burn(address,uint256)                                                        external                => DISPATCHER(true);
    function _.permit(address,address,uint256,uint256,uint8,bytes32,bytes32)                external                => DISPATCHER(true);
    function _.setIndex(uint256)                                                            external                => DISPATCHER(true);

    function _.fetchPrice()                                                                 external                => DISPATCHER(true);

    function _.LOW_TOTAL_DEBT()                                                             external                => DISPATCHER(true);
    function _.MCR()                                                                        external                => DISPATCHER(true);
    function _.split(uint256,uint256,uint256,bool)                                          external                => DISPATCHER(true); 
}

function checkIsCollateralTokenSetupGood() returns bool {
    address raftCollateralToken;
    address raftDebtToken;
    address priceFeed;
    address splitLiquidation;
    bool isEnabled;
    uint256 lastFeeOperationTime;
    uint256 borrowingSpread;
    uint256 baseRate;
    uint256 redemptionSpread;
    uint256 redemptionRebate;
    raftCollateralToken, raftDebtToken, priceFeed, splitLiquidation, isEnabled, lastFeeOperationTime, borrowingSpread, baseRate, redemptionSpread, redemptionRebate = collateralInfo(collateralTokenMock);

    return raftCollateralToken == raftCollateralTokenMock 
        && raftDebtToken == raftDebtTokenMock 
        && priceFeed == priceFeedMock
        && splitLiquidation == splitLiquidationMock 
        && isEnabled == true;
}

function checkCollateralToken(address collateralToken_) returns bool {
    return collateralToken_ != rToken 
        && collateralToken_ != currentContract 
        && collateralToken_ != raftDebtTokenMock
        && collateralToken_ != raftCollateralTokenMock;
}
