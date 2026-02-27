// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title RealEstateNotary
 * @dev Digital notary service smart contract for managing real estate documentation.
 * Each real estate document is represented by a unique NFT following the ERC721 standard.
 * Implements role-based access control for minting, pausing, and reviewing document modifications.
 */
contract RealEstateNotary is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC721PausableUpgradeable,
    ERC721BurnableUpgradeable,
    AccessControlUpgradeable
{
    /// @dev Role identifier for accounts authorized to mint new tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /// @dev Role identifier for accounts authorized to pause the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @dev Role identifier for accounts authorized to review user requests
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");

    /// @dev Storage location for the contract's custom storage structure
    bytes32 private constant CARTORIO_STORAGE_LOCATION = 
        0xaa8b2f32297fc10d4303e434e1d6aee0c0c68830fc677fa0be548b8e938c9000;

    /**
     * @dev Struct representing a modification request for a token's URI
     * @param tokenId The ID of the token to be modified
     * @param requester Address of the user who submitted the request
     * @param newUri The proposed new URI for the token
     * @param status Current status of the request ("under_evaluation", "accepted", or "rejected")
     */
    struct request {
        uint256 tokenId;
        address requester;
        string newUri;
        string status;
    }

    /**
     * @dev Custom storage structure for the contract
     * @param _nextTokenId Counter for generating unique token IDs
     * @param requests Mapping of request IDs to modification requests
     * @param currentId Counter for generating unique request IDs
     */
    struct CartorioStorage {
        uint256 _nextTokenId;
        mapping(uint256 => request) requests;
        uint256 currentId;
    }

    /**
     * @dev Constructor that disables initializers to prevent implementation contract initialization
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with ERC721 extensions and grants admin role to deployer
     * Can only be called once due to the initializer modifier
     */
    function initialize() public initializer {
        __ERC721_init("Cartorio", "CBR");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Returns the base URI for computing token URIs
     * @return Base URI string for all tokens
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://cartorio.org/imoveis/registro/";
    }

    /**
     * @dev Pauses all token transfers and minting operations
     * Can only be called by accounts with PAUSER_ROLE
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers and minting operations
     * Can only be called by accounts with PAUSER_ROLE
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Safely mints a new token with a specified URI
     * @param to Address that will receive the minted token
     * @param uri Metadata URI for the token
     * @return tokenId The ID of the newly minted token
     * Requirements:
     * - Caller must have MINTER_ROLE
     * - Contract must not be paused
     */
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

    /**
     * @dev Retrieves the contract's custom storage structure
     * @return $ Reference to the CartorioStorage struct
     */
    function _getCartorioStorage() private pure returns (CartorioStorage storage $) {
        assembly {
            $.slot := CARTORIO_STORAGE_LOCATION
        }
    }

    /**
     * @dev Creates a request to modify a token's URI
     * @param _tokenId ID of the token to be modified
     * @param _newUri Proposed new URI for the token
     * @return requestId Unique ID of the created request
     * Requirements:
     * - Token must exist
     * - Caller must be the owner of the token
     */
    function requestChange(uint256 _tokenId, string memory _newUri) 
        public 
        returns (uint256) 
    {
        CartorioStorage storage $ = _getCartorioStorage();
        
        require(_ownerOf(_tokenId) != address(0), "Token does not exist");
        require(ownerOf(_tokenId) == msg.sender, "Caller is not the token owner");
        
        $.currentId++;
        $.requests[$.currentId] = request(_tokenId, msg.sender, _newUri, "under_evaluation");
        
        return $.currentId;
    }

    /**
     * @dev Reviews and processes a modification request
     * @param requestId ID of the request to process
     * @param accepted Whether the request is accepted (true) or rejected (false)
     * Requirements:
     * - Caller must have REVIEWER_ROLE
     * - Contract must not be paused
     * - Request must exist and be under evaluation
     */
    function answerRequest(uint256 requestId, bool accepted) 
        public 
        onlyRole(REVIEWER_ROLE) 
        whenNotPaused 
    {
        CartorioStorage storage $ = _getCartorioStorage();
        
        require(requestId > 0 && requestId <= $.currentId, "Invalid request ID");
        require(
            keccak256(bytes($.requests[requestId].status)) == keccak256(bytes("under_evaluation")),
            "Request is not under evaluation"
        );
        
        if (accepted) {
            _setTokenURI($.requests[requestId].tokenId, $.requests[requestId].newUri);
            $.requests[requestId].status = "accepted";
        } else {
            $.requests[requestId].status = "rejected";
        }
    }

    /**
     * @dev Retrieves details of a modification request
     * @param requestId ID of the request to retrieve
     * @return The request struct containing all request details
     * Requirements:
     * - Request must exist
     */
    function getRequest(uint256 requestId) public view returns (request memory) {
        CartorioStorage storage $ = _getCartorioStorage();
        
        require(requestId > 0 && requestId <= $.currentId, "Invalid request ID");
        
        return $.requests[requestId];
    }

    /**
     * @dev Internal function to update token ownership
     * Overrides multiple parent contracts to ensure proper functionality
     * @param to Address receiving the token
     * @param tokenId ID of the token being transferred
     * @param auth Address authorized to perform the transfer
     * @return Previous owner of the token
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable)
        whenNotPaused
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Internal function to increase token balance for an account
     * Overrides multiple parent contracts to ensure proper functionality
     * @param account Address whose balance is being increased
     * @param value Amount to increase the balance by
     */
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        whenNotPaused
    {
        super._increaseBalance(account, value);
    }

    /**
     * @dev Returns the token URI for a given token
     * @param tokenId ID of the token
     * @return Complete URI string for the token's metadata
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev Checks if the contract supports a given interface
     * @param interfaceId Interface identifier to check
     * @return True if the interface is supported
     */
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