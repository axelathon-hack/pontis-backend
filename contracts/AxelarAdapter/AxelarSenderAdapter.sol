pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAxelarGasService} from "@axelar-network/axelar-cgp-solidity/contracts/interfaces/IAxelarGasService.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

import {TypeCasts} from "./libraries/TypeCasts.sol";
import {Errors} from "./libraries/Errors.sol";
import {IMessageDispatcher} from "./interfaces/EIP5164/IMessageDispatcher.sol";
import {StringToAddress, AddressToString} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/utils/AddressString.sol";
import {StringToBytes32, Bytes32ToString} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/utils/Bytes32String.sol";

import "./libraries/MessageStruct.sol";

contract AxelarSenderAdapter is IAxelarGateway, IMessageDispatcher, Ownable {
    /// @notice `Gateway` contract reference.
    IGateway public immutable gateway;

    IAxelarGasService public immutable gasService;

    using StringToAddress for string;
    using AddressToString for address;

    uint256 public nonce;

    /**
     * @notice Receiver adapter address for each destination chain.
     * @dev dstChainId => receiverAdapter address.
     */
    mapping(uint256 => address) public receiverAdapters;

    /**
     * @notice Domain identifier for each destination chain.
     * @dev dstChainId => dstChainName.
     */
    mapping(uint256 => string) public chainIdToChainName;

    /**
     * @notice Emitted when a receiver adapter for a destination chain is updated.
     * @param dstChainId Destination chain identifier.
     * @param receiverAdapter Address of the receiver adapter.
     */
    event ReceiverAdapterUpdated(uint256 dstChainId, address receiverAdapter);

    /**
     * @notice Emitted when a domain identifier for a destination chain is updated.
     * @param dstChainId Destination chain identifier.
     * @param dstDomainId Destination domain identifier.
     */
    event DestinationDomainUpdated(uint256 dstChainId, uint32 dstDomainId);

    /**
     * @notice HyperlaneSenderAdapter constructor.
     * @param _Gateway Address of the Hyperlane `Gateway` contract.
     */
    constructor(address _gateway, address _gasService) {
        if (_gateway == address(0)) {
            revert Errors.InvalidGatewayZeroAddress();
        }
        gateway = IGateway(_gateway);
        gasService = IAxelarGasService(_gasService);
    }

    function setChainIdToChainName(
        string _chainName,
        uint32 _chainId
    ) public onlyOwner {
        chainIdToChainName[_chainId] = _chainName;
    }

    function encodeMessage(
        address to,
        bytes memory data,
        bytes32 messageId,
        uint256 fromChainId,
        address from
    ) internal pure returns (bytes memory) {
        return
            abi.encodeCall(
                IMessageExecutor.executeMessage,
                (to, data, messageId, fromChainId, from)
            );
    }

    function executeMessage(
        address to,
        bytes memory data,
        bytes32 messageId,
        uint256 fromChainId,
        address from,
        bool executedMessageId
    ) internal {
        if (executedMessageId) {
            revert MessageIdAlreadyExecuted(messageId);
        }

        _requireContract(to);

        (bool _success, bytes memory _returnData) = to.call(
            abi.encodePacked(data, messageId, fromChainId, from)
        );

        if (!_success) {
            revert MessageFailure(messageId, _returnData);
        }
    }

    function dispatchMessage(
        uint256 _toChainId,
        address _to,
        bytes calldata _data
    ) external payable returns (bytes32) {
        address receiverAdapter = receiverAdapters[_toChainId]; // read value into memory once
        if (receiverAdapter == address(0)) {
            revert Errors.InvalidAdapterZeroAddress();
        }
        bytes32 msgId = _getNewMessageId(_toChainId, _to);
        uint32 dstChainName = _getDestinationChainName(_toChainId);

        if (dstDomainId == "") {
            revert Errors.UnknownDomainId(_toChainId);
        }

        bytes memory payload = abi.encodeCall(
            IMessageExecutor.executeMessage,
            (_to, _data, msgId, getChainId(), msg.sender)
        );
        IGasService(gasService).payNativeGasForContractCall{value: msg.value}(
            address(this), //sender
            dstChainName, //destination chain
            receiverAdapter.toString(),
            payload,
            msg.sender
        );

        IGateway(gateway).callContract(
            dstChainName,
            receiverAdapter.toString(),
            payload
        );

        emit MessageDispatched(msgId, msg.sender, _toChainId, _to, _data);
        return msgId;
    }

    function updateReceiverAdapter(
        uint256[] calldata _dstChainIds,
        address[] calldata _receiverAdapters
    ) external onlyOwner {
        if (_dstChainIds.length != _receiverAdapters.length) {
            revert Errors.MismatchChainsAdaptersLength(
                _dstChainIds.length,
                _receiverAdapters.length
            );
        }
        for (uint256 i; i < _dstChainIds.length; ++i) {
            receiverAdapters[_dstChainIds[i]] = _receiverAdapters[i];
            emit ReceiverAdapterUpdated(_dstChainIds[i], _receiverAdapters[i]);
        }
    }

    function _getReceiverAdapter(
        uint256 _toChainID
    ) internal view returns (address _receiverAdapter) {
        _receiverAdapter = receiverAdapters[_toChainID];
    }

    /**
     * @notice Updates destination domain identifiers.
     * @param _dstChainIds Destination chain ids array.
     * @param _dstDomainIds Destination domain ids array.
     */
    function updateDestinationChainNames(
        uint256[] calldata _dstChainIds,
        string[] calldata _dstChainNames
    ) external onlyOwner {
        if (_dstChainIds.length != _dstChainNames.length) {
            revert Errors.MismatchChainsDomainsLength(
                _dstChainIds.length,
                _dstChainNames.length
            );
        }
        for (uint256 i; i < _dstChainIds.length; ++i) {
            chainIdToChainName[_dstChainIds[i]] = _dstChainNames[i];
            emit DestinationDomainUpdated(_dstChainIds[i], _dstChainNames[i]);
        }
    }

    /// @dev Get current chain id
    function getChainId() public view virtual returns (uint256 cid) {
        assembly {
            cid := chainid()
        }
    }
    /* ============ Internal Functions ============ */

    /**
     * @notice Returns destination domain identifier for given destination chain id.
     * @dev dstDomainId is read from destinationDomains mapping
     * @dev Returned dstDomainId can be zero, reverting should be handled by consumers if necessary.
     * @param _dstChainId Destination chain id.
     * @return destination domain identifier.
     */
    function _getDestinationChainName(
        uint256 _dstChainId
    ) internal view returns (uint32) {
        return chainIdToChainName[_dstChainId];
    }

    /**
     * @notice Get new message Id and increment nonce
     * @param _toChainId is the destination chainId.
     * @param _to is the contract address on the destination chain.
     */

    function _getNewMessageId(
        uint256 _toChainId,
        address _to
    ) internal returns (bytes32 messageId) {
        messageId = keccak256(
            abi.encodePacked(
                getChainId(),
                _toChainId,
                nonce,
                address(this),
                _to
            )
        );
        nonce++;
    }
}
