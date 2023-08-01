#!/bin/bash

certoraRun certora/contracts/PositionManagerWrappedCollateralTokenHarness.sol:PositionManagerWrappedCollateralTokenHarness \
                    certora/contracts/mocks/RaftDebtTokenMockWithoutIndex.sol:RaftDebtTokenMockWithoutIndex \
                    certora/contracts/mocks/RaftCollateralTokenMockWithoutIndex.sol:RaftCollateralTokenMockWithoutIndex \
                    certora/contracts/mocks/WrappedCollateralTokenMock.sol:WrappedCollateralTokenMock \
                    certora/contracts/mocks/PriceFeedMock.sol:PriceFeedMock \
                    certora/contracts/mocks/RTokenMock.sol:RTokenMock \
                    contracts/PositionManager.sol:PositionManager \
                    contracts/SplitLiquidationCollateral.sol:SplitLiquidationCollateral \
            --verify PositionManagerWrappedCollateralTokenHarness:certora/specs/PositionManagerWrappedCollateralTokenRedeemCollateralOtherTokens.spec \
            --optimistic_loop \
            --solc_via_ir \
            --solc_optimize \
            --prover_args '-globalTimeout 7200 -cegar true' \
            --cache PositionManagerWrappedCollateralTokenRedeemCollateralOtherTokens \
            --link PositionManagerWrappedCollateralTokenHarness:raftDebtTokenHarness=RaftDebtTokenMockWithoutIndex \
                    PositionManagerWrappedCollateralTokenHarness:raftCollateralTokenHarness=RaftCollateralTokenMockWithoutIndex \
                    PositionManagerWrappedCollateralTokenHarness:collateralTokenHarness=WrappedCollateralTokenMock \
                    PositionManagerWrappedCollateralTokenHarness:rToken=RTokenMock \
                    PositionManagerWrappedCollateralTokenHarness:positionManager=PositionManager \
                    PositionManagerWrappedCollateralTokenHarness:priceFeedHarness=PriceFeedMock \
                    PositionManagerWrappedCollateralTokenHarness:splitLiquidationCollateralHarness=SplitLiquidationCollateral \
            --packages @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts \
                        @tempusfinance/tempus-utils/contracts/=lib/tempus-utils/contracts
