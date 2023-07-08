/*
    This is a specification file for the verification of PositionManager
    smart contract using the Certora prover (function managePosition)

    https://prover.certora.com/output/23931/9bc4e2c79ab543b99cf36fc01f4f3c97?anonymousKey=493b7684a037478639434a43c3bb82221d3a291c
*/

import "PositionManagerBase.spec";

using RaftDebtTokenMockWithoutIndex as raftDebtTokenMock;
using RaftCollateralTokenMockWithoutIndex as raftCollateralTokenMock;
using CollateralTokenMock as collateralTokenMock;
using PriceFeedMock as priceFeedMock;
using RTokenMock as rToken;
using SplitLiquidationCollateral as splitLiquidationMock;

methods {
    function collateralTokenForPosition(address)                                            external returns (address)                  envfree;
    function computeICR(address,uint256)                                                    external returns (uint256)                  envfree;

    function managePosition(address,address,uint256,bool,uint256,bool,uint256,PositionManagerHarness.ERC20PermitSignature) external;
    function redeemCollateral(address,uint256,uint256)                                                                     external;
    function liquidate(address)                                                                                            external;

    function raftDebtTokenMock.balanceOf(address)                           external returns (uint256)   envfree;
    function raftDebtTokenMock.totalSupply()                                external returns (uint256)   envfree;

    function raftCollateralTokenMock.balanceOf(address)                     external returns (uint256)   envfree;
    function raftCollateralTokenMock.totalSupply()                          external returns (uint256)   envfree;

    function collateralTokenMock.balanceOf(address)                         external returns (uint256)   envfree;

    function rToken.balanceOf(address)                                      external returns (uint256)   envfree;
    function rToken.totalSupply()                                           external returns (uint256)   envfree;
}

// Check integrity of collateral tokens when isCollateralIncrease is true
rule integrityOfCollateralTokensWhenIsCollateralIncreaseTrue(
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        PositionManagerHarness.ERC20PermitSignature signature
    ) {
    require checkIsCollateralTokenSetupGood() == true;
    require isCollateralIncrease == true;
    require !(!isDebtIncrease && (debtChange == max_uint || (raftDebtTokenMock.balanceOf(position) != 0 && debtChange == raftDebtTokenMock.balanceOf(position)))) ;

    env e;

    require e.msg.sender != currentContract;

    uint256 raftCollateralTokenBalanceBefore = raftCollateralTokenMock.balanceOf(position);
    uint256 collateralTokenBalanceBeforeSender = collateralTokenMock.balanceOf(e.msg.sender);
    uint256 collateralTokenBalanceBeforeContract = collateralTokenMock.balanceOf(currentContract);

    managePosition(e,
        collateralTokenMock,
        position,
        collateralChange,
        isCollateralIncrease,
        debtChange,
        isDebtIncrease,
        maxFeePercentage,
        signature
    );

    assert raftCollateralTokenBalanceBefore + collateralChange <= to_mathint(raftCollateralTokenMock.balanceOf(position)) + to_mathint(10);
    assert raftCollateralTokenBalanceBefore + collateralChange >= to_mathint(raftCollateralTokenMock.balanceOf(position)) - to_mathint(10);
    assert collateralTokenBalanceBeforeSender - collateralChange == to_mathint(collateralTokenMock.balanceOf(e.msg.sender));
    assert collateralTokenBalanceBeforeContract + collateralChange == to_mathint(collateralTokenMock.balanceOf(currentContract));
}

// Check integrity of collateral tokens when isCollateralIncrease is false
rule integrityOfCollateralTokensWhenIsCollateralIncreaseFalse(
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        PositionManagerHarness.ERC20PermitSignature signature
    ) {
    require checkIsCollateralTokenSetupGood() == true;
    require isCollateralIncrease == false;
    require !(!isDebtIncrease && (debtChange == max_uint || (raftDebtTokenMock.balanceOf(position) != 0 && debtChange == raftDebtTokenMock.balanceOf(position)))) ;

    env e;

    require e.msg.sender != currentContract;

    uint256 raftCollateralTokenBalanceBefore = raftCollateralTokenMock.balanceOf(position);
    uint256 collateralTokenBalanceBeforeSender = collateralTokenMock.balanceOf(e.msg.sender);
    uint256 collateralTokenBalanceBeforeContract = collateralTokenMock.balanceOf(currentContract);

    managePosition(e,
        collateralTokenMock,
        position,
        collateralChange,
        isCollateralIncrease,
        debtChange,
        isDebtIncrease,
        maxFeePercentage,
        signature
    );

    assert raftCollateralTokenBalanceBefore - collateralChange == to_mathint(raftCollateralTokenMock.balanceOf(position));
    assert collateralTokenBalanceBeforeSender + collateralChange == to_mathint(collateralTokenMock.balanceOf(e.msg.sender));
    assert collateralTokenBalanceBeforeContract - collateralChange == to_mathint(collateralTokenMock.balanceOf(currentContract));
}

// Check integrity of debt and R token when isDebtIncrease is true
rule integrityOfDebtAndRTokenWhenIsDebtIncreaseTrue(
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        PositionManagerHarness.ERC20PermitSignature signature
    ) {
    require checkIsCollateralTokenSetupGood() == true;
    require isDebtIncrease == true;
    require !(!isDebtIncrease && (debtChange == max_uint || (raftDebtTokenMock.balanceOf(position) != 0 && debtChange == raftDebtTokenMock.balanceOf(position)))) ;

    env e;

    require e.msg.sender != currentContract;

    uint256 rTokenBalanceBefore = rToken.balanceOf(e.msg.sender);
    uint256 raftDebtTokenBalanceBefore = raftDebtTokenMock.balanceOf(position);

    managePosition(e,
        collateralTokenMock,
        position,
        collateralChange,
        isCollateralIncrease,
        debtChange,
        isDebtIncrease,
        maxFeePercentage,
        signature
    );

    assert rTokenBalanceBefore + debtChange <= to_mathint(rToken.balanceOf(e.msg.sender));
    assert raftDebtTokenBalanceBefore + debtChange <= to_mathint(raftDebtTokenMock.balanceOf(position));
}

// Check integrity of debt and R token when isDebtIncrease is false
rule integrityOfDebtAndRTokenWheIsDebtIncreaseFalse(
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        PositionManagerHarness.ERC20PermitSignature signature
    ) {
    require checkIsCollateralTokenSetupGood() == true;
    require isDebtIncrease == false;
    require !(!isDebtIncrease && (debtChange == max_uint || (raftDebtTokenMock.balanceOf(position) != 0 && debtChange == raftDebtTokenMock.balanceOf(position)))) ;

    env e;

    require e.msg.sender != currentContract;

    uint256 rTokenBalanceBefore = rToken.balanceOf(e.msg.sender);
    uint256 raftDebtTokenBalanceBefore = raftDebtTokenMock.balanceOf(position);

    managePosition(e,
        collateralTokenMock,
        position,
        collateralChange,
        isCollateralIncrease,
        debtChange,
        isDebtIncrease,
        maxFeePercentage,
        signature
    );

    assert rTokenBalanceBefore - debtChange == to_mathint(rToken.balanceOf(e.msg.sender));
    assert raftDebtTokenBalanceBefore - debtChange == to_mathint(raftDebtTokenMock.balanceOf(position));
}

// Check integrity of tokens when close position
rule integrityOfTokensWhenClosePosition(
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        PositionManagerHarness.ERC20PermitSignature signature
    ) {
    require checkIsCollateralTokenSetupGood() == true;
    require isCollateralIncrease == true;
    require !isDebtIncrease && (debtChange == max_uint || (raftDebtTokenMock.balanceOf(position) != 0 && debtChange == raftDebtTokenMock.balanceOf(position))) ;

    env e;

    require e.msg.sender != currentContract;

    uint256 raftCollateralTokenBalanceBefore = raftCollateralTokenMock.balanceOf(position);
    uint256 collateralTokenBalanceBeforeSender = collateralTokenMock.balanceOf(e.msg.sender);
    uint256 collateralTokenBalanceBeforeContract = collateralTokenMock.balanceOf(currentContract);

    managePosition(e,
        collateralTokenMock,
        position,
        collateralChange,
        isCollateralIncrease,
        debtChange,
        isDebtIncrease,
        maxFeePercentage,
        signature
    );

    assert rToken.balanceOf(e.msg.sender) == 0;
    assert raftDebtTokenMock.balanceOf(position) == 0;
    assert raftCollateralTokenMock.balanceOf(position) == 0;
    assert collateralTokenBalanceBeforeSender + raftCollateralTokenBalanceBefore == to_mathint(collateralTokenMock.balanceOf(e.msg.sender));
    assert collateralTokenBalanceBeforeContract - raftCollateralTokenBalanceBefore == to_mathint(collateralTokenMock.balanceOf(currentContract));
}

// Check integrity of the total supply of the Raft collateral token
rule integrityOfRaftCollateralTokenTotalSupply(
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        PositionManagerHarness.ERC20PermitSignature signature
    ) {
    require checkIsCollateralTokenSetupGood() == true;
    require raftCollateralTokenMock.totalSupply() == collateralTokenMock.balanceOf(currentContract);

    env e;
    require e.msg.sender != currentContract;
    require checkCollateralToken(collateralTokenMock);

    managePosition(e, collateralTokenMock, position, collateralChange, isCollateralIncrease, debtChange, isDebtIncrease, maxFeePercentage, signature); 

    assert raftCollateralTokenMock.totalSupply() == collateralTokenMock.balanceOf(currentContract);
}

// Check integrity of the total supply of the Raft debt token and R token
rule integrityOfRaftDebtTokenTotalSupply(
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage,
        PositionManagerHarness.ERC20PermitSignature signature
    ) {
    require checkIsCollateralTokenSetupGood() == true;
    require raftDebtTokenMock.totalSupply() == rToken.totalSupply();

    env e;
    require e.msg.sender != currentContract && e.msg.sender != rToken;
    require checkCollateralToken(collateralTokenMock);

    managePosition(e, collateralTokenMock, position, collateralChange, isCollateralIncrease, debtChange, isDebtIncrease, maxFeePercentage, signature); 

    assert raftDebtTokenMock.totalSupply() == rToken.totalSupply();
}
