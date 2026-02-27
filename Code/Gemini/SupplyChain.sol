// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ----------------------------------------------------------------------------
// Interfaces
// ----------------------------------------------------------------------------

interface IAuthorizationCertificates {
    function isAuthorizedHospital(address hospital) external view returns (bool);
    function isAuthorizedManufacturer(address manufacturer) external view returns (bool);
}

// Defining the struct in an interface to ensure compatibility across contracts
interface IPrescriptionStructs {
    struct Prescription {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }
}

interface IPrescriptions is IPrescriptionStructs {
    function _prescribe(address doctor, address patient, string memory _medicine, uint256 _dose) external returns (uint256);
    function _getPrescription(address patient, uint256 id) external view returns (Prescription memory);
    function usePrescription(address patient, uint256 id) external;
}

interface IHospitalManagement {
    function authorizeSale(uint256 prescriptionId, address patient, string memory medicine, uint256 amount) external returns (bool);
}

// ----------------------------------------------------------------------------
// 1. Authorization Certificates
// ----------------------------------------------------------------------------

/**
 * @title AuthorizationCertificates
 * @dev Manages the allowlist for hospitals and manufacturers.
 */
contract AuthorizationCertificates {
    // Variables
    address public admin;
    mapping(address => bool) internal authorizedHospitals;
    mapping(address => bool) internal authorizedManufacturers;

    // Events
    event HospitalStatusChanged(address indexed hospital, bool status);
    event ManufacturerStatusChanged(address indexed manufacturer, bool status);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Caller is not the admin");
        _;
    }

    // Functions
    constructor() {
        admin = msg.sender;
    }

    function authorizeHospital(address hospital) external onlyAdmin {
        authorizedHospitals[hospital] = true;
        emit HospitalStatusChanged(hospital, true);
    }

    function unauthorizeHospital(address hospital) external onlyAdmin {
        authorizedHospitals[hospital] = false;
        emit HospitalStatusChanged(hospital, false);
    }

    function authorizeManufacturer(address manufacturer) external onlyAdmin {
        authorizedManufacturers[manufacturer] = true;
        emit ManufacturerStatusChanged(manufacturer, true);
    }

    function unauthorizeManufacturer(address manufacturer) external onlyAdmin {
        authorizedManufacturers[manufacturer] = false;
        emit ManufacturerStatusChanged(manufacturer, false);
    }

    function isAuthorizedHospital(address hospital) external view returns (bool) {
        return authorizedHospitals[hospital];
    }

    function isAuthorizedManufacturer(address manufacturer) external view returns (bool) {
        return authorizedManufacturers[manufacturer];
    }

    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid address");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }
}

// ----------------------------------------------------------------------------
// 2. Prescriptions
// ----------------------------------------------------------------------------

/**
 * @title Prescriptions
 * @dev Stores prescription data. Only the Manager contract can modify state.
 */
contract Prescriptions is IPrescriptionStructs {
    // Variables
    address public managerContract;

    // Note: Redefining struct as per prompt requirement, though Interface usage is cleaner.
    // We maintain the interface for external calls but define logic here.
    struct prescription {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }

    struct patient {
        uint256 currentId;
        mapping(uint256 => prescription) prescriptions;
    }

    mapping(address => patient) private patients;

    // Modifiers
    modifier onlyManager() {
        require(msg.sender == managerContract, "Caller is not the manager");
        _;
    }

    // Functions
    constructor(address managerAddress) {
        require(managerAddress != address(0), "Invalid manager address");
        managerContract = managerAddress;
    }

    function _prescribe(
        address doctor,
        address patientAddr,
        string memory _medicine,
        uint256 _dose
    ) external onlyManager returns (uint256) {
        // Access storage
        patient storage p = patients[patientAddr];
        
        // Create struct
        prescription memory newPrescription = prescription({
            time: block.timestamp,
            doctor: doctor,
            medicine: _medicine,
            dose: _dose,
            valid: true
        });

        // Update state
        p.currentId++;
        p.prescriptions[p.currentId] = newPrescription;

        return p.currentId;
    }

    function _getPrescription(address patientAddr, uint256 id) external view onlyManager returns (prescription memory) {
        require(id > 0 && id <= patients[patientAddr].currentId, "Invalid prescription ID");
        return patients[patientAddr].prescriptions[id];
    }

    function usePrescription(address patientAddr, uint256 id) external onlyManager {
        require(id > 0 && id <= patients[patientAddr].currentId, "Invalid prescription ID");
        require(patients[patientAddr].prescriptions[id].valid, "Prescription already used or invalid");
        
        patients[patientAddr].prescriptions[id].valid = false;
    }
}

// ----------------------------------------------------------------------------
// 3. Hospital Management
// ----------------------------------------------------------------------------

/**
 * @title HospitalManagement
 * @dev Manages doctors, admins, and validates sales for Pharma companies.
 */
contract HospitalManagement is IPrescriptionStructs {
    // Variables
    mapping(address => bool) public admins;
    uint256 internal adminsCount;
    mapping(address => bool) public doctors;
    
    address public prescriptionsContract;
    address public govAuthorizationContract;

    // Struct re-definition as per prompt requirements
    struct prescription {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }

    // Events
    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);
    event DoctorStatusChanged(address indexed account, bool status);
    event SaleAuthorized(uint256 indexed prescriptionId, address indexed patient, bool success);

    // Modifiers
    modifier onlyAdmin() {
        require(admins[msg.sender], "Caller is not a hospital admin");
        _;
    }

    modifier onlyDoctor() {
        require(doctors[msg.sender], "Caller is not a doctor");
        _;
    }

    // Functions
    constructor(address _govAuthorizationContract) {
        require(_govAuthorizationContract != address(0), "Invalid Gov address");
        admins[msg.sender] = true;
        adminsCount = 1;
        govAuthorizationContract = _govAuthorizationContract;
    }

    function addAdmin(address newAdmin) external onlyAdmin {
        require(!admins[newAdmin], "Already an admin");
        admins[newAdmin] = true;
        adminsCount++;
        emit AdminAdded(newAdmin);
    }

    function removeAdmin(address adminAddr) external onlyAdmin {
        require(admins[adminAddr], "Address is not an admin");
        require(adminsCount > 1, "Cannot remove the last admin");
        
        admins[adminAddr] = false;
        adminsCount--;
        emit AdminRemoved(adminAddr);
    }

    function addDoctor(address newDoctor) external onlyAdmin {
        doctors[newDoctor] = true;
        emit DoctorStatusChanged(newDoctor, true);
    }

    function removeDoctor(address doctor) external onlyAdmin {
        doctors[doctor] = false;
        emit DoctorStatusChanged(doctor, false);
    }

    function prescribe(address patient, string memory medicine, uint256 dose) external onlyDoctor returns (uint256) {
        require(prescriptionsContract != address(0), "Prescription contract not set");
        
        uint256 prescriptionId = IPrescriptions(prescriptionsContract)._prescribe(
            msg.sender,
            patient,
            medicine,
            dose
        );
        
        return prescriptionId;
    }

    function getPrescription(address patient, uint256 prescriptionId) external view returns (prescription memory) {
        require(doctors[msg.sender] || msg.sender == patient, "Unauthorized access to prescription");
        require(prescriptionsContract != address(0), "Prescription contract not set");

        // Fetch from external contract using interface
        Prescription memory pData = IPrescriptions(prescriptionsContract)._getPrescription(patient, prescriptionId);
        
        // Map interface struct to local struct
        return prescription({
            time: pData.time,
            doctor: pData.doctor,
            medicine: pData.medicine,
            dose: pData.dose,
            valid: pData.valid
        });
    }

    function authorizeSale(uint256 prescriptionId, address patient, string memory medicine, uint256 amount) external returns (bool) {
        // 1. Check if caller is an authorized manufacturer via Gov contract
        bool isAuthMfg = IAuthorizationCertificates(govAuthorizationContract).isAuthorizedManufacturer(msg.sender);
        require(isAuthMfg, "Caller is not an authorized manufacturer");

        // 2. Fetch prescription
        Prescription memory p = IPrescriptions(prescriptionsContract)._getPrescription(patient, prescriptionId);

        // 3. Validation Logic
        bool namesMatch = keccak256(abi.encodePacked(medicine)) == keccak256(abi.encodePacked(p.medicine));
        
        if (p.valid && namesMatch && amount == p.dose) {
            // Invalidate prescription
            IPrescriptions(prescriptionsContract).usePrescription(patient, prescriptionId);
            emit SaleAuthorized(prescriptionId, patient, true);
            return true;
        } else {
            emit SaleAuthorized(prescriptionId, patient, false);
            return false;
        }
    }

    function setPrescriptionContract(address newPrescriptionContract) external onlyAdmin {
        require(newPrescriptionContract != address(0), "Invalid address");
        prescriptionsContract = newPrescriptionContract;
    }
}

// ----------------------------------------------------------------------------
// 4. Pharma Company
// ----------------------------------------------------------------------------

/**
 * @title PharmaCompany
 * @dev ERC1155 Token representing medicines. Handles sales logic.
 */
contract PharmaCompany is ERC1155, ERC1155Burnable, Ownable {
    // Variables
    mapping(string => uint256) public medicines;
    mapping(uint256 => uint256) public prices;
    address public govAuthorizationContract;

    // Events
    event MedicineMinted(uint256 indexed id, string name, uint256 amount);
    event MedicineSold(uint256 indexed id, address indexed buyer, uint256 amount);
    event PriceUpdated(uint256 indexed id, uint256 newPrice);

    // Constructor
    constructor(address _govAuthorizationContract) 
        ERC1155("https://pharma.com/medicine/") 
        Ownable(msg.sender) 
    {
        require(_govAuthorizationContract != address(0), "Invalid Gov address");
        govAuthorizationContract = _govAuthorizationContract;
    }

    // Functions
    function mint(uint256 id, uint256 amount, bytes memory data, string memory medicineName) public onlyOwner {
        require(id != 0, "ID cannot be zero");
        medicines[medicineName] = id;
        _mint(msg.sender, id, amount, data);
        emit MedicineMinted(id, medicineName, amount);
    }

    function mintBatch(
        uint256[] memory ids, 
        uint256[] memory amounts, 
        bytes memory data, 
        string[] memory medicineNames
    ) public onlyOwner {
        require(ids.length == medicineNames.length, "Length mismatch");
        
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] != 0, "ID cannot be zero");
            medicines[medicineNames[i]] = ids[i];
        }

        _mintBatch(msg.sender, ids, amounts, data);
    }

    function buyMedicine(
        string memory medicineName, 
        address hospital, 
        uint256 prescriptionId, 
        uint256 to, 
        uint256 amount
    ) external payable {
        // 1. Check Hospital Authorization
        bool isAuthHospital = IAuthorizationCertificates(govAuthorizationContract).isAuthorizedHospital(hospital);
        require(isAuthHospital, "Invalid or unauthorized hospital");

        uint256 medId = medicines[medicineName];
        require(medId != 0, "Medicine does not exist");

        // 2. Check Availability (Owner is the PharmaCompany/Admin)
        // Note: tokens are held by the contract owner (the manufacturer) until sold
        require(balanceOf(owner(), medId) >= amount, "Insufficient stock");

        // 3. Check Payment
        require(msg.value == amount * prices[medId], "Incorrect ETH value sent");

        // 4. Authorize Sale (External Call to Hospital)
        // The hospital contract will check if *this* contract (PharmaCompany) is an authorized manufacturer
        bool saleAuthorized = IHospitalManagement(hospital).authorizeSale(
            prescriptionId, 
            address(uint160(to)), // Casting uint256 to address as per 'to' standard
            medicineName, 
            amount
        );

        // If authorization works, transfer tokens
        if (saleAuthorized) {
            _safeTransferFrom(owner(), address(uint160(to)), medId, amount, bytes(medicineName));
            emit MedicineSold(medId, address(uint160(to)), amount);
        } else {
            // Best practice: Revert to refund ETH if sale is not authorized
            revert("Sale not authorized by hospital");
        }
    }

    function updatePrice(uint256 id, uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        prices[id] = newPrice;
        emit PriceUpdated(id, newPrice);
    }
}