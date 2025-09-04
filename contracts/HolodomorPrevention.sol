// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GrainRequisition.sol";
import "./LaborCompensation.sol";
import "./QuotaGovernance.sol";
import "./FoodProductionOracle.sol";
import "./ExportController.sol";
import "./EmergencyPause.sol";

contract HolodomorPrevention {
    address public owner;
    bool public systemPaused;
    
    GrainRequisition public grainRequisition;
    LaborCompensation public laborCompensation;
    QuotaGovernance public quotaGovernance;
    FoodProductionOracle public productionOracle;
    ExportController public exportController;
    EmergencyPause public emergencyPause;
    
    struct Stakeholder {
        bool isRegistered;
        bool isFarmer;
        bool isValidator;
        uint256 registrationTime;
        uint256 reputation;
    }
    
    mapping(address => Stakeholder) public stakeholders;
    mapping(address => bool) public reliefRecipients;
    
    uint256 public constant MIN_PRODUCTION_THRESHOLD = 1000000; // tonnes
    uint256 public emergencyReliefFund;
    
    event SystemPaused(address indexed by, uint256 timestamp);
    event SystemResumed(address indexed by, uint256 timestamp);
    event StakeholderRegistered(address indexed stakeholder, bool isFarmer, bool isValidator);
    event EmergencyReliefDistributed(address indexed recipient, uint256 amount);
    event CriticalShortageDetected(uint256 productionLevel, uint256 threshold);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier whenNotPaused() {
        require(!systemPaused, "System is paused");
        _;
    }
    
    modifier onlyRegistered() {
        require(stakeholders[msg.sender].isRegistered, "Not registered stakeholder");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        systemPaused = false;
    }
    
    function initialize(
        address _grainRequisition,
        address _laborCompensation,
        address _quotaGovernance,
        address _productionOracle,
        address _exportController,
        address _emergencyPause
    ) external onlyOwner {
        grainRequisition = GrainRequisition(_grainRequisition);
        laborCompensation = LaborCompensation(_laborCompensation);
        quotaGovernance = QuotaGovernance(_quotaGovernance);
        productionOracle = FoodProductionOracle(_productionOracle);
        exportController = ExportController(_exportController);
        emergencyPause = EmergencyPause(_emergencyPause);
    }
    
    function registerStakeholder(
        address _stakeholder,
        bool _isFarmer,
        bool _isValidator
    ) external whenNotPaused {
        require(!stakeholders[_stakeholder].isRegistered, "Already registered");
        
        stakeholders[_stakeholder] = Stakeholder({
            isRegistered: true,
            isFarmer: _isFarmer,
            isValidator: _isValidator,
            registrationTime: block.timestamp,
            reputation: 100
        });
        
        if (_isValidator) {
            productionOracle.addValidator(_stakeholder);
        }
        
        emit StakeholderRegistered(_stakeholder, _isFarmer, _isValidator);
    }
    
    function checkProductionLevels() external view returns (bool isCritical, uint256 currentProduction) {
        currentProduction = productionOracle.getTotalProduction();
        isCritical = currentProduction < MIN_PRODUCTION_THRESHOLD;
        return (isCritical, currentProduction);
    }
    
    function triggerEmergencyProtocol() external onlyRegistered {
        (bool isCritical, uint256 production) = this.checkProductionLevels();
        
        if (isCritical) {
            emergencyPause.initiateEmergencyPause();
            grainRequisition.pauseRequisitions();
            exportController.pauseAllExports();
            laborCompensation.pauseDeportations();
            
            emit CriticalShortageDetected(production, MIN_PRODUCTION_THRESHOLD);
        }
    }
    
    function pauseSystem() external {
        require(
            msg.sender == owner || 
            msg.sender == address(emergencyPause),
            "Unauthorized"
        );
        systemPaused = true;
        
        grainRequisition.pauseRequisitions();
        exportController.pauseAllExports();
        laborCompensation.pauseDeportations();
        
        emit SystemPaused(msg.sender, block.timestamp);
    }
    
    function resumeSystem() external onlyOwner {
        require(systemPaused, "System not paused");
        
        (bool isCritical, ) = this.checkProductionLevels();
        require(!isCritical, "Cannot resume during critical shortage");
        
        systemPaused = false;
        emit SystemResumed(msg.sender, block.timestamp);
    }
    
    function distributeEmergencyRelief(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner whenNotPaused {
        require(recipients.length == amounts.length, "Array length mismatch");
        require(emergencyReliefFund > 0, "No relief funds available");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(totalAmount <= emergencyReliefFund, "Insufficient relief funds");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            reliefRecipients[recipients[i]] = true;
            emergencyReliefFund -= amounts[i];
            payable(recipients[i]).transfer(amounts[i]);
            emit EmergencyReliefDistributed(recipients[i], amounts[i]);
        }
    }
    
    function fundEmergencyRelief() external payable {
        emergencyReliefFund += msg.value;
    }
    
    function updateStakeholderReputation(address _stakeholder, int256 _change) external {
        require(
            msg.sender == address(productionOracle) ||
            msg.sender == address(quotaGovernance),
            "Unauthorized reputation update"
        );
        
        require(stakeholders[_stakeholder].isRegistered, "Stakeholder not registered");
        
        if (_change > 0) {
            stakeholders[_stakeholder].reputation += uint256(_change);
        } else {
            uint256 decrease = uint256(-_change);
            if (stakeholders[_stakeholder].reputation > decrease) {
                stakeholders[_stakeholder].reputation -= decrease;
            } else {
                stakeholders[_stakeholder].reputation = 0;
            }
        }
    }
    
    function getSystemStatus() external view returns (
        bool isPaused,
        bool requisitionsPaused,
        bool exportsPaused,
        bool deportationsPaused,
        uint256 currentProduction,
        uint256 reliefFunds
    ) {
        isPaused = systemPaused;
        requisitionsPaused = grainRequisition.requisitionsPaused();
        exportsPaused = exportController.exportsPaused();
        deportationsPaused = laborCompensation.deportationsPaused();
        currentProduction = productionOracle.getTotalProduction();
        reliefFunds = emergencyReliefFund;
    }
}