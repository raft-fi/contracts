// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NonPayable {
    function forward(address _dest, bytes calldata _data) external {
        (bool success, bytes memory returnData) = _dest.call(_data);
        require(success, string(returnData));
    }

    function forwardWithApprove(address _dest, bytes calldata _data, address _token,  address _spender, uint256 _amount) external {
        IERC20(_token).approve(_spender, _amount);
        (bool success, bytes memory returnData) = _dest.call(_data);
        require(success, string(returnData));
    }
}
