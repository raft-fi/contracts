/*
    This is a specification file for the verification of PositionManagerWrappedCollateralToken
    smart contract using the Certora prover

    https://prover.certora.com/output/23931/04d3fee78b4648199d5592dd302e98a0?anonymousKey=09320242c104687a068b6ab6be15e43dca6b271a
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMockWithoutIndex as raftDebtTokenMock;
using RaftCollateralTokenMockWithoutIndex as raftCollateralTokenMock;
using WrappedCollateralTokenMock as collateralTokenMock;
using RTokenMock as rToken;
using PositionManager as positionManagerHarness;
using PriceFeedMock as priceFeedMock;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function managePositionHarness(uint256,bool,uint256,bool,uint256,PositionManager.ERC20PermitSignature) external;
    function positionManager()                                              external returns (address)   envfree;
    function getRToken()                                                    external returns (address)   envfree;
    function getRaftDebtToken()                                             external returns (address)   envfree;
    function wrappedCollateralToken()                                       external returns (address)   envfree;
    function feeRecipient()                                                 external returns (address)   envfree;

    function raftDebtTokenMock.balanceOf(address)                           external returns (uint256)   envfree;

    function raftCollateralTokenMock.balanceOf(address)                     external returns (uint256)   envfree;

    function collateralTokenMock.balanceOf(address)                         external returns (uint256)   envfree;

    function rToken.balanceOf(address)                                      external returns (uint256)   envfree;

    function _.depositForWithAccountCheck(address,address,uint256)          external                => DISPATCHER(true);
    function _.withdrawTo(address,uint256)                                  external                => DISPATCHER(true);

    function _.collateralInfo(address)                                      external                => DISPATCHER(true);

    function _.managePosition(address,address,uint256,bool,uint256,bool,uint256,PositionManager.ERC20PermitSignature) external => DISPATCHER(true);
}

// Check that PositionManagerWrappedCollateralToken does not have any tokens after managePosition execution
rule integrityOfTokensTransferInManagerPosition(
    uint256 collateralChange,
    bool isCollateralIncrease,
    uint256 debtChange,
    bool isDebtIncrease,
    uint256 maxFeePercentage,
    PositionManager.ERC20PermitSignature permitSignature
) {
    env e;

    require positionManagerHarness == positionManager();
    require rToken == getRToken();
    require raftDebtTokenMock == getRaftDebtToken();
    require collateralTokenMock == wrappedCollateralToken();
    require raftDebtTokenMock.balanceOf(e.msg.sender) < max_uint;
    require raftDebtTokenMock != e.msg.sender
        && raftCollateralTokenMock != e.msg.sender 
        && collateralTokenMock != e.msg.sender
        && rToken != e.msg.sender
        && positionManagerHarness != e.msg.sender
        && priceFeedMock != e.msg.sender
        && splitLiquidationMock != e.msg.sender;
    require currentContract != feeRecipient();

    require checkIsCollateralTokenSetupGood() == true;

    require e.msg.sender != currentContract;
    require checkCollateralToken(collateralTokenMock);

    require raftDebtTokenMock.balanceOf(currentContract) == 0;
    require raftCollateralTokenMock.balanceOf(currentContract) == 0;
    require collateralTokenMock.balanceOf(currentContract) == 0;
    require rToken.balanceOf(currentContract) == 0;

    managePositionHarness(e, collateralChange, isCollateralIncrease, debtChange, isDebtIncrease, maxFeePercentage, permitSignature);

    assert raftDebtTokenMock.balanceOf(currentContract) == 0;
    assert raftCollateralTokenMock.balanceOf(currentContract) == 0;
    assert collateralTokenMock.balanceOf(currentContract) == 0;
    assert rToken.balanceOf(currentContract) == 0;
}
