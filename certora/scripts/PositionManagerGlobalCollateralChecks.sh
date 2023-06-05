#!/bin/bash

certoraRun certora/contracts/PositionManagerHarness.sol:PositionManagerHarness \
                    certora/contracts/mocks/RaftDebtTokenMockWithoutIndex.sol:RaftDebtTokenMockWithoutIndex \
                    certora/contracts/mocks/RaftCollateralTokenMock.sol:RaftCollateralTokenMock \
                    certora/contracts/mocks/CollateralTokenMock.sol:CollateralTokenMock \
                    certora/contracts/mocks/PriceFeedMock.sol:PriceFeedMock \
                    certora/contracts/mocks/RTokenMock.sol:RTokenMock \
                    contracts/SplitLiquidationCollateral.sol:SplitLiquidationCollateral \
            --verify PositionManagerHarness:certora/specs/PositionManagerGlobalCollateralChecks.spec \
            --optimistic_loop \
            --settings -t=3600 \
            --solc_args "['--via-ir','--optimize']" \
            --cloud jtoman/cert-2201 \
            --link PositionManagerHarness:raftDebtTokenHarness=RaftDebtTokenMockWithoutIndex \
                    PositionManagerHarness:raftCollateralTokenHarness=RaftCollateralTokenMock \
                    PositionManagerHarness:collateralTokenHarness=CollateralTokenMock \
                    PositionManagerHarness:priceFeedHarness=PriceFeedMock \
                    PositionManagerHarness:rToken=RTokenMock \
                    PositionManagerHarness:splitLiquidationCollateralHarness=SplitLiquidationCollateral \
            --packages @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts \
                        @tempusfinance/tempus-utils/contracts/=lib/tempus-utils/contracts
