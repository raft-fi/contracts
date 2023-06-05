#!/bin/bash

certoraRun certora/contracts/PositionManagerHarness.sol:PositionManagerHarness \
                    certora/contracts/mocks/RaftDebtTokenMock.sol:RaftDebtTokenMock \
                    certora/contracts/mocks/RaftCollateralTokenMockWithoutIndex.sol:RaftCollateralTokenMockWithoutIndex \
                    certora/contracts/mocks/CollateralTokenMock.sol:CollateralTokenMock \
                    certora/contracts/mocks/PriceFeedMock.sol:PriceFeedMock \
                    certora/contracts/mocks/RTokenMock.sol:RTokenMock \
                    contracts/SplitLiquidationCollateral.sol:SplitLiquidationCollateral \
            --verify PositionManagerHarness:certora/specs/PositionManagerGlobalDebtChecks.spec \
            --optimistic_loop \
            --settings -t=3600 -globalTimeout=43200 \
            --solc_args "['--via-ir','--optimize']" \
            --cloud jtoman/cert-2201 \
            --link PositionManagerHarness:raftDebtTokenHarness=RaftDebtTokenMock\
                    PositionManagerHarness:raftCollateralTokenHarness=RaftCollateralTokenMockWithoutIndex \
                    PositionManagerHarness:collateralTokenHarness=CollateralTokenMock \
                    PositionManagerHarness:priceFeedHarness=PriceFeedMock \
                    PositionManagerHarness:rToken=RTokenMock \
                    PositionManagerHarness:splitLiquidationCollateralHarness=SplitLiquidationCollateral \
            --packages @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts \
                        @tempusfinance/tempus-utils/contracts/=lib/tempus-utils/contracts
