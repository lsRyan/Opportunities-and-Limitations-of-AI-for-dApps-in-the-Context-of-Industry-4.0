# Role

You are a senior Ethereum smart contract developer responsible for implementing secure, efficient, well-documented Solidity contracts based on detailed specifications. Your work should follow industry-standard practices for structure, safety, and readability.

# Context

A governmental agency has requested the development of a digital notary service smart contract for managing real estate documentation. You are the lead developer responsible for employing OpenZeppelin's ERC721 standard for implementing this project with all of the required functionalities in a secure and extensible manner using Solidity and employing all of the best practices for decentralized applications.

# Objective

Your task is to develop a fully functional, well-commented, and secure Solidity contract that implements the RealStateNotary contract, as will be thoroughly described below. The code must:
* Be secure, avoiding vulnerabilities such as reentrancy, integer overflows/underflows, access control issues, and all known vulnerabilities that could affect the contract's functionalities.
* Be readable, using clear naming conventions, structured logic, and inline documentation (Solidity comments).
* Follow best practices for gas efficiency and modularity.
* Represents a digital notary system based on the OpenZeppelin ERC721 token standard.
* Use the latest Solidity compiler version you are familiar with.

# Application

## Overview
The contract will represent a digital notary service, where each real estate document is represented by a unique, non-fungible token (NFT) following OpenZeppelin's ERC721 standard. Each NFT must have a unique identifier, and when created, no other NFT may share that ID.

The contract will support the following special roles:

* `DEFAULT_ADMIN_ROLE`: The default admin account.
* `MINTER_ROLE`: Accounts authorized to mint new tokens.
* `PAUSER_ROLE`: Accounts authorized to pause the contract.
* `REVIEWER_ROLE`: Accounts authorized to review user requests, as defined in the "functions" section.

All actions must be logged for auditability and transparency, following best practices in blockchain development.

## Contracts

### RealEstateNotary

#### Variables

* `struct CartorioStorage`: Stores the next token id. Includes:
  * `uint256 _nextTokenId`: Next token id. 
  * `struct request`: The format of a request. Includes:
    * `uint256 tokenId`: The ID of the affected token.
    * `address requester`: Address of the user who made the request.
    * `string memory newUri`: The new URI requested for the token.
    * `string memory status`: Current request status. Can be set as "under_evaluation", "accepted", "rejected".
  * `mapping(uint256 => request) requests`: Maps request IDs to a `request`.
  * `uint256 currentId`: Used to generate a unique ID for each modification `request`.
* `bytes32 private constant CARTORIO_STORAGE_LOCATION`: A bytes32 constant private variable with a contract's storage address. In this example, it should be initialized as `0xaa8b2f32297fc10d4303e434e1d6aee0c0c68830fc677fa0be548b8e938c9000`.
* `bytes32 public constant MINTER_ROLE`: Set as keccak256("MINTER_ROLE").
* `bytes32 public constant PAUSER_ROLE`: Set as keccak256("PAUSER_ROLE").
* `bytes32 public constant REVIEWER_ROLE`: Set as keccak256("REVIEWER_ROLE").

#### Functions

##### Standard Functions

The contract should follow OpenZeppelin's ERC721. Hence, the following libraries should be used:

* `AccessControlUpgradeable`
* `ERC721Upgradeable`
* `ERC721BurnableUpgradeable`
* `ERC721EnumerableUpgradeable`
* `ERC721PausableUpgradeable`
* `ERC721URIStorageUpgradeable`

As per OpenZeppelin's token wizard, the following functions should be present:

* `initialize() public initializer`
  * Call __ERC721_init("Cartorio", "CBR").
  * Call __ERC721Enumerable_init().
  * Call __ERC721URIStorage_init().
  * Call __ERC721Pausable_init().
  * Call __AccessControl_init();
  * Call __ERC721Burnable_init().
  * Call _grantRole(`DEFAULT_ADMIN_ROLE`, `msg.sender`);

* `_baseURI() internal pure overrides returns (string memory)`
  * Returns the base URI.
  * Use "https://cartorio.org/imoveis/registro/" in your implementation.

* `pause() public onlyRole(PAUSER_ROLE)`
  * Call _pause().

* `unpause() public onlyRole(PAUSER_ROLE)`
  * Call _unpause().

* `safeMint(address to, string memory uri) public onlyRole(MINTER_ROLE) whenNotPaused returns (uint256)`
  * Set `CartorioStorage storage $` as the return value of the call to `_getCartorioStorage()`.
  * Update `tokenId` with `$._nextTokenId++`.
  * Call _safeMint(`to`, `tokenId`).
  * Call _setTokenURI(`tokenId`, `uri`).
  * Return `tokenId`.

* `_getCartorioStorage() private pure returns (CartorioStorage storage $)`
  * Execute the following assembly line:
    * $.slot := `CARTORIO_STORAGE_LOCATION`

* `_update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable) whenNotPaused returns (address)`
  * Return super._update(`to`, `tokenId`, `auth`).

* `_increaseBalance(address account, uint128 value) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) whenNotPaused`
  * Call super._increaseBalance(`account`, `value`).

* `tokenURI(uint256 tokenId) public view override(ERC721Upgradeable and ERC721URIStorageUpgradeable) returns (string memory)`
  * Return super.tokenURI(`tokenId`).

* `supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable) returns (bool)`
  * Return super.supportsInterface(`interfaceId`).

##### Custom Functions

* `constructor()`
  * Call _disableInitializers().

* `requestChange(uint256 _tokenId, string memory _newUri) public returns (uint256)`
  * Set `CartorioStorage storage $` as the return value of the call to `_getCartorioStorage()`.
  * Check if:
    * The value of `_tokenId` is valid.
    * Calling ownerOf(`_tokenId`) returns the same address as `msg.sender`.
  * Increment `$.currentId`
  * Set `$.requests[$.currentId]` as request(`_tokenId`, `msg.sender`, `_newUri`, "under_evaluation").
  * Return `$.currentId`.

* `answerRequest(uint256 requestId, bool accepted) public onlyRole(REVIEWER_ROLE) whenNotPaused`
  * Set `CartorioStorage storage $` as the return value of the call to `_getCartorioStorage()`.
  * Check if:
    * The value of `requestId` is valid.
    * The value of `$.requests[requestId].status` is "under_evaluation".
  * If `accepted` is `true`:
    * Call _setTokenURI(`$.requests[requestId].tokenId`, `$.requests[requestId].newUri`).
    * Change `$.requests[requestId].status` to "accepted".
  * Else:
    * Change `$.requests[requestId].status` to "rejected".

* `getRequest(uint256 requestId) public view returns (request memory)`
  * Set `CartorioStorage storage $` as the return value of the call to `_getCartorioStorage()`.
  * Check if:
    * The value of `requestId` is valid.
  * Return `$.requests[requestId]`.

# Response Format
Your response should be the fully implemented Solidity contract that includes all the functionalities and functions described above, including the OpenZeppelin ERC721 implementation. No additional content is required.