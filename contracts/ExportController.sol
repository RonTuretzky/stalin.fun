// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFoodProductionOracle {
    function getTotalProduction() external view returns (uint256);
    function getRegionProduction(bytes32 region) external view returns (uint256);
}

contract ExportController {
    address public owner;
    address public holodomorPrevention;
    IFoodProductionOracle public productionOracle;
    
    struct ExportPermit {
        bytes32 destination;
        uint256 amount;
        uint256 pricePerUnit;
        uint256 issuedAt;
        uint256 expiresAt;
        address exporter;
        bool executed;
        bool revoked;
    }
    
    mapping(uint256 => ExportPermit) public exportPermits;
    mapping(bytes32 => uint256) public monthlyExports;
    mapping(bytes32 => uint256) public exportRevenue;
    
    uint256 public permitCounter;
    uint256 public exportLimit;
    uint256 public totalExported;
    uint256 public domesticReserveRequirement = 60; // 60% must stay domestic
    uint256 public minimumDomesticSupply = 2000000; // tonnes
    uint256 public currentMonth;
    bool public exportsPaused;
    
    event ExportLimitSet(uint256 newLimit);
    event ExportsPaused(uint256 timestamp);
    event ExportsResumed(uint256 timestamp);
    event PermitRequested(uint256 permitId, address exporter, uint256 amount);
    event PermitApproved(uint256 permitId);
    event PermitExecuted(uint256 permitId, uint256 revenue);
    event PermitRevoked(uint256 permitId, string reason);
    event DomesticSupplyPrioritized(uint256 reservedAmount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyAuthorized() {
        require(
            msg.sender == owner || 
            msg.sender == holodomorPrevention,
            "Not authorized"
        );
        _;
    }
    
    modifier exportsNotPaused() {
        require(!exportsPaused, "Exports are paused");
        _;
    }
    
    constructor(address _productionOracle) {
        owner = msg.sender;
        productionOracle = IFoodProductionOracle(_productionOracle);
        currentMonth = block.timestamp / 30 days;
    }
    
    function setHolodomorPrevention(address _holodomorPrevention) external onlyOwner {
        holodomorPrevention = _holodomorPrevention;
    }
    
    function setExportLimit(uint256 _limit) external onlyOwner {
        exportLimit = _limit;
        emit ExportLimitSet(_limit);
    }
    
    function pauseAllExports() external onlyAuthorized {
        exportsPaused = true;
        emit ExportsPaused(block.timestamp);
    }
    
    function resumeExports() external onlyOwner {
        require(exportsPaused, "Exports not paused");
        
        uint256 totalProduction = productionOracle.getTotalProduction();
        uint256 domesticSupply = totalProduction - totalExported;
        
        require(
            domesticSupply >= minimumDomesticSupply,
            "Insufficient domestic supply to resume exports"
        );
        
        exportsPaused = false;
        emit ExportsResumed(block.timestamp);
    }
    
    function requestExportPermit(
        bytes32 _destination,
        uint256 _amount,
        uint256 _pricePerUnit
    ) external exportsNotPaused returns (uint256) {
        require(_amount > 0, "Invalid amount");
        require(_pricePerUnit > 0, "Invalid price");
        
        // Check if domestic supply requirements are met
        uint256 totalProduction = productionOracle.getTotalProduction();
        require(totalProduction > 0, "No production data available");
        
        uint256 domesticRequired = (totalProduction * domesticReserveRequirement) / 100;
        uint256 availableForExport = totalProduction > domesticRequired ? 
            totalProduction - domesticRequired : 0;
        
        require(availableForExport >= _amount, "Exceeds available export capacity");
        
        // Check monthly limits
        uint256 month = block.timestamp / 30 days;
        if (month > currentMonth) {
            currentMonth = month;
            // Reset monthly counters
        }
        
        require(
            monthlyExports[_destination] + _amount <= exportLimit,
            "Exceeds monthly export limit"
        );
        
        permitCounter++;
        
        exportPermits[permitCounter] = ExportPermit({
            destination: _destination,
            amount: _amount,
            pricePerUnit: _pricePerUnit,
            issuedAt: block.timestamp,
            expiresAt: block.timestamp + 7 days,
            exporter: msg.sender,
            executed: false,
            revoked: false
        });
        
        emit PermitRequested(permitCounter, msg.sender, _amount);
        
        // Auto-approve if conditions are met
        if (_checkAutoApproval(totalProduction, _amount)) {
            _approvePermit(permitCounter);
        }
        
        return permitCounter;
    }
    
    function _checkAutoApproval(uint256 _totalProduction, uint256 _exportAmount) internal view returns (bool) {
        uint256 postExportDomestic = _totalProduction - totalExported - _exportAmount;
        return postExportDomestic >= minimumDomesticSupply * 2; // 2x safety margin
    }
    
    function _approvePermit(uint256 _permitId) internal {
        ExportPermit storage permit = exportPermits[_permitId];
        require(!permit.executed && !permit.revoked, "Invalid permit state");
        
        monthlyExports[permit.destination] += permit.amount;
        
        emit PermitApproved(_permitId);
    }
    
    function executeExportPermit(uint256 _permitId) external exportsNotPaused {
        ExportPermit storage permit = exportPermits[_permitId];
        require(msg.sender == permit.exporter, "Not permit holder");
        require(!permit.executed, "Already executed");
        require(!permit.revoked, "Permit revoked");
        require(block.timestamp <= permit.expiresAt, "Permit expired");
        
        // Final check on domestic supply
        uint256 totalProduction = productionOracle.getTotalProduction();
        uint256 domesticSupply = totalProduction - totalExported;
        
        if (domesticSupply - permit.amount < minimumDomesticSupply) {
            _autoP pauseExports();
            revert("Would breach minimum domestic supply");
        }
        
        permit.executed = true;
        totalExported += permit.amount;
        
        uint256 revenue = permit.amount * permit.pricePerUnit;
        exportRevenue[permit.destination] += revenue;
        
        emit PermitExecuted(_permitId, revenue);
    }
    
    function revokeExportPermit(uint256 _permitId, string memory _reason) external onlyOwner {
        ExportPermit storage permit = exportPermits[_permitId];
        require(!permit.executed, "Already executed");
        require(!permit.revoked, "Already revoked");
        
        permit.revoked = true;
        monthlyExports[permit.destination] -= permit.amount;
        
        emit PermitRevoked(_permitId, _reason);
    }
    
    function prioritizeDomesticSupply() external onlyAuthorized {
        uint256 totalProduction = productionOracle.getTotalProduction();
        uint256 domesticNeeded = (totalProduction * 80) / 100; // Increase to 80%
        
        domesticReserveRequirement = 80;
        minimumDomesticSupply = domesticNeeded;
        
        // Pause exports if current supply is insufficient
        if (totalProduction - totalExported < domesticNeeded) {
            exportsPaused = true;
            emit ExportsPaused(block.timestamp);
        }
        
        emit DomesticSupplyPrioritized(domesticNeeded);
    }
    
    function _autoPauseExports() internal {
        if (!exportsPaused) {
            exportsPaused = true;
            emit ExportsPaused(block.timestamp);
        }
    }
    
    function checkExportCapacity() external view returns (
        uint256 totalProduction,
        uint256 domesticReserved,
        uint256 alreadyExported,
        uint256 availableForExport,
        bool canExport
    ) {
        totalProduction = productionOracle.getTotalProduction();
        domesticReserved = (totalProduction * domesticReserveRequirement) / 100;
        alreadyExported = totalExported;
        
        if (totalProduction > domesticReserved + alreadyExported) {
            availableForExport = totalProduction - domesticReserved - alreadyExported;
        } else {
            availableForExport = 0;
        }
        
        canExport = !exportsPaused && availableForExport > 0;
    }
    
    function updateDomesticRequirements(
        uint256 _reservePercentage,
        uint256 _minimumSupply
    ) external onlyOwner {
        require(_reservePercentage <= 100, "Invalid percentage");
        require(_minimumSupply > 0, "Invalid minimum supply");
        
        domesticReserveRequirement = _reservePercentage;
        minimumDomesticSupply = _minimumSupply;
    }
    
    function getExportStatistics() external view returns (
        uint256 totalExportedAmount,
        uint256 currentMonthExports,
        uint256 totalRevenue,
        bool paused
    ) {
        totalExportedAmount = totalExported;
        
        // Sum current month exports
        currentMonthExports = 0; // Would sum from monthlyExports mapping
        
        // Sum total revenue
        totalRevenue = 0; // Would sum from exportRevenue mapping
        
        paused = exportsPaused;
    }
    
    function emergencyRevokeAllPendingPermits() external onlyOwner {
        for (uint256 i = 1; i <= permitCounter; i++) {
            ExportPermit storage permit = exportPermits[i];
            if (!permit.executed && !permit.revoked) {
                permit.revoked = true;
                monthlyExports[permit.destination] -= permit.amount;
                emit PermitRevoked(i, "Emergency revocation");
            }
        }
    }
}