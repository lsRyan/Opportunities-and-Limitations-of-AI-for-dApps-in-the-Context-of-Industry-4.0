// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract RealEstateNotary is Initializable, ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, ERC721PausableUpgradeable, ERC721BurnableUpgradeable, AccessControlUpgradeable {
    bytes32 private constant CARTORIO_STORAGE_LOCATION = 0xaa8b2f32297fc10d4303e434e1d6aee0c0c68830fc677fa0be548b8e938c9000;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");

    struct Request {
        uint256 tokenId;
        address requester;
        string newUri;
        string status;
    }

    struct CartorioStorage {
        uint256 _nextTokenId;
        mapping(uint256 => Request) requests;
        uint256 currentId;
    }

    function _getCartorioStorage() private pure returns (CartorioStorage storage $) {
        assembly {
            $.slot := CARTORIO_STORAGE_LOCATION
        }
    }

    function initialize() public initializer {
        __ERC721_init("Cartorio", "CBR");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://cartorio.org/imoveis/registro/";
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function safeMint(address to, string memory uri) public onlyRole(MINTER_ROLE) whenNotPaused returns (uint256) {
        CartorioStorage storage $ = _getCartorioStorage();
        uint256 tokenId = $._nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        return tokenId;
    }

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable) whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) whenNotPaused {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function requestChange(uint256 _tokenId, string memory _newUri) public returns (uint256) {
        CartorioStorage storage $ = _getCartorioStorage();
        require(_tokenId < $._nextTokenId, "Invalid token ID");
        require(ownerOf(_tokenId) == msg.sender, "Caller is not the token owner");
        $.currentId++;
        $.requests[$.currentId] = Request(_tokenId, msg.sender, _newUri, "under_evaluation");
        return $.currentId;
    }

    function answerRequest(uint256 requestId, bool accepted) public onlyRole(REVIEWER_ROLE) whenNotPaused {
        CartorioStorage storage $ = _getCartorioStorage();
        require(requestId <= $.currentId, "Invalid request ID");
        require(keccak256(abi.encodePacked($.requests[requestId].status)) == keccak256(abi.encodePacked("under_evaluation")), "Request already processed");
        if (accepted) {
            _setTokenURI($.requests[requestId].tokenId, $.requests[requestId].newUri);
            $.requests[requestId].status = "accepted";
        } else {
            $.requests[requestId].status = "rejected";
        }
    }

    function getRequest(uint256 requestId) public view returns (Request memory) {
        CartorioStorage storage $ = _getCartorioStorage();
        require(requestId <= $.currentId, "Invalid request ID");
        return $.requests[requestId];
    }
}
