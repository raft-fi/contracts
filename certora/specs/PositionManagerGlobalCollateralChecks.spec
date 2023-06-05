/*
    This is a specification file for the verification of PositionManager
    smart contract using the Certora prover (check global invariants)

    https://prover.certora.com/output/23931/6d8bbc4afc3246dcada8845f0df291de/?anonymousKey=db1a456ff1a1d1e5e1bc5f10ecf15b365066abac
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMockWithoutIndex as raftDebtTokenMock;
using RaftCollateralTokenMock as raftCollateralTokenMock;
using CollateralTokenMock as collateralTokenMock;
using PriceFeedMock as priceFeedMock;
using RTokenMock as rToken;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function raftCollateralTokenMock.currentIndex()                     external returns (uint256)          envfree;

    function priceFeedMock.fetchPrice()                                 external returns (uint256,uint256)  envfree;   
}

rule integrityOfRaftCollateralSetIndex(method f) {
    require checkIsCollateralTokenSetupGood() == true;

    require raftCollateralTokenMock.currentIndex() > 0;

    env e;
    require e.msg.sender != currentContract;

    if (f.selector == sig:liquidate(address).selector) {
        uint256 lastPrice;
        uint256 deviation;
        lastPrice, deviation = priceFeedMock.fetchPrice();
        require lastPrice > 0;

        address position;
        address collateralTokenForPosition_ = collateralTokenForPosition(position);
        require checkCollateralToken(collateralTokenForPosition_);
        
        uint256 icr = computeICR(position, lastPrice);
        require icr > 1000000000000000;
        
        liquidate(e, position);
    } else if (f.selector == sig:managePosition(address,address,uint256,bool,uint256,bool,uint256,PositionManagerHarness.ERC20PermitSignature).selector) {
        address position;
        uint256 collateralChange;
        bool isCollateralIncrease;
        uint256 debtChange;
        bool isDebtIncrease;
        uint256 maxFeePercentage;
        PositionManagerHarness.ERC20PermitSignature signature;

        managePosition(
            e,
            collateralTokenMock,
            position,
            collateralChange,
            isCollateralIncrease,
            debtChange,
            isDebtIncrease,
            maxFeePercentage,
            signature
        );
    } else if (f.selector == sig:redeemCollateral(address,uint256,uint256).selector) {
        uint256 debtAmount;
        uint256 maxFeePercentage;

        uint256 lastPrice;
        uint256 deviation;
        lastPrice, deviation = priceFeedMock.fetchPrice();
        require lastPrice > 10000000000000000;

        redeemCollateral(
            e,
            collateralTokenMock,
            debtAmount,
            maxFeePercentage
        ); 
    } else { 
        calldataarg args;
        f(e, args);
    }

    assert raftCollateralTokenMock.currentIndex() > 0;
}
