// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract RealEstateNotary is 
    Initializable,
    ERC721Upgradeable,
    ERC721BurnableUpgradeable,
    ERC721EnumerableUpgradeable,
    ERC721PausableUpgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Struct to store cartorio-specific storage data
    struct CartorioStorage {
        uint256 _nextTokenId;
        mapping(uint256 => request) requests;
        uint256 currentId;
    }

    // Struct to represent a request for URI change
    struct request {
        uint256 tokenId;
        address requester;
        string newUri;
        string status; // "under_evaluation", "accepted", "rejected"
    }

    // Storage location for cartorio-specific data
    bytes32 private constant CARTORIO_STORAGE_LOCATION = 0xaa8b2f32297fc10d4303e434e1d6aee0c0c68830fc677fa0be548b8e938c9000;

    // Role definitions
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("Cartorio", "CBR");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Returns the base URI for all token URIs
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://cartorio.org/imoveis/registro/";
    }

    /**
     * @dev Pauses the contract, restricting certain operations
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract, allowing operations again
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Safely mints a new token with the specified URI
     * @param to The address that will receive the new token
     * @param uri The URI for the new token
     * @return The ID of the newly minted token
     */
    function safeMint(address to, string memory uri) public onlyRole(MINTER_ROLE) whenNotPaused returns (uint256) {
        CartorioStorage storage $ = _getCartorioStorage();
        uint256 tokenId = $._nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        return tokenId;
    }

    /**
     * @dev Internal function to get the cartorio-specific storage
     * @return $ The storage reference for cartorio data
     */
    function _getCartorioStorage() private pure returns (CartorioStorage storage $) {
        assembly {
            $.slot := CARTORIO_STORAGE_LOCATION
        }
    }

    /**
     * @dev Override update function to handle token transfers with pause functionality
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable) whenNotPaused 
    returns (address) {
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Override increase balance function with pause functionality
     */
    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) whenNotPaused {
        super._increaseBalance(account, value);
    }

    /**
     * @dev Override tokenURI to handle URI storage properly
     */
    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Check if the contract supports a specific interface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Allows token owners to request a URI change
     * @param _tokenId The ID of the token for which to request a URI change
     * @param _newUri The new URI to request
     * @return The ID of the created request
     */
    function requestChange(uint256 _tokenId, string memory _newUri) public nonReentrant returns (uint256) {
        require(_exists(_tokenId), "Token does not exist");
        require(ownerOf(_tokenId) == msg.sender, "Only token owner can request changes");

        CartorioStorage storage $ = _getCartorioStorage();
        
        $.currentId++;
        $.requests[$.currentId] = request({
            tokenId: _tokenId,
            requester: msg.sender,
            newUri: _newUri,
            status: "under_evaluation"
        });

        return $.currentId;
    }

    /**
     * @dev Allows reviewers to approve or reject a URI change request
     * @param requestId The ID of the request to process
     * @param accepted Whether to accept or reject the request
     */
    function answerRequest(uint256 requestId, bool accepted) public onlyRole(REVIEWER_ROLE) whenNotPaused nonReentrant {
        CartorioStorage storage $ = _getCartorioStorage();
        
        require(requestId <= $.currentId && requestId > 0, "Invalid request ID");
        require(keccak256(bytes($.requests[requestId].status)) == keccak256(bytes("under_evaluation")), "Request already processed");

        if (accepted) {
            _setTokenURI($.requests[requestId].tokenId, $.requests[requestId].newUri);
            $.requests[requestId].status = "accepted";
        } else {
            $.requests[requestId].status = "rejected";
        }
    }

    /**
     * @dev Gets the details of a specific request
     * @param requestId The ID of the request to retrieve
     * @return The request details
     */
    function getRequest(uint256 requestId) public view returns (request memory) {
        CartorioStorage storage $ = _getCartorioStorage();
        
        require(requestId <= $.currentId && requestId > 0, "Invalid request ID");
        
        return $.requests[requestId];
    }

    function _exists(uint256 tokenId) internal view returns(bool) {
        CartorioStorage storage $ = _getCartorioStorage();
        return 0 <= tokenId && tokenId < $._nextTokenId;
    }
}