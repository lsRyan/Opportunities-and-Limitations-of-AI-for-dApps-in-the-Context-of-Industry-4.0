// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import OpenZeppelin contracts
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AuthorizationCertificates
 * @notice Manages authorization certificates for hospitals and manufacturers
 * @dev Centralized authorization management with admin control
 */
contract AuthorizationCertificates {
    address public admin;
    
    mapping(address => bool) internal authorizedHospitals;
    mapping(address => bool) internal authorizedManufacturers;
    
    event HospitalAuthorized(address indexed hospital);
    event HospitalUnauthorized(address indexed hospital);
    event ManufacturerAuthorized(address indexed manufacturer);
    event ManufacturerUnauthorized(address indexed manufacturer);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    
    error Unauthorized();
    error InvalidAddress();
    
    /**
     * @notice Initialize the contract with the deployer as admin
     */
    constructor() {
        admin = msg.sender;
        emit AdminChanged(address(0), msg.sender);
    }
    
    /**
     * @notice Authorize a hospital address
     * @param hospital The address of the hospital to authorize
     */
    function authorizeHospital(address hospital) external {
        if (msg.sender != admin) revert Unauthorized();
        if (hospital == address(0)) revert InvalidAddress();
        
        authorizedHospitals[hospital] = true;
        emit HospitalAuthorized(hospital);
    }
    
    /**
     * @notice Remove authorization from a hospital address
     * @param hospital The address of the hospital to unauthorize
     */
    function unauthorizeHospital(address hospital) external {
        if (msg.sender != admin) revert Unauthorized();
        if (hospital == address(0)) revert InvalidAddress();
        
        authorizedHospitals[hospital] = false;
        emit HospitalUnauthorized(hospital);
    }
    
    /**
     * @notice Authorize a manufacturer address
     * @param manufacturer The address of the manufacturer to authorize
     */
    function authorizeManufacturer(address manufacturer) external {
        if (msg.sender != admin) revert Unauthorized();
        if (manufacturer == address(0)) revert InvalidAddress();
        
        authorizedManufacturers[manufacturer] = true;
        emit ManufacturerAuthorized(manufacturer);
    }
    
    /**
     * @notice Remove authorization from a manufacturer address
     * @param manufacturer The address of the manufacturer to unauthorize
     */
    function unauthorizeManufacturer(address manufacturer) external {
        if (msg.sender != admin) revert Unauthorized();
        if (manufacturer == address(0)) revert InvalidAddress();
        
        authorizedManufacturers[manufacturer] = false;
        emit ManufacturerUnauthorized(manufacturer);
    }
    
    /**
     * @notice Check if a hospital is authorized
     * @param hospital The address of the hospital to check
     * @return bool True if the hospital is authorized
     */
    function isAuthorizedHospital(address hospital) external view returns (bool) {
        return authorizedHospitals[hospital];
    }
    
    /**
     * @notice Check if a manufacturer is authorized
     * @param manufacturer The address of the manufacturer to check
     * @return bool True if the manufacturer is authorized
     */
    function isAuthorizedManufacturer(address manufacturer) external view returns (bool) {
        return authorizedManufacturers[manufacturer];
    }
    
    /**
     * @notice Transfer admin rights to a new address
     * @param newAdmin The address of the new admin
     */
    function changeAdmin(address newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        if (newAdmin == address(0)) revert InvalidAddress();
        
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }
}

/**
 * @title Prescriptions
 * @notice Manages patient prescriptions with validity tracking
 * @dev Stores prescriptions in nested mappings for efficient patient-based lookup
 */
contract Prescriptions {
    address public managerContract;
    
    struct PrescriptionData {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }
    
    struct Patient {
        uint256 currentId;
        mapping(uint256 => PrescriptionData) prescriptions;
    }
    
    mapping(address => Patient) private patients;
    
    event PrescriptionCreated(
        address indexed patient,
        uint256 indexed id,
        address doctor,
        string medicine,
        uint256 dose
    );
    event PrescriptionUsed(address indexed patient, uint256 indexed id);
    
    error Unauthorized();
    error InvalidPrescriptionId();
    error PrescriptionAlreadyUsed();
    
    /**
     * @notice Initialize the contract with manager contract address
     * @param managerAddress The address of the hospital management contract
     */
    constructor(address managerAddress) {
        managerContract = managerAddress;
    }
    
    /**
     * @notice Create a new prescription for a patient
     * @dev Only callable by manager contract
     * @param doctor The address of the prescribing doctor
     * @param patient The address of the patient
     * @param _medicine The name of the prescribed medicine
     * @param _dose The prescribed dose amount
     * @return uint256 The ID of the created prescription
     */
    function _prescribe(
        address doctor,
        address patient,
        string memory _medicine,
        uint256 _dose
    ) external returns (uint256) {
        if (msg.sender != managerContract) revert Unauthorized();
        
        Patient storage patientData = patients[patient];
        patientData.currentId++;
        
        patientData.prescriptions[patientData.currentId] = PrescriptionData({
            time: block.timestamp,
            doctor: doctor,
            medicine: _medicine,
            dose: _dose,
            valid: true
        });
        
        emit PrescriptionCreated(patient, patientData.currentId, doctor, _medicine, _dose);
        return patientData.currentId;
    }
    
    /**
     * @notice Retrieve a specific prescription
     * @dev Only callable by manager contract
     * @param patient The address of the patient
     * @param id The ID of the prescription to retrieve
     * @return PrescriptionData The prescription data
     */
    function _getPrescription(
        address patient,
        uint256 id
    ) external view returns (PrescriptionData memory) {
        if (msg.sender != managerContract) revert Unauthorized();
        if (id == 0 || id > patients[patient].currentId) revert InvalidPrescriptionId();
        
        return patients[patient].prescriptions[id];
    }
    
    /**
     * @notice Mark a prescription as used
     * @dev Only callable by manager contract
     * @param patient The address of the patient
     * @param id The ID of the prescription to mark as used
     */
    function usePrescription(address patient, uint256 id) external {
        if (msg.sender != managerContract) revert Unauthorized();
        if (id == 0 || id > patients[patient].currentId) revert InvalidPrescriptionId();
        
        PrescriptionData storage prescription = patients[patient].prescriptions[id];
        if (!prescription.valid) revert PrescriptionAlreadyUsed();
        
        prescription.valid = false;
        emit PrescriptionUsed(patient, id);
    }
}

/**
 * @title HospitalManagement
 * @notice Manages hospital operations including doctors and prescriptions
 * @dev Acts as the manager contract for the Prescriptions contract
 */
contract HospitalManagement {
    mapping(address => bool) public admins;
    uint256 internal adminsCount;
    mapping(address => bool) public doctors;
    
    address public prescriptionsContract;
    address public govAuthorizationContract;
    
    struct Prescription {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }
    
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event DoctorAdded(address indexed doctor);
    event DoctorRemoved(address indexed doctor);
    event PrescriptionContractUpdated(address indexed newContract);
    
    error Unauthorized();
    error LastAdmin();
    error InvalidAddress();
    
    /**
     * @notice Initialize the hospital management contract
     * @param _govAuthorizationContract Address of the authorization certificates contract
     */
    constructor(address _govAuthorizationContract) {
        admins[msg.sender] = true;
        adminsCount = 1;
        govAuthorizationContract = _govAuthorizationContract;
        emit AdminAdded(msg.sender);
    }
    
    /**
     * @notice Add a new admin
     * @param newAdmin The address of the new admin
     */
    function addAdmin(address newAdmin) external {
        if (!admins[msg.sender]) revert Unauthorized();
        if (newAdmin == address(0)) revert InvalidAddress();
        
        admins[newAdmin] = true;
        adminsCount++;
        emit AdminAdded(newAdmin);
    }
    
    /**
     * @notice Remove an existing admin
     * @param admin The address of the admin to remove
     */
    function removeAdmin(address admin) external {
        if (!admins[msg.sender]) revert Unauthorized();
        if (adminsCount <= 1) revert LastAdmin();
        
        admins[admin] = false;
        adminsCount--;
        emit AdminRemoved(admin);
    }
    
    /**
     * @notice Add a new doctor
     * @param newDoctor The address of the new doctor
     */
    function addDoctor(address newDoctor) external {
        if (!admins[msg.sender]) revert Unauthorized();
        if (newDoctor == address(0)) revert InvalidAddress();
        
        doctors[newDoctor] = true;
        emit DoctorAdded(newDoctor);
    }
    
    /**
     * @notice Remove an existing doctor
     * @param doctor The address of the doctor to remove
     */
    function removeDoctor(address doctor) external {
        if (!admins[msg.sender]) revert Unauthorized();
        
        doctors[doctor] = false;
        emit DoctorRemoved(doctor);
    }
    
    /**
     * @notice Create a new prescription for a patient
     * @param patient The address of the patient
     * @param medicine The name of the prescribed medicine
     * @param dose The prescribed dose amount
     * @return uint256 The ID of the created prescription
     */
    function prescribe(
        address patient,
        string memory medicine,
        uint256 dose
    ) external returns (uint256) {
        if (!doctors[msg.sender]) revert Unauthorized();
        
        return Prescriptions(prescriptionsContract)._prescribe(
            msg.sender,
            patient,
            medicine,
            dose
        );
    }
    
    /**
     * @notice Retrieve a prescription for viewing
     * @param patient The address of the patient
     * @param prescriptionId The ID of the prescription to retrieve
     * @return Prescription The prescription data
     */
    function getPrescription(
        address patient,
        uint256 prescriptionId
    ) external view returns (Prescription memory) {
        if (!doctors[msg.sender] && msg.sender != patient) revert Unauthorized();
        
        Prescriptions.PrescriptionData memory data = Prescriptions(prescriptionsContract)
            ._getPrescription(patient, prescriptionId);
            
        return Prescription({
            time: data.time,
            doctor: data.doctor,
            medicine: data.medicine,
            dose: data.dose,
            valid: data.valid
        });
    }
    
    /**
     * @notice Authorize a medicine sale based on prescription validity
     * @dev Called by PharmaCompany contract to validate prescriptions
     * @param prescriptionId The ID of the prescription to validate
     * @param patient The address of the patient
     * @param medicine The name of the medicine to verify
     * @param amount The amount of medicine to verify
     * @return bool True if the sale is authorized
     */
    function authorizeSale(
        uint256 prescriptionId,
        address patient,
        string memory medicine,
        uint256 amount
    ) external returns (bool) {
        bool isAuthorized = AuthorizationCertificates(govAuthorizationContract)
            .isAuthorizedManufacturer(msg.sender);
        if (!isAuthorized) revert Unauthorized();
        
        Prescriptions.PrescriptionData memory data = Prescriptions(prescriptionsContract)
            ._getPrescription(patient, prescriptionId);
        
        if (
            data.valid &&
            keccak256(bytes(data.medicine)) == keccak256(bytes(medicine)) &&
            data.dose == amount
        ) {
            Prescriptions(prescriptionsContract).usePrescription(patient, prescriptionId);
            return true;
        }
        
        return false;
    }
    
    /**
     * @notice Update the prescriptions contract address
     * @param newPrescriptionContract The new prescriptions contract address
     */
    function setPrescriptionContract(address newPrescriptionContract) external {
        if (!admins[msg.sender]) revert Unauthorized();
        if (newPrescriptionContract == address(0)) revert InvalidAddress();
        
        prescriptionsContract = newPrescriptionContract;
        emit PrescriptionContractUpdated(newPrescriptionContract);
    }
}

/**
 * @title PharmaCompany
 * @notice ERC1155-based medicine token contract with prescription validation
 * @dev Extends OpenZeppelin ERC1155 for medicine token management
 */
contract PharmaCompany is ERC1155, ERC1155Burnable, Ownable {
    mapping(string => uint256) public medicines;
    mapping(uint256 => uint256) public prices;
    address public govAuthorizationContract;
    
    event MedicineMinted(uint256 indexed id, string name, uint256 amount);
    event MedicineBatchMinted(uint256[] ids, string[] names, uint256[] amounts);
    event PriceUpdated(uint256 indexed id, uint256 newPrice);
    event MedicinePurchased(
        address indexed buyer,
        uint256 indexed medicineId,
        uint256 amount,
        uint256 totalPrice
    );
    
    error UnauthorizedHospital();
    error InvalidMedicineId();
    error InsufficientBalance();
    error IncorrectPayment();
    error InvalidAmount();
    error InvalidPrice();
    error Unauthorized();
    
    /**
     * @notice Initialize the PharmaCompany contract
     * @param _govAuthorizationContract Address of the authorization certificates contract
     */
    constructor(address _govAuthorizationContract)
        ERC1155("https://pharma.com/medicine/")
        Ownable(msg.sender)
    {
        govAuthorizationContract = _govAuthorizationContract;
    }
    
    /**
     * @notice Mint new medicine tokens
     * @param id The ID of the medicine token to mint
     * @param amount The amount of tokens to mint
     * @param data Additional data to pass
     * @param medicineName The name of the medicine
     */
    function mint(
        uint256 id,
        uint256 amount,
        bytes memory data,
        string memory medicineName
    ) public onlyOwner {
        if (id == 0) revert InvalidMedicineId();
        
        medicines[medicineName] = id;
        _mint(msg.sender, id, amount, data);
        emit MedicineMinted(id, medicineName, amount);
    }
    
    /**
     * @notice Batch mint multiple medicine tokens
     * @param ids Array of medicine token IDs to mint
     * @param amounts Array of amounts to mint for each ID
     * @param data Additional data to pass
     * @param medicineNames Array of medicine names corresponding to IDs
     */
    function mintBatch(
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data,
        string[] memory medicineNames
    ) public onlyOwner {
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == 0) revert InvalidMedicineId();
            medicines[medicineNames[i]] = ids[i];
        }
        
        _mintBatch(msg.sender, ids, amounts, data);
        emit MedicineBatchMinted(ids, medicineNames, amounts);
    }
    
    /**
     * @notice Purchase medicine using a valid prescription
     * @param medicineName The name of the medicine to purchase
     * @param hospital The address of the hospital that issued the prescription
     * @param prescriptionId The ID of the prescription
     * @param to The address to send the medicine tokens to
     * @param amount The amount of medicine to purchase
     */
    function buyMedicine(
        string memory medicineName,
        address hospital,
        uint256 prescriptionId,
        address to,
        uint256 amount
    ) external payable {
        bool isAuthorized = AuthorizationCertificates(govAuthorizationContract)
            .isAuthorizedHospital(hospital);
        if (!isAuthorized) revert UnauthorizedHospital();
        
        uint256 medicineId = medicines[medicineName];
        if (medicineId == 0) revert InvalidMedicineId();
        
        if (balanceOf(owner(), medicineId) < amount) revert InsufficientBalance();
        
        uint256 totalPrice = prices[medicineId] * amount;
        if (msg.value != totalPrice) revert IncorrectPayment();
        
        bool saleAuthorized = HospitalManagement(hospital).authorizeSale(
            prescriptionId,
            to,
            medicineName,
            amount
        );
        
        if (!saleAuthorized) revert Unauthorized();
        
        _safeTransferFrom(owner(), to, medicineId, amount, bytes(medicineName));
        
        // Transfer payment to contract owner
        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "Transfer failed");
        
        emit MedicinePurchased(to, medicineId, amount, totalPrice);
    }
    
    /**
     * @notice Update the price of a medicine
     * @param id The ID of the medicine token
     * @param newPrice The new price in wei per unit
     */
    function updatePrice(uint256 id, uint256 newPrice) external onlyOwner {
        if (newPrice == 0) revert InvalidPrice();
        
        prices[id] = newPrice;
        emit PriceUpdated(id, newPrice);
    }
}