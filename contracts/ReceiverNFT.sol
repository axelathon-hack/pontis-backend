// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.17;

import {AxelarReceiverAdapter} from "./AxelarAdapter/AxelarReceiverAdapter.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IMultiChainNFT} from "./IMultiChainNFT.sol";

contract ReceiverNFT is
    ERC721URIStorage,
    AxelarReceiverAdapter,
    IMultiChainNFT
{
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    uint256 public collectionRoyalty;
    address collectionOwner;

    event TokenCreated(string ipfsURL, uint256 tokenId);

    address public owner;
    IGateway public gatewayContract;

    constructor(
        string memory _name,
        string memory _symbol,
        address _gatewayAddress,
        string memory _feePayerAddress,
        uint256 _royalty,
        address _collectionOwner
    ) {}

    function _execute(
        uint32 _origin, bytes32 _sender,
        bytes memory _body
    ) external override onlyGateway {
        super.handle(_origin, _sender, _body);
           }

     function mintAfterBurn(bytes calldata _payload) internal {
          
    }

}
