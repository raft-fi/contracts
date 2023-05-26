/*
    This is a specification file for the verification of PositionManager
    smart contract using the Certora prover (function liquidate)

    https://prover.certora.com/output/23931/111e9932f01c4126a1d9f60c154362b1?anonymousKey=d917fb174cc730f3abd50a99cf13083aee067df4
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMockWithoutIndex as raftDebtTokenMock;
using RaftCollateralTokenMock as raftCollateralTokenMock;
using CollateralTokenMock as collateralTokenMock;
using PriceFeedMock as priceFeedMock;
using RTokenMock as rToken;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function raftCollateralTokenMock.totalSupply()                      external    returns (uint256)           envfree;

    function collateralTokenMock.balanceOf(address)                     external    returns (uint256)           envfree;

    function priceFeedMock.fetchPrice()                                 external    returns (uint256,uint256)   envfree;
}

// Check integrity of the total supply of the Raft collateral token
rule integrityOfRaftCollateralTokenTotalSupply(address position) {
    require checkIsCollateralTokenSetupGood() == true;
    require raftCollateralTokenMock.totalSupply() == collateralTokenMock.balanceOf(currentContract);

    env e;
    require e.msg.sender != currentContract;

    uint256 lastPrice;
    uint256 deviation;
    lastPrice, deviation = priceFeedMock.fetchPrice();
    require lastPrice > 0;

    address collateralTokenForPosition_ = collateralTokenForPosition(position);
    require checkCollateralToken(collateralTokenForPosition_);
    
    uint256 icr = computeICR(position, lastPrice);
    require icr > 1000000000000000;
    
    liquidate(e, position);

    assert to_mathint(raftCollateralTokenMock.totalSupply()) <= to_mathint(collateralTokenMock.balanceOf(currentContract));
}
