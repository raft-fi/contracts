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
    function totalSupply()                         external returns (uint256)   envfree;
    function balanceOf(address)                    external returns (uint256)   envfree;
    function allowance(address,address)            external returns (uint256)   envfree;
    function currentIndex()                        external returns (uint256)   envfree;
    function totalSupplyERC20()                    external returns (uint256)   envfree;
    function balanceOfERC20(address)               external returns (uint256)   envfree;
    function setIndex(uint256) external;
    function mint(address,uint256) external;
    function burn(address,uint256) external;
}

// Check functions that change the balance of the user
rule CheckFunctionsThatChangeBalance(method f) filtered {
		f -> f.selector != sig:mint(address,uint256).selector && 
            f.selector != sig:burn(address,uint256).selector &&
            f.selector != sig:setIndex(uint256).selector
	}
{
    env e;

    uint256 balanceOfUserBefore = balanceOf(e.msg.sender);

    calldataarg args;
    f(e, args);

    assert balanceOfUserBefore == balanceOf(e.msg.sender);
}

// Check currentIndex cannot be zero
rule CheckCurrentIndexCannotBeZero(uint256 backingAmount) {
    require currentIndex() != 0;

    // In PositionManagerGlobalCollateralChecks.spec (rule integrityOfRaftCollateralSetIndex) 
    //      and PositionManagerGlobalCollateralChecks (rule integrityOfRaftDebtlSetIndex) is checked that backingAmount != 0
    require backingAmount != 0;

    env e;
    setIndex(e, backingAmount);

    assert currentIndex() != 0;
}

// Check total supply is greater or equal to sum of user balances
rule CheckTotalSupplyMustBeGreaterOrEqualThanSumOfUserBalances(method f, address user, uint256 amount) {
    address user1;
    require user != user1;
    require balanceOfERC20(user) + balanceOfERC20(user1) == to_mathint(totalSupplyERC20());
    
    env e;
    if (f.selector == sig:mint(address,uint256).selector) {
        mint(e, user, amount);
    } else if (f.selector == sig:burn(address,uint256).selector) {
        burn(e, user, amount); 
    } else {
        calldataarg args;
        f(e, args);
    }

    assert balanceOf(user) + balanceOf(user1) <= to_mathint(totalSupply());
}
