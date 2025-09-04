// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract FoodProductionOracle {
    address public owner;
    
    struct ProductionReport {
        uint256 amount;
        uint256 timestamp;
        bytes32 dataHash;
        uint256 validations;
        bool finalized;
    }
    
    struct Validator {
        bool isActive;
        uint256 stake;
        uint256 reputation;
        uint256 lastValidation;
    }
    
    mapping(bytes32 => mapping(uint256 => ProductionReport)) public productionReports;
    mapping(address => Validator) public validators;
    mapping(bytes32 => mapping(uint256 => mapping(address => bool))) public hasValidated;
    mapping(bytes32 => uint256) public latestReportIndex;
    mapping(bytes32 => bytes32) public regionMerkleRoots;
    
    bytes32[] public registeredRegions;
    address[] public validatorList;
    
    uint256 public constant MIN_VALIDATORS = 3;
    uint256 public constant MIN_STAKE = 1000 * 10**18;
    uint256 public constant VALIDATION_THRESHOLD = 66; // 66% consensus required
    uint256 public totalProduction;
    
    bytes32 public globalMerkleRoot;
    
    event ProductionReported(bytes32 region, uint256 amount, uint256 reportIndex);
    event ReportValidated(bytes32 region, uint256 reportIndex, address validator);
    event ReportFinalized(bytes32 region, uint256 reportIndex, uint256 finalAmount);
    event ValidatorAdded(address validator);
    event ValidatorSlashed(address validator, uint256 penalty);
    event MerkleRootUpdated(bytes32 newRoot);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyValidator() {
        require(validators[msg.sender].isActive, "Not active validator");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function addValidator(address _validator) external {
        require(msg.sender == owner || validators[msg.sender].isActive, "Unauthorized");
        require(!validators[_validator].isActive, "Already validator");
        
        validators[_validator] = Validator({
            isActive: true,
            stake: 0,
            reputation: 100,
            lastValidation: block.timestamp
        });
        
        validatorList.push(_validator);
        emit ValidatorAdded(_validator);
    }
    
    function stakeAsValidator() external payable {
        require(validators[msg.sender].isActive, "Not a validator");
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        
        validators[msg.sender].stake += msg.value;
    }
    
    function submitProductionData(
        bytes32 _region,
        uint256 _amount,
        bytes32 _dataHash,
        bytes32[] memory _merkleProof
    ) external onlyValidator returns (uint256) {
        uint256 reportIndex = latestReportIndex[_region] + 1;
        
        productionReports[_region][reportIndex] = ProductionReport({
            amount: _amount,
            timestamp: block.timestamp,
            dataHash: _dataHash,
            validations: 1,
            finalized: false
        });
        
        hasValidated[_region][reportIndex][msg.sender] = true;
        latestReportIndex[_region] = reportIndex;
        
        _verifyMerkleProof(_dataHash, _merkleProof, _region);
        
        emit ProductionReported(_region, _amount, reportIndex);
        return reportIndex;
    }
    
    function validateReport(
        bytes32 _region,
        uint256 _reportIndex,
        bool _approve
    ) external onlyValidator {
        ProductionReport storage report = productionReports[_region][_reportIndex];
        require(!report.finalized, "Report already finalized");
        require(!hasValidated[_region][_reportIndex][msg.sender], "Already validated");
        require(block.timestamp <= report.timestamp + 1 days, "Validation period expired");
        
        hasValidated[_region][_reportIndex][msg.sender] = true;
        
        if (_approve) {
            report.validations++;
            validators[msg.sender].reputation += 1;
        } else {
            validators[msg.sender].reputation += 2; // Reward for catching bad data
        }
        
        validators[msg.sender].lastValidation = block.timestamp;
        
        emit ReportValidated(_region, _reportIndex, msg.sender);
        
        uint256 activeValidators = _getActiveValidatorCount();
        uint256 requiredValidations = (activeValidators * VALIDATION_THRESHOLD) / 100;
        
        if (report.validations >= requiredValidations && report.validations >= MIN_VALIDATORS) {
            _finalizeReport(_region, _reportIndex);
        }
    }
    
    function _finalizeReport(bytes32 _region, uint256 _reportIndex) internal {
        ProductionReport storage report = productionReports[_region][_reportIndex];
        report.finalized = true;
        
        _updateTotalProduction(_region, report.amount);
        _updateMerkleRoot(_region, report.dataHash);
        
        emit ReportFinalized(_region, _reportIndex, report.amount);
    }
    
    function _updateTotalProduction(bytes32 _region, uint256 _amount) internal {
        uint256 previousAmount = 0;
        uint256 previousIndex = latestReportIndex[_region] - 1;
        
        if (previousIndex > 0 && productionReports[_region][previousIndex].finalized) {
            previousAmount = productionReports[_region][previousIndex].amount;
        }
        
        totalProduction = totalProduction - previousAmount + _amount;
    }
    
    function _updateMerkleRoot(bytes32 _region, bytes32 _dataHash) internal {
        regionMerkleRoots[_region] = keccak256(abi.encodePacked(regionMerkleRoots[_region], _dataHash));
        
        bytes32 newGlobalRoot = regionMerkleRoots[_region];
        for (uint256 i = 0; i < registeredRegions.length; i++) {
            if (registeredRegions[i] != _region) {
                newGlobalRoot = keccak256(abi.encodePacked(newGlobalRoot, regionMerkleRoots[registeredRegions[i]]));
            }
        }
        
        globalMerkleRoot = newGlobalRoot;
        emit MerkleRootUpdated(globalMerkleRoot);
    }
    
    function _verifyMerkleProof(
        bytes32 _leaf,
        bytes32[] memory _proof,
        bytes32 _region
    ) internal view {
        bytes32 computedHash = _leaf;
        
        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        require(computedHash == regionMerkleRoots[_region] || regionMerkleRoots[_region] == bytes32(0), "Invalid proof");
    }
    
    function generateMerkleProof(
        bytes32 _region,
        uint256 _reportIndex
    ) external view returns (bytes32[] memory) {
        // Simplified - would generate actual proof in production
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = productionReports[_region][_reportIndex].dataHash;
        return proof;
    }
    
    function slashValidator(address _validator, uint256 _penalty) external onlyOwner {
        require(validators[_validator].isActive, "Not active validator");
        require(validators[_validator].stake >= _penalty, "Insufficient stake");
        
        validators[_validator].stake -= _penalty;
        validators[_validator].reputation = validators[_validator].reputation > 10 ? 
            validators[_validator].reputation - 10 : 0;
        
        if (validators[_validator].stake < MIN_STAKE) {
            validators[_validator].isActive = false;
        }
        
        emit ValidatorSlashed(_validator, _penalty);
    }
    
    function registerRegion(bytes32 _region) external onlyOwner {
        for (uint256 i = 0; i < registeredRegions.length; i++) {
            require(registeredRegions[i] != _region, "Region already registered");
        }
        registeredRegions.push(_region);
    }
    
    function getRegionProduction(bytes32 _region) external view returns (uint256) {
        uint256 latestIndex = latestReportIndex[_region];
        if (latestIndex == 0) return 0;
        
        ProductionReport memory report = productionReports[_region][latestIndex];
        return report.finalized ? report.amount : 0;
    }
    
    function getTotalProduction() external view returns (uint256) {
        return totalProduction;
    }
    
    function queryProduction(bytes32 _region, uint256 _fromTimestamp, uint256 _toTimestamp) 
        external view returns (uint256 totalAmount) {
        uint256 latestIndex = latestReportIndex[_region];
        
        for (uint256 i = 1; i <= latestIndex; i++) {
            ProductionReport memory report = productionReports[_region][i];
            if (report.finalized && 
                report.timestamp >= _fromTimestamp && 
                report.timestamp <= _toTimestamp) {
                totalAmount += report.amount;
            }
        }
        
        return totalAmount;
    }
    
    function _getActiveValidatorCount() internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < validatorList.length; i++) {
            if (validators[validatorList[i]].isActive) {
                count++;
            }
        }
        return count;
    }
    
    function getValidatorStatus(address _validator) external view returns (
        bool isActive,
        uint256 stake,
        uint256 reputation,
        uint256 lastValidation
    ) {
        Validator memory v = validators[_validator];
        return (v.isActive, v.stake, v.reputation, v.lastValidation);
    }
}