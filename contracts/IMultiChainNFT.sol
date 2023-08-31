// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.17;

interface IMultiChainNFT {
    function mintLocal(string memory _tokenURI) external returns (uint256);
    
}