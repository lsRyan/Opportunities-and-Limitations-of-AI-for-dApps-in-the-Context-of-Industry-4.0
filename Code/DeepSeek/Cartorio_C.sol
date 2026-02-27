// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import OpenZeppelin upgradeable contracts
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title RealEstateNotary
 * @notice Digital notary service for managing real estate documentation as NFTs
 * @dev This contract implements an ERC721-based notary system with role-based access control
 */
contract RealEstateNotary is 
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721PausableUpgradeable,
    AccessControlUpgradeable
{
    // =============================================================
    // Storage Structures and Constants
    // =============================================================
    
    /**
     * @notice Storage structure for cartorio data
     * @dev Uses diamond storage pattern to avoid storage collisions
     */
    struct CartorioStorage {
        uint256 _nextTokenId;           // Next available token ID for minting
        uint256 currentId;              // Current request ID counter
        mapping(uint256 => Request) requests; // Mapping of request IDs to requests
    }
    
    /**
     * @notice Structure representing a modification request
     */
    struct Request {
        uint256 tokenId;      // ID of the token being modified
        address requester;    // Address of the user who made the request
        string newUri;        // Requested new URI for the token
        string status;        // Current status of the request
    }
    
    /**
     * @notice Storage location constant for diamond storage pattern
     * @dev This ensures storage isolation in upgradeable contracts
     */
    bytes32 private constant CARTORIO_STORAGE_LOCATION = 
        0xaa8b2f32297fc10d4303e434e1d6aee0c0c68830fc677fa0be548b8e938c9000;
    
    // Role definitions
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");
    
    // =============================================================
    // Initialization and Constructor
    // =============================================================
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // Prevents initialization of the implementation contract
    }
    
    /**
     * @notice Initializes the contract with required parameters
     * @dev Sets up ERC721 token, roles, and initializes parent contracts
     */
    function initialize() public initializer {
        __ERC721_init("Cartorio", "CBR");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        
        // Grant default admin role to the deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize storage
        CartorioStorage storage $ = _getCartorioStorage();
        $._nextTokenId = 1; // Start token IDs from 1
        $.currentId = 0;    // Start request IDs from 0
    }
    
    // =============================================================
    // Public Functions - Token Management
    // =============================================================
    
    /**
     * @notice Mints a new real estate document token
     * @param to Address that will receive the token
     * @param uri Metadata URI for the token
     * @return tokenId The ID of the newly minted token
     * @dev Requires MINTER_ROLE and contract not to be paused
     */
    function safeMint(
        address to, 
        string memory uri
    ) 
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
     * @notice Requests a change to a token's metadata URI
     * @param _tokenId ID of the token to modify
     * @param _newUri New URI requested for the token
     * @return requestId The ID of the created request
     * @dev Only token owner can request changes
     */
    function requestChange(
        uint256 _tokenId, 
        string memory _newUri
    ) 
        public 
        returns (uint256) 
    {
        // Validate token existence and ownership
        require(_exists(_tokenId), "RealEstateNotary: Token does not exist");
        require(ownerOf(_tokenId) == msg.sender, "RealEstateNotary: Not token owner");
        
        CartorioStorage storage $ = _getCartorioStorage();
        $.currentId++;
        
        // Create and store the request
        $.requests[$.currentId] = Request({
            tokenId: _tokenId,
            requester: msg.sender,
            newUri: _newUri,
            status: "under_evaluation"
        });
        
        return $.currentId;
    }
    
    /**
     * @notice Reviews and responds to a modification request
     * @param requestId ID of the request to review
     * @param accepted Whether the request is accepted or rejected
     * @dev Requires REVIEWER_ROLE and contract not to be paused
     */
    function answerRequest(
        uint256 requestId, 
        bool accepted
    ) 
        public 
        onlyRole(REVIEWER_ROLE) 
        whenNotPaused 
    {
        CartorioStorage storage $ = _getCartorioStorage();
        
        // Validate request exists and is under evaluation
        require(requestId > 0 && requestId <= $.currentId, "RealEstateNotary: Invalid request ID");
        require(
            keccak256(abi.encodePacked($.requests[requestId].status)) == 
            keccak256(abi.encodePacked("under_evaluation")),
            "RealEstateNotary: Request not under evaluation"
        );
        
        if (accepted) {
            // Update token URI if accepted
            _setTokenURI($.requests[requestId].tokenId, $.requests[requestId].newUri);
            $.requests[requestId].status = "accepted";
        } else {
            // Mark as rejected
            $.requests[requestId].status = "rejected";
        }
    }
    
    /**
     * @notice Retrieves a request by ID
     * @param requestId ID of the request to retrieve
     * @return Request structure containing request details
     */
    function getRequest(
        uint256 requestId
    ) 
        public 
        view 
        returns (Request memory) 
    {
        CartorioStorage storage $ = _getCartorioStorage();
        require(requestId > 0 && requestId <= $.currentId, "RealEstateNotary: Invalid request ID");
        return $.requests[requestId];
    }
    
    // =============================================================
    // Public Functions - Contract Management
    // =============================================================
    
    /**
     * @notice Pauses all token transfers and minting
     * @dev Requires PAUSER_ROLE
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpauses the contract
     * @dev Requires PAUSER_ROLE
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    // =============================================================
    // Internal Functions
    // =============================================================
    
    /**
     * @notice Returns the base URI for token metadata
     * @return Base URI string
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://cartorio.org/imoveis/registro/";
    }
    
    /**
     * @notice Retrieves the cartorio storage structure
     * @return $ Reference to the CartorioStorage
     * @dev Uses assembly for diamond storage pattern
     */
    function _getCartorioStorage() private pure returns (CartorioStorage storage $) {
        assembly {
            $.slot := CARTORIO_STORAGE_LOCATION
        }
    }
    
    // =============================================================
    // Override Functions - Required by multiple inheritance
    // =============================================================
    
    /**
     * @notice Updates token ownership with pause protection
     * @param to New owner address
     * @param tokenId Token ID to update
     * @param auth Authorized address
     * @return Previous owner address
     */
    function _update(
        address to, 
        uint256 tokenId, 
        address auth
    ) 
        internal 
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable) 
        whenNotPaused 
        returns (address) 
    {
        return super._update(to, tokenId, auth);
    }
    
    /**
     * @notice Increases account balance with pause protection
     * @param account Account to increase balance for
     * @param value Amount to increase by
     */
    function _increaseBalance(
        address account, 
        uint128 value
    ) 
        internal 
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable) 
        whenNotPaused 
    {
        super._increaseBalance(account, value);
    }
    
    /**
     * @notice Returns the token URI for a given token ID
     * @param tokenId Token ID to query
     * @return Token URI string
     */
    function tokenURI(
        uint256 tokenId
    ) 
        public 
        view 
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable) 
        returns (string memory) 
    {
        return super.tokenURI(tokenId);
    }
    
    /**
     * @notice Checks interface support
     * @param interfaceId Interface ID to check
     * @return bool Whether the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) 
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

    function _exists(uint256 tokenId) internal view returns(bool) {
        CartorioStorage storage $ = _getCartorioStorage();
        return 0 < tokenId && tokenId < $.currentId;
    }
}