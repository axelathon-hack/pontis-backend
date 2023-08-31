// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.17;

import {AxelarSenderAdapter} from "./AxelarAdapter/AxelarSenderAdapter.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {IMultiChainNFT} from "./IMultiChainNFT.sol";

contract SenderNFT is ERC721URIStorage, AxelarSenderAdapter, IMultiChainNFT {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    address collectionOwner;

    event TokenCreated(string ipfsURL, uint256 tokenId);

    // transfer params struct where we specify which NFTs should be transferred to
    // the destination chain and to which address

    struct TransferParams {
        uint256 nftId;
        bytes recipient;
        string uri;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _mailbox,
        address _igp
    ) ERC721(_name, _symbol) AxelarSenderAdapter(_mailbox, _igp) {
        collectionOwner = msg.sender;
    }

    function mintLocal(string memory _tokenURI) external returns (uint256) {
        require(msg.sender == owner, "only owner");

        uint256 newTokenId = _tokenIds.current();
        _safeMint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, _tokenURI);
        _tokenIds.increment();

        emit TokenCreated(_tokenURI, newTokenId);
        return newTokenId;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721URIStorage) {
        super._burn(tokenId);
    }

    /// @notice function to generate a cross-chain NFT transfer request.
    /// @param destChainId chain ID of the destination chain in string.
    /// @param _tokenId nft token ID.
    /// @param _recipient recipient of token ID on destination chain.
    function transferRemote(
        string calldata destChainId,
        uint256 _tokenId,
        address _recipient
    ) public payable {
       
       IMultiChainNFT receiverAdapter = IMultiChainNFT(_recipient);

        require(_ownerOf(_tokenId) == msg.sender, "caller is not the owner");
        TransferParams memory transferParams;
        transferParams.nftId = _tokenId;
        transferParams.recipient = _recipient;
        transferParams.uri = super.tokenURI(_tokenId);
        // burning the NFTs from the address of the user calling _burnBatch function
        _burn(transferParams.nftId);

        // sending the transfer params struct to the destination chain as payload.
        bytes memory payload = abi.encode(transferParams);

        // Encode the function call.
        bytes memory targetData = abi.encodeCall(
            receiverAdapter.mintAfterBurn,
            _tokenURI,
            payload
        );

         dispatchMessage(_toChainId, receiverAdapter, targetData);
    }

   
    function mintRemote(
        uint256 _toChainId,
        address _to,
        string memory _tokenURI
    ) external returns (uint256) {
        IMultiChainNFT receiverAdapter = IMultiChainNFT(_to);

        // Encode the function call.
        bytes memory targetData = abi.encodeCall(
            receiverAdapter.mintLocal,
            _tokenURI
        );

        dispatchMessage(_toChainId, receiverAdapter, targetData);
    }
}
