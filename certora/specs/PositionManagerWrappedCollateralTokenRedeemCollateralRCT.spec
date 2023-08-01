/*
    This is a specification file for the verification of PositionManagerWrappedCollateralToken
    smart contract, function redeemCollateral (RaftCollateralToken) using the Certora prover

    https://prover.certora.com/output/23931/fcdb34f24c6040a083f1cc927702a0c7/?anonymousKey=1f5585847b71b68655edb9f4cf7ea7988df13424
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMockWithoutIndex as raftDebtTokenMock;
using RaftCollateralTokenMock as raftCollateralTokenMock;
using WrappedCollateralTokenMock as collateralTokenMock;
using RTokenMock as rToken;
using PositionManager as positionManagerHarness;
using PriceFeedMock as priceFeedMock;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function redeemCollateralHarness(uint256,uint256,PositionManager.ERC20PermitSignature) external;
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

// Check that PositionManagerWrappedCollateralToken does not have RaftCollateralToken after redeem collateral execution
rule integrityOfTokensTransferInRedeemCollateral(
    uint256 debtAmount,
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

    redeemCollateralHarness(e, debtAmount, maxFeePercentage, permitSignature);

    assert raftCollateralTokenMock.balanceOf(currentContract) == 0;
}
