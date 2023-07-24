// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRaftToken } from "./IRaftToken.sol";

/// @dev Raft Token, with an initial supply that can be increased by up to 2% yearly,
/// starting 2.5 years after deployment.
/// Token holders have the ability to burn their own tokens.
/// They can also vote and participate in governance decisions.
/// The contract supports the delegation of voting rights.
contract RaftToken is IRaftToken, Ownable2Step, ERC20Votes {
    using SafeERC20 for IERC20;

    string private _name;
    string private _symbol;

    uint256 public constant override INITIAL_SUPPLY = 2_500_000_000e18;
    uint256 public constant override MIN_TIME_BETWEEN_MINTS = 365 days;
    uint256 public constant override MINT_CAP = 10;

    uint256 public immutable override mintingAllowedAfter;

    uint256 public override lastMintingTime;

    constructor() ERC20("Raft", "RAFT") ERC20Permit("Raft") {
        mintingAllowedAfter = block.timestamp + 2.5 * 365 days;
        lastMintingTime = block.timestamp;
        _mint(msg.sender, INITIAL_SUPPLY);

        emit TokenRenamed("Raft", "RAFT");
    }

    function mint(address account, uint256 amount) external override onlyOwner {
        if (account == address(0)) {
            revert MintingToZeroAddressNotAllowed();
        }
        if (block.timestamp < mintingAllowedAfter) {
            revert MintingNotAllowedYet();
        }
        if (block.timestamp < (lastMintingTime + MIN_TIME_BETWEEN_MINTS)) {
            revert NotEnoughTimeBetweenMints();
        }
        uint256 mintCap = MINT_CAP * totalSupply() / 100;
        if (amount > mintCap) {
            revert MintAmountIsGreaterThanCap(amount, mintCap);
        }

        lastMintingTime = block.timestamp;
        _mint(account, amount);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function rescueTokens(IERC20 token, address to) external override onlyOwner {
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);

        emit TokensRescued(token, to, amount);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function renameToken(string calldata name_, string calldata symbol_) external override onlyOwner {
        if (bytes(name_).length == 0) {
            revert NewTokenNameIsEmpty();
        }
        if (bytes(symbol_).length == 0) {
            revert NewTokenSymbolIsEmpty();
        }

        _name = name_;
        _symbol = symbol_;

        emit TokenRenamed(name_, symbol_);
    }
}
