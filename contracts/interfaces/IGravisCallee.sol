// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

interface IGravisCallee {
    function gravisCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
