// SPDX-License-Identifier: GPL-v3
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {

    address public owner;
    uint8 public immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        owner = msg.sender;
        _decimals = decimals_ == 0 ? 18 : decimals_;
        _mint(msg.sender, 100000 * (10 ** decimals_));
    }

    function decimals() public virtual override view returns(uint8) {
        return _decimals;
    }

    function getSender() public virtual view returns(address) {
        return msg.sender;
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
