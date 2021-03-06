//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;


interface Ijoetroller {
    function markets(address) external returns (bool, uint256);

    function enterMarkets(address[] calldata)
        external
        returns (uint256[] memory);

    function getAccountLiquidity(address)
        external
        view
        returns (uint256, uint256, uint256);
    
}