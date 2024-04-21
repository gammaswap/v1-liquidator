// SPDX-License-Identifier: GPL-v3
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {

    address public owner;
    uint8 public _decimals;
    string public _name;
    string public _symbol;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        owner = msg.sender;
        setMetaData(name_, symbol_, 18);
    }

    function setMetaData(string memory name_, string memory symbol_, uint8 decimals_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public virtual override view returns(string memory) {
        return _name;
    }

    function symbol() public virtual override view returns(string memory) {
        return _symbol;
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
