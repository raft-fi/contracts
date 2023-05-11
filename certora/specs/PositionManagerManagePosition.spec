/*
    This is a specification file for the verification of ERC20Indexable
    smart contract using the Certora prover.
*/

////////////////////////////////////////////////////////////////////////////
//                                Methods                                 //
////////////////////////////////////////////////////////////////////////////
/*
    Declaration of methods that are used in the rules. envfree indicate that
    the method is not dependent on the environment (msg.value, msg.sender).
    Methods that are not declared here are assumed to be dependent on env.
*/
methods {
    getRaftCollateralTokenBalance(address,address)                  returns (uint256)   envfree
    managePosition(address,address,uint256,bool,uint256,bool,uint256)
}

rule CheckManagePositionIncreaseCollateral(
        address collateralToken,
        address position,
        uint256 collateralChange,
        bool isCollateralIncrease,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 maxFeePercentage
    ) {
    require isCollateralIncrease == true;
    
    uint256 raftCollateralTokenBalanceBefore = getRaftCollateralTokenBalance(collateralToken, position);

    env e;
    managePosition(e, 
        collateralToken,
        position,
        collateralChange,
        isCollateralIncrease,
        debtChange,
        isDebtIncrease,
        maxFeePercentage
    );

    assert raftCollateralTokenBalanceBefore < getRaftCollateralTokenBalance(collateralToken, position);
}
