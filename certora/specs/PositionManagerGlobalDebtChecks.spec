/*
    This is a specification file for the verification of PositionManager
    smart contract using the Certora prover (check global invariants)

    https://prover.certora.com/output/23931/e2bac599e2204e11a832932b5472262d?anonymousKey=61a144fe8dd9ab99f6f58f842fbbdff6599b770a
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMock as raftDebtTokenMock;
using RaftCollateralTokenMockWithoutIndex as raftCollateralTokenMock;
using CollateralTokenMock as collateralTokenMock;
using PriceFeedMock as priceFeedMock;
using RTokenMock as rToken;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function raftDebtTokenMock.currentIndex()                           external returns (uint256)          envfree;

    function priceFeedMock.fetchPrice()                                 external returns (uint256,uint256)  envfree;   
}

rule integrityOfRaftDebtlSetIndex(method f) {
    require checkIsCollateralTokenSetupGood() == true;

    require raftDebtTokenMock.currentIndex() > 0;

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

    assert raftDebtTokenMock.currentIndex() > 0;
}
