/*
    This is a specification file for the verification of PositionManager
    smart contract using the Certora prover (all functions except managePosition, redeemCollateral and liquidate)

    https://prover.certora.com/output/23931/f0e870bf940b400cacd756f6047252a6?anonymousKey=5e25e5e3af9633c50b9ad1beb676c2922de2f8ad
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMock as raftDebtTokenMock;
using RaftCollateralTokenMock as raftCollateralTokenMock;
using CollateralTokenMock as collateralTokenMock;
using PriceFeedMock as priceFeedMock;
using RTokenMock as rToken;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function raftDebtTokenMock.totalSupply()                            external returns (uint256)          envfree;

    function raftCollateralTokenMock.totalSupply()                      external returns (uint256)          envfree;

    function collateralTokenMock.balanceOf(address)                     external returns (uint256)          envfree;

    function rToken.totalSupply()                                       external returns (uint256)          envfree;
}

// Check integrity of the total supply of the Raft collateral token
rule integrityOfRaftCollateralTokenTotalSupply(method f) filtered {
		f -> f.selector != sig:managePosition(address,address,uint256,bool,uint256,bool,uint256,PositionManagerHarness.ERC20PermitSignature).selector && 
            f.selector != sig:redeemCollateral(address,uint256,uint256).selector &&
            f.selector != sig:liquidate(address).selector
	}
{
    require checkIsCollateralTokenSetupGood() == true;
    require raftCollateralTokenMock.totalSupply() == collateralTokenMock.balanceOf(currentContract);

    env e;
    require e.msg.sender != currentContract;

    calldataarg args;
    f(e, args);

    assert raftCollateralTokenMock.totalSupply() == collateralTokenMock.balanceOf(currentContract);
}

// Check integrity of the total supply of the Raft debt token and R token
rule integrityOfRaftDebtTokenTotalSupply(method f) filtered {
        f -> f.selector != sig:managePosition(address,address,uint256,bool,uint256,bool,uint256,PositionManagerHarness.ERC20PermitSignature).selector && 
            f.selector != sig:redeemCollateral(address,uint256,uint256).selector &&
            f.selector != sig:liquidate(address).selector
	}
{
    require checkIsCollateralTokenSetupGood() == true;
    require raftDebtTokenMock.totalSupply() == rToken.totalSupply();

    env e;
    require e.msg.sender != currentContract && e.msg.sender != rToken;

    calldataarg args;
    f(e, args);

    assert raftDebtTokenMock.totalSupply() == rToken.totalSupply();
}
