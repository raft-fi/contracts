/*
    This is a specification file for the verification of PositionManager
    smart contract using the Certora prover (function redeemCollateral)

    https://prover.certora.com/output/23931/725ef910ee0f483189c5342762c2b5ba?anonymousKey=98394ce0bb818f73815c0a4489b19b73b7344a3b
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMockWithoutIndex as raftDebtTokenMock;
using RaftCollateralTokenMock as raftCollateralTokenMock;
using CollateralTokenMock as collateralTokenMock;
using PriceFeedMock as priceFeedMock;
using RTokenMock as rToken;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function raftDebtTokenMock.totalSupply()                            external    returns (uint256)           envfree;

    function raftCollateralTokenMock.totalSupply()                      external    returns (uint256)           envfree;
    function raftCollateralTokenMock.balanceOf(address)                 external    returns (uint256)           envfree;

    function collateralTokenMock.balanceOf(address)                     external    returns (uint256)           envfree;

    function priceFeedMock.fetchPrice()                                 external    returns (uint256,uint256)   envfree;

    function splitLiquidationMock.LOW_TOTAL_DEBT()                      external    returns (uint256)           envfree;

    function borrowingSpread(address)                                   external    returns (uint256)           envfree;
    function redemptionRebate(address)                                  external    returns (uint256)           envfree;
    function redemptionSpread(address)                                  external    returns (uint256)           envfree;
}


// Check integrity of the total supply of the Raft collateral token
rule integrityOfRaftCollateralTokenTotalSupply(
        uint256 debtAmount,
        uint256 maxFeePercentage
    ) {
    require checkIsCollateralTokenSetupGood() == true;
    require raftCollateralTokenMock.totalSupply() == collateralTokenMock.balanceOf(currentContract);

    env e;
    require e.msg.sender != currentContract;
    require checkCollateralToken(collateralTokenMock);

    uint256 lastPrice;
    uint256 deviation;
    lastPrice, deviation = priceFeedMock.fetchPrice();
    require lastPrice > 10000000000000000 && lastPrice < 1000000000000000000000000;
    require deviation == 10000000000000000;

    // Hardcoced values as are current setup in the PositionManager contract and wstETH collateral
    // The reason for this is timeout in CertoraProver
    require borrowingSpread(collateralTokenMock) == 0;
    require redemptionSpread(collateralTokenMock) == 1000000000000000000;
    require redemptionRebate(collateralTokenMock) == 1000000000000000000;

    mathint newRaftDebtTokenTotalSupply = to_mathint(raftDebtTokenMock.totalSupply()) - to_mathint(debtAmount);
    require newRaftDebtTokenTotalSupply >= to_mathint(splitLiquidationMock.LOW_TOTAL_DEBT());

    redeemCollateral(
        e,
        collateralTokenMock,
        debtAmount,
        maxFeePercentage
    );

    assert to_mathint(raftCollateralTokenMock.totalSupply()) <= to_mathint(collateralTokenMock.balanceOf(currentContract)) + to_mathint(100) 
        && to_mathint(raftCollateralTokenMock.totalSupply()) >= to_mathint(collateralTokenMock.balanceOf(currentContract)) - to_mathint(100);
}
