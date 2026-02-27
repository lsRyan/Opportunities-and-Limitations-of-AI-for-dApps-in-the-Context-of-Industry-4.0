// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Prescriptions
 * @notice Manages medical prescriptions for patients
 * @dev Only callable by authorized manager contract
 */
contract Prescriptions {
    /// @notice Address of the manager contract authorized to interact with prescriptions
    address public managerContract;

    /// @notice Represents a medical prescription
    struct Prescription {
        uint256 time;        // Timestamp when prescription was created
        address doctor;      // Address of prescribing doctor
        string medicine;     // Name of prescribed medicine
        uint256 dose;        // Number of units prescribed
        bool valid;          // Whether prescription can still be used
    }

    /// @notice Represents a patient's prescription records
    struct Patient {
        uint256 currentId;   // Last prescription ID for this patient
        mapping(uint256 => Prescription) prescriptions;  // Prescription ID to Prescription mapping
    }

    /// @notice Maps patient addresses to their prescription records
    mapping(address => Patient) private patients;

    /// @notice Emitted when a new prescription is created
    event PrescriptionCreated(address indexed patient, uint256 indexed prescriptionId, address indexed doctor, string medicine, uint256 dose);
    
    /// @notice Emitted when a prescription is used
    event PrescriptionUsed(address indexed patient, uint256 indexed prescriptionId);

    /**
     * @notice Constructor sets the manager contract address
     * @param managerAddress Address of the hospital management contract
     */
    constructor(address managerAddress) {
        require(managerAddress != address(0), "Invalid manager address");
        managerContract = managerAddress;
    }

    /**
     * @notice Creates a new prescription for a patient
     * @param doctor Address of the prescribing doctor
     * @param patient Address of the patient
     * @param _medicine Name of the prescribed medicine
     * @param _dose Number of units prescribed
     * @return The ID of the newly created prescription
     */
    function _prescribe(
        address doctor,
        address patient,
        string memory _medicine,
        uint256 _dose
    ) external returns (uint256) {
        require(msg.sender == managerContract, "Only manager contract can call");
        require(doctor != address(0), "Invalid doctor address");
        require(patient != address(0), "Invalid patient address");
        require(bytes(_medicine).length > 0, "Medicine name cannot be empty");
        require(_dose > 0, "Dose must be greater than zero");

        // Increment prescription ID for patient
        patients[patient].currentId++;
        uint256 newPrescriptionId = patients[patient].currentId;

        // Create new prescription
        patients[patient].prescriptions[newPrescriptionId] = Prescription({
            time: block.timestamp,
            doctor: doctor,
            medicine: _medicine,
            dose: _dose,
            valid: true
        });

        emit PrescriptionCreated(patient, newPrescriptionId, doctor, _medicine, _dose);

        return newPrescriptionId;
    }

    /**
     * @notice Retrieves a prescription for a patient
     * @param patient Address of the patient
     * @param id Prescription ID
     * @return The prescription data
     */
    function _getPrescription(
        address patient,
        uint256 id
    ) external view returns (Prescription memory) {
        require(msg.sender == managerContract, "Only manager contract can call");
        require(id > 0 && id <= patients[patient].currentId, "Invalid prescription ID");

        return patients[patient].prescriptions[id];
    }

    /**
     * @notice Marks a prescription as used (invalid)
     * @param patient Address of the patient
     * @param id Prescription ID
     */
    function usePrescription(address patient, uint256 id) external {
        require(msg.sender == managerContract, "Only manager contract can call");
        require(id > 0 && id <= patients[patient].currentId, "Invalid prescription ID");

        patients[patient].prescriptions[id].valid = false;

        emit PrescriptionUsed(patient, id);
    }
}

/**
 * @title AuthorizationCertificates
 * @notice Manages authorization of hospitals and manufacturers by government
 * @dev Centralized authorization system with admin control
 */
contract AuthorizationCertificates {
    /// @notice Admin address with authorization privileges
    address public admin;

    /// @notice Maps hospital addresses to authorization status
    mapping(address => bool) internal authorizedHospitals;

    /// @notice Maps manufacturer addresses to authorization status
    mapping(address => bool) internal authorizedManufacturers;

    /// @notice Emitted when a hospital is authorized
    event HospitalAuthorized(address indexed hospital);
    
    /// @notice Emitted when a hospital is unauthorized
    event HospitalUnauthorized(address indexed hospital);
    
    /// @notice Emitted when a manufacturer is authorized
    event ManufacturerAuthorized(address indexed manufacturer);
    
    /// @notice Emitted when a manufacturer is unauthorized
    event ManufacturerUnauthorized(address indexed manufacturer);
    
    /// @notice Emitted when admin is changed
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    /**
     * @notice Constructor sets deployer as admin
     */
    constructor() {
        admin = msg.sender;
    }

    /// @notice Modifier to restrict access to admin only
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call");
        _;
    }

    /**
     * @notice Authorizes a hospital
     * @param hospital Address of the hospital to authorize
     */
    function authorizeHospital(address hospital) external onlyAdmin {
        require(hospital != address(0), "Invalid hospital address");
        authorizedHospitals[hospital] = true;
        emit HospitalAuthorized(hospital);
    }

    /**
     * @notice Unauthorizes a hospital
     * @param hospital Address of the hospital to unauthorize
     */
    function unauthorizeHospital(address hospital) external onlyAdmin {
        authorizedHospitals[hospital] = false;
        emit HospitalUnauthorized(hospital);
    }

    /**
     * @notice Authorizes a manufacturer
     * @param manufacturer Address of the manufacturer to authorize
     */
    function authorizeManufacturer(address manufacturer) external onlyAdmin {
        require(manufacturer != address(0), "Invalid manufacturer address");
        authorizedManufacturers[manufacturer] = true;
        emit ManufacturerAuthorized(manufacturer);
    }

    /**
     * @notice Unauthorizes a manufacturer
     * @param manufacturer Address of the manufacturer to unauthorize
     */
    function unauthorizeManufacturer(address manufacturer) external onlyAdmin {
        authorizedManufacturers[manufacturer] = false;
        emit ManufacturerUnauthorized(manufacturer);
    }

    /**
     * @notice Checks if a hospital is authorized
     * @param hospital Address of the hospital
     * @return True if hospital is authorized
     */
    function isAuthorizedHospital(address hospital) external view returns (bool) {
        return authorizedHospitals[hospital];
    }

    /**
     * @notice Checks if a manufacturer is authorized
     * @param manufacturer Address of the manufacturer
     * @return True if manufacturer is authorized
     */
    function isAuthorizedManufacturer(address manufacturer) external view returns (bool) {
        return authorizedManufacturers[manufacturer];
    }

    /**
     * @notice Changes the admin address
     * @param newAdmin Address of the new admin
     */
    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin address");
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }
}

/**
 * @title PharmaCompany
 * @notice ERC1155 token contract for managing medicine inventory and sales
 * @dev Implements OpenZeppelin's ERC1155 with custom medicine marketplace functionality
 */
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PharmaCompany is ERC1155, ERC1155Burnable, Ownable {
    /// @notice Maps medicine names to their token IDs
    mapping(string => uint256) public medicines;

    /// @notice Maps medicine token IDs to their prices in wei
    mapping(uint256 => uint256) public prices;

    /// @notice Address of government authorization contract
    address public govAuthorizationContract;

    /// @notice Emitted when medicine is purchased
    event MedicinePurchased(address indexed buyer, string medicineName, uint256 amount, uint256 totalPrice);
    
    /// @notice Emitted when medicine price is updated
    event PriceUpdated(uint256 indexed medicineId, uint256 newPrice);

    /**
     * @notice Constructor initializes ERC1155 with base URI and sets government contract
     * @param _govAuthorizationContract Address of the authorization certificate contract
     */
    constructor(address _govAuthorizationContract) 
        ERC1155("https://pharma.com/medicine/") 
        Ownable(msg.sender) 
    {
        require(_govAuthorizationContract != address(0), "Invalid gov contract address");
        govAuthorizationContract = _govAuthorizationContract;
    }

    /**
     * @notice Mints a new medicine token
     * @param id Token ID for the medicine
     * @param amount Amount to mint
     * @param data Additional data
     * @param medicineName Name of the medicine
     */
    function mint(
        uint256 id,
        uint256 amount,
        bytes memory data,
        string memory medicineName
    ) public onlyOwner {
        require(id != 0, "ID cannot be zero");
        require(bytes(medicineName).length > 0, "Medicine name cannot be empty");
        
        medicines[medicineName] = id;
        _mint(msg.sender, id, amount, data);
    }

    /**
     * @notice Mints multiple medicine tokens in batch
     * @param ids Array of token IDs
     * @param amounts Array of amounts to mint
     * @param data Additional data
     * @param medicineNames Array of medicine names
     */
    function mintBatch(
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data,
        string[] memory medicineNames
    ) public onlyOwner {
        require(ids.length == medicineNames.length, "IDs and names length mismatch");
        
        // Check no ID is zero
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] != 0, "ID cannot be zero");
            require(bytes(medicineNames[i]).length > 0, "Medicine name cannot be empty");
            medicines[medicineNames[i]] = ids[i];
        }
        
        _mintBatch(msg.sender, ids, amounts, data);
    }

    /**
     * @notice Allows patients to buy medicine with valid prescription
     * @param medicineName Name of the medicine to purchase
     * @param hospital Address of the hospital that issued prescription
     * @param prescriptionId ID of the prescription
     * @param to Address to receive the medicine tokens
     * @param amount Amount of medicine to purchase
     */
    function buyMedicine(
        string memory medicineName,
        address hospital,
        uint256 prescriptionId,
        address to,
        uint256 amount
    ) external payable {
        // Check hospital is authorized
        (bool success, bytes memory data) = govAuthorizationContract.call(
            abi.encodeWithSignature("isAuthorizedHospital(address)", hospital)
        );
        require(success && abi.decode(data, (bool)), "Hospital not authorized");

        uint256 medicineId = medicines[medicineName];
        require(medicineId != 0, "Medicine not found");

        // Check medicine is available
        require(balanceOf(owner(), medicineId) > 0, "Medicine not available");

        // Check payment is correct
        uint256 totalPrice = amount * prices[medicineId];
        require(msg.value == totalPrice, "Incorrect payment amount");

        // Authorize sale through hospital
        (bool authSuccess, bytes memory authData) = hospital.call(
            abi.encodeWithSignature(
                "authorizeSale(uint256,address,string,uint256)",
                prescriptionId,
                to,
                medicineName,
                amount
            )
        );
        require(authSuccess, "Authorization call failed");
        require(abi.decode(authData, (bool)), "Sale not authorized");

        // Transfer medicine tokens
        _safeTransferFrom(owner(), to, medicineId, amount, bytes(medicineName));

        emit MedicinePurchased(to, medicineName, amount, totalPrice);
    }

    /**
     * @notice Updates the price of a medicine
     * @param id Medicine token ID
     * @param newPrice New price in wei
     */
    function updatePrice(uint256 id, uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than zero");
        prices[id] = newPrice;
        emit PriceUpdated(id, newPrice);
    }
}

/**
 * @title HospitalManagement
 * @notice Manages hospital staff and prescription workflow
 * @dev Integrates with Prescriptions contract and authorization system
 */
contract HospitalManagement {
    /// @notice Maps addresses to admin status
    mapping(address => bool) public admins;

    /// @notice Number of active admins
    uint256 internal adminsCount;

    /// @notice Maps addresses to doctor status
    mapping(address => bool) public doctors;

    /// @notice Address of the prescriptions contract
    address public prescriptionsContract;

    /// @notice Address of government authorization contract
    address public govAuthorizationContract;

    /// @notice Represents a medical prescription (matches Prescriptions contract)
    struct Prescription {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }

    /// @notice Emitted when admin is added
    event AdminAdded(address indexed admin);
    
    /// @notice Emitted when admin is removed
    event AdminRemoved(address indexed admin);
    
    /// @notice Emitted when doctor is added
    event DoctorAdded(address indexed doctor);
    
    /// @notice Emitted when doctor is removed
    event DoctorRemoved(address indexed doctor);
    
    /// @notice Emitted when prescription contract is updated
    event PrescriptionContractUpdated(address indexed newContract);

    /// @notice Modifier to restrict access to admins only
    modifier onlyAdmin() {
        require(admins[msg.sender], "Only admin can call");
        _;
    }

    /// @notice Modifier to restrict access to doctors only
    modifier onlyDoctor() {
        require(doctors[msg.sender], "Only doctor can call");
        _;
    }

    /**
     * @notice Constructor sets deployer as first admin and initializes gov contract
     * @param _govAuthorizationContract Address of the authorization certificate contract
     */
    constructor(address _govAuthorizationContract) {
        require(_govAuthorizationContract != address(0), "Invalid gov contract address");
        admins[msg.sender] = true;
        adminsCount = 1;
        govAuthorizationContract = _govAuthorizationContract;
    }

    /**
     * @notice Adds a new admin to the hospital
     * @param newAdmin Address of the new admin
     */
    function addAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin address");
        require(!admins[newAdmin], "Already an admin");
        
        adminsCount++;
        admins[newAdmin] = true;
        emit AdminAdded(newAdmin);
    }

    /**
     * @notice Removes an admin from the hospital
     * @param admin Address of the admin to remove
     */
    function removeAdmin(address admin) external onlyAdmin {
        require(adminsCount > 1, "Cannot remove last admin");
        require(admins[admin], "Not an admin");
        
        adminsCount--;
        admins[admin] = false;
        emit AdminRemoved(admin);
    }

    /**
     * @notice Adds a new doctor to the hospital
     * @param newDoctor Address of the new doctor
     */
    function addDoctor(address newDoctor) external onlyAdmin {
        require(newDoctor != address(0), "Invalid doctor address");
        require(!doctors[newDoctor], "Already a doctor");
        
        doctors[newDoctor] = true;
        emit DoctorAdded(newDoctor);
    }

    /**
     * @notice Removes a doctor from the hospital
     * @param doctor Address of the doctor to remove
     */
    function removeDoctor(address doctor) external onlyAdmin {
        require(doctors[doctor], "Not a doctor");
        
        doctors[doctor] = false;
        emit DoctorRemoved(doctor);
    }

    /**
     * @notice Creates a new prescription for a patient
     * @param patient Address of the patient
     * @param medicine Name of the medicine
     * @param dose Number of units prescribed
     * @return The prescription ID
     */
    function prescribe(
        address patient,
        string memory medicine,
        uint256 dose
    ) external onlyDoctor returns (uint256) {
        require(prescriptionsContract != address(0), "Prescription contract not set");
        
        (bool success, bytes memory data) = prescriptionsContract.call(
            abi.encodeWithSignature(
                "_prescribe(address,address,string,uint256)",
                msg.sender,
                patient,
                medicine,
                dose
            )
        );
        require(success, "Prescription creation failed");
        
        uint256 prescriptionId = abi.decode(data, (uint256));
        return prescriptionId;
    }

    /**
     * @notice Retrieves a prescription
     * @param patient Address of the patient
     * @param prescriptionId ID of the prescription
     * @return The prescription data
     */
    function getPrescription(
        address patient,
        uint256 prescriptionId
    ) external view returns (Prescription memory) {
        require(
            doctors[msg.sender] || msg.sender == patient,
            "Not authorized to view prescription"
        );
        require(prescriptionsContract != address(0), "Prescription contract not set");
        
        (bool success, bytes memory data) = prescriptionsContract.staticcall(
            abi.encodeWithSignature(
                "_getPrescription(address,uint256)",
                patient,
                prescriptionId
            )
        );
        require(success, "Failed to get prescription");
        
        Prescription memory prescription = abi.decode(data, (Prescription));
        return prescription;
    }

    /**
     * @notice Authorizes a medicine sale based on prescription validity
     * @param prescriptionId ID of the prescription
     * @param patient Address of the patient
     * @param medicine Name of the medicine
     * @param amount Amount to purchase
     * @return True if sale is authorized
     */
    function authorizeSale(
        uint256 prescriptionId,
        address patient,
        string memory medicine,
        uint256 amount
    ) external returns (bool) {
        // Check caller is authorized manufacturer
        (bool authSuccess, bytes memory authData) = govAuthorizationContract.call(
            abi.encodeWithSignature("isAuthorizedManufacturer(address)", msg.sender)
        );
        require(authSuccess && abi.decode(authData, (bool)), "Manufacturer not authorized");
        require(prescriptionsContract != address(0), "Prescription contract not set");

        // Get prescription
        (bool success, bytes memory data) = prescriptionsContract.call(
            abi.encodeWithSignature(
                "_getPrescription(address,uint256)",
                patient,
                prescriptionId
            )
        );
        require(success, "Failed to get prescription");
        
        Prescription memory prescription = abi.decode(data, (Prescription));

        // Validate prescription
        if (
            prescription.valid &&
            keccak256(bytes(medicine)) == keccak256(bytes(prescription.medicine)) &&
            amount == prescription.dose
        ) {
            // Mark prescription as used
            (bool useSuccess, ) = prescriptionsContract.call(
                abi.encodeWithSignature(
                    "usePrescription(address,uint256)",
                    patient,
                    prescriptionId
                )
            );
            require(useSuccess, "Failed to use prescription");
            
            return true;
        }
        
        return false;
    }

    /**
     * @notice Sets the prescription contract address
     * @param newPrescriptionContract Address of the new prescription contract
     */
    function setPrescriptionContract(address newPrescriptionContract) external onlyAdmin {
        require(newPrescriptionContract != address(0), "Invalid prescription contract address");
        prescriptionsContract = newPrescriptionContract;
        emit PrescriptionContractUpdated(newPrescriptionContract);
    }
}