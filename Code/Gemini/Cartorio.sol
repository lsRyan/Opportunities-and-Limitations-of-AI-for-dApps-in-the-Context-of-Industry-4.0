// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title RealEstateNotary
/// @notice A digital notary service smart contract for managing real estate documentation as NFTs.
/// @dev Implements ERC721 with Access Control, Pausability, Enumerability, URI Storage, and custom Request logic using Namespaced Storage.
contract RealEstateNotary is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC721PausableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable
{
    // =============================================================
    //                           ROLES
    // =============================================================

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @dev Storage slot for Cartorio specific data to ensure upgrade safety
    bytes32 private constant CARTORIO_STORAGE_LOCATION =
        0xaa8b2f32297fc10d4303e434e1d6aee0c0c68830fc677fa0be548b8e938c9000;

    struct Request {
        uint256 tokenId;
        address requester;
        string newUri;
        string status; // "under_evaluation", "accepted", "rejected"
    }

    /// @custom:storage-location erc7201:Cartorio.storage
    struct CartorioStorage {
        uint256 _nextTokenId;
        mapping(uint256 => Request) requests;
        uint256 currentId;
    }

    // =============================================================
    //                         INITIALIZATION
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with necessary roles and configurations.
    function initialize() public initializer {
        __ERC721_init("Cartorio", "CBR");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // =============================================================
    //                       STANDARD FUNCTIONS
    // =============================================================

    /// @notice Returns the base URI for the tokens.
    function _baseURI() internal pure override returns (string memory) {
        return "https://cartorio.org/imoveis/registro/";
    }

    /// @notice Pauses the contract.
    /// @dev Only callable by accounts with PAUSER_ROLE.
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev Only callable by accounts with PAUSER_ROLE.
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Mints a new NFT representing a real estate document.
    /// @dev Increments token ID via storage struct and sets URI.
    /// @param to The address receiving the token.
    /// @param uri The specific URI string for the token metadata.
    /// @return The ID of the newly minted token.
    function safeMint(address to, string memory uri)
        public
        onlyRole(MINTER_ROLE)
        whenNotPaused
        returns (uint256)
    {
        CartorioStorage storage $ = _getCartorioStorage();
        uint256 tokenId = $._nextTokenId++;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        return tokenId;
    }

    // =============================================================
    //                        CUSTOM FUNCTIONS
    // =============================================================

    /// @notice Requests a change of URI for a specific token.
    /// @dev Can only be called by the token owner.
    /// @param _tokenId The ID of the token to update.
    /// @param _newUri The proposed new URI.
    /// @return The ID of the created request.
    function requestChange(uint256 _tokenId, string memory _newUri)
        public
        returns (uint256)
    {
        CartorioStorage storage $ = _getCartorioStorage();

        // Check if token exists and sender is owner
        // ownerOf reverts if token does not exist, satisfying validity check
        require(ownerOf(_tokenId) == msg.sender, "Caller is not token owner");

        $.currentId++;
        $.requests[$.currentId] = Request({
            tokenId: _tokenId,
            requester: msg.sender,
            newUri: _newUri,
            status: "under_evaluation"
        });

        return $.currentId;
    }

    /// @notice Reviews and answers a pending URI change request.
    /// @dev Only callable by REVIEWER_ROLE. Updates token URI if accepted.
    /// @param requestId The ID of the request to review.
    /// @param accepted Boolean indicating approval (true) or rejection (false).
    function answerRequest(uint256 requestId, bool accepted)
        public
        onlyRole(REVIEWER_ROLE)
        whenNotPaused
    {
        CartorioStorage storage $ = _getCartorioStorage();

        require(requestId > 0 && requestId <= $.currentId, "Invalid request ID");
        
        // String comparison using keccak256
        require(
            keccak256(bytes($.requests[requestId].status)) == keccak256(bytes("under_evaluation")),
            "Request not under evaluation"
        );

        if (accepted) {
            _setTokenURI($.requests[requestId].tokenId, $.requests[requestId].newUri);
            $.requests[requestId].status = "accepted";
        } else {
            $.requests[requestId].status = "rejected";
        }
    }

    /// @notice Retrieves details of a specific request.
    /// @param requestId The ID of the request.
    /// @return The Request struct containing details.
    function getRequest(uint256 requestId) public view returns (Request memory) {
        CartorioStorage storage $ = _getCartorioStorage();
        require(requestId > 0 && requestId <= $.currentId, "Invalid request ID");
        return $.requests[requestId];
    }

    // =============================================================
    //                        INTERNAL HELPERS
    // =============================================================

    /// @dev Retrieves the CartorioStorage struct from the specific storage slot.
    function _getCartorioStorage() private pure returns (CartorioStorage storage $) {
        assembly {
            $.slot := CARTORIO_STORAGE_LOCATION
        }
    }

    // =============================================================
    //                        OVERRIDES
    // =============================================================

    /// @notice Updates token state (transfers, mints, burns).
    /// @dev Required override for ERC721Enumerable and ERC721Pausable.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable)
        whenNotPaused
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /// @notice Updates account balances.
    /// @dev Required override for ERC721Enumerable.
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        whenNotPaused
    {
        super._increaseBalance(account, value);
    }

    /// @notice Returns the URI for a given token ID.
    /// @dev Required override for ERC721URIStorage.
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /// @notice Checks if the contract supports a specific interface.
    /// @dev Required override for multiple inheritance.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(
            ERC721Upgradeable,
            ERC721EnumerableUpgradeable,
            ERC721URIStorageUpgradeable,
            AccessControlUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}