/*
    This is a specification file for the verification of PositionManager
    smart contract using the Certora prover (function liquidate)

    https://prover.certora.com/output/23931/fd30a9da46bf4364984dc836f41cbb72/?anonymousKey=9f1c2ffc760178e9c327f6bc41125f114b6419cb
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMock as raftDebtTokenMock;
using RaftCollateralTokenMockWithoutIndex as raftCollateralTokenMock;
using CollateralTokenMock as collateralTokenMock;
using PriceFeedMock as priceFeedMock;
using RTokenMock as rToken;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function raftDebtTokenMock.totalSupply()                            external    returns (uint256)           envfree;

    function priceFeedMock.fetchPrice()                                 external    returns (uint256,uint256)   envfree;

    function rToken.totalSupply()                                       external    returns (uint256)           envfree;
}

// Check integrity of the total supply of the Raft debt token and R token
rule integrityOfRaftDebtTokenTotalSupply(address position) {
    require checkIsCollateralTokenSetupGood() == true;
    require raftDebtTokenMock.totalSupply() == rToken.totalSupply();

    env e;
    require e.msg.sender != currentContract;

    uint256 lastPrice;
    uint256 deviation;
    lastPrice, deviation = priceFeedMock.fetchPrice();
    require lastPrice > 10000000000000000;

    address collateralTokenForPosition_ = collateralTokenForPosition(position);
    require checkCollateralToken(collateralTokenForPosition_);
    
    uint256 icr = computeICR(position, lastPrice);
    require icr > 1000000000000000;
    
    liquidate(e, position);

    assert to_mathint(raftDebtTokenMock.totalSupply()) <= to_mathint(rToken.totalSupply()) + to_mathint(100) 
        && to_mathint(raftDebtTokenMock.totalSupply()) >= to_mathint(rToken.totalSupply()) - to_mathint(100);
}
