// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IHolodomorPrevention {
    function updateStakeholderReputation(address stakeholder, int256 change) external;
}

contract QuotaGovernance {
    address public owner;
    IHolodomorPrevention public holodomorPrevention;
    
    enum ProposalStatus { Pending, Voting, Approved, Rejected, Appealed, Frozen }
    
    struct QuotaProposal {
        bytes32 region;
        uint256 quotaAmount;
        uint256 proposedAt;
        uint256 votingEndsAt;
        uint256 appealEndsAt;
        address proposer;
        ProposalStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        bool emergencyOverride;
    }
    
    struct Vote {
        bool hasVoted;
        bool support;
        uint256 weight;
    }
    
    mapping(uint256 => QuotaProposal) public quotaProposals;
    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(bytes32 => uint256) public activeQuotas;
    mapping(bytes32 => bool) public frozenQuotas;
    mapping(address => uint256) public voterWeight;
    mapping(uint256 => address[]) public appealSigners;
    
    uint256 public proposalCounter;
    uint256 public votingPeriod = 3 days;
    uint256 public appealPeriod = 2 days;
    uint256 public quorumThreshold = 30; // 30% participation required
    uint256 public approvalThreshold = 51; // 51% approval required
    uint256 public appealThreshold = 3; // 3 signatures needed for appeal
    
    event ProposalCreated(uint256 proposalId, bytes32 region, uint256 quotaAmount);
    event VoteCast(uint256 proposalId, address voter, bool support, uint256 weight);
    event ProposalApproved(uint256 proposalId, uint256 quotaAmount);
    event ProposalRejected(uint256 proposalId);
    event QuotaAppealed(uint256 proposalId, address appealer);
    event QuotaFrozen(bytes32 region);
    event QuotaUnfrozen(bytes32 region);
    event EmergencyOverride(uint256 proposalId, address initiator);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier hasVotingWeight() {
        require(voterWeight[msg.sender] > 0, "No voting weight");
        _;
    }
    
    constructor(address _holodomorPrevention) {
        owner = msg.sender;
        holodomorPrevention = IHolodomorPrevention(_holodomorPrevention);
    }
    
    function setVoterWeight(address _voter, uint256 _weight) external onlyOwner {
        voterWeight[_voter] = _weight;
    }
    
    function proposeQuota(
        bytes32 _region,
        uint256 _quotaAmount
    ) external hasVotingWeight returns (uint256) {
        require(!frozenQuotas[_region], "Quota frozen for region");
        
        proposalCounter++;
        
        quotaProposals[proposalCounter] = QuotaProposal({
            region: _region,
            quotaAmount: _quotaAmount,
            proposedAt: block.timestamp,
            votingEndsAt: block.timestamp + votingPeriod,
            appealEndsAt: 0,
            proposer: msg.sender,
            status: ProposalStatus.Voting,
            votesFor: 0,
            votesAgainst: 0,
            emergencyOverride: false
        });
        
        emit ProposalCreated(proposalCounter, _region, _quotaAmount);
        return proposalCounter;
    }
    
    function voteOnQuota(uint256 _proposalId, bool _support) external hasVotingWeight {
        QuotaProposal storage proposal = quotaProposals[_proposalId];
        require(proposal.status == ProposalStatus.Voting, "Not in voting phase");
        require(block.timestamp <= proposal.votingEndsAt, "Voting period ended");
        require(!votes[_proposalId][msg.sender].hasVoted, "Already voted");
        
        uint256 weight = voterWeight[msg.sender];
        
        votes[_proposalId][msg.sender] = Vote({
            hasVoted: true,
            support: _support,
            weight: weight
        });
        
        if (_support) {
            proposal.votesFor += weight;
        } else {
            proposal.votesAgainst += weight;
            holodomorPrevention.updateStakeholderReputation(proposal.proposer, -5);
        }
        
        emit VoteCast(_proposalId, msg.sender, _support, weight);
        
        if (block.timestamp >= proposal.votingEndsAt) {
            _finalizeVoting(_proposalId);
        }
    }
    
    function finalizeProposal(uint256 _proposalId) external {
        QuotaProposal storage proposal = quotaProposals[_proposalId];
        require(proposal.status == ProposalStatus.Voting, "Not in voting phase");
        require(block.timestamp > proposal.votingEndsAt, "Voting period not ended");
        
        _finalizeVoting(_proposalId);
    }
    
    function _finalizeVoting(uint256 _proposalId) internal {
        QuotaProposal storage proposal = quotaProposals[_proposalId];
        
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        uint256 totalPossibleVotes = _getTotalVotingWeight();
        uint256 participation = (totalVotes * 100) / totalPossibleVotes;
        
        if (participation < quorumThreshold) {
            proposal.status = ProposalStatus.Rejected;
            emit ProposalRejected(_proposalId);
            return;
        }
        
        uint256 approvalPercentage = (proposal.votesFor * 100) / totalVotes;
        
        if (approvalPercentage >= approvalThreshold) {
            proposal.status = ProposalStatus.Approved;
            activeQuotas[proposal.region] = proposal.quotaAmount;
            proposal.appealEndsAt = block.timestamp + appealPeriod;
            
            holodomorPrevention.updateStakeholderReputation(proposal.proposer, 10);
            emit ProposalApproved(_proposalId, proposal.quotaAmount);
        } else {
            proposal.status = ProposalStatus.Rejected;
            emit ProposalRejected(_proposalId);
        }
    }
    
    function appealQuota(uint256 _proposalId) external hasVotingWeight {
        QuotaProposal storage proposal = quotaProposals[_proposalId];
        require(proposal.status == ProposalStatus.Approved, "Not approved");
        require(block.timestamp <= proposal.appealEndsAt, "Appeal period ended");
        
        bool alreadySigned = false;
        for (uint256 i = 0; i < appealSigners[_proposalId].length; i++) {
            if (appealSigners[_proposalId][i] == msg.sender) {
                alreadySigned = true;
                break;
            }
        }
        require(!alreadySigned, "Already signed appeal");
        
        appealSigners[_proposalId].push(msg.sender);
        
        if (appealSigners[_proposalId].length >= appealThreshold) {
            proposal.status = ProposalStatus.Appealed;
            activeQuotas[proposal.region] = 0;
            emit QuotaAppealed(_proposalId, msg.sender);
        }
    }
    
    function freezeQuota(bytes32 _region) external onlyOwner {
        frozenQuotas[_region] = true;
        activeQuotas[_region] = 0;
        emit QuotaFrozen(_region);
    }
    
    function unfreezeQuota(bytes32 _region) external onlyOwner {
        frozenQuotas[_region] = false;
        emit QuotaUnfrozen(_region);
    }
    
    function emergencyOverride(uint256 _proposalId) external onlyOwner {
        QuotaProposal storage proposal = quotaProposals[_proposalId];
        require(proposal.status != ProposalStatus.Frozen, "Already frozen");
        
        proposal.status = ProposalStatus.Frozen;
        proposal.emergencyOverride = true;
        activeQuotas[proposal.region] = 0;
        
        emit EmergencyOverride(_proposalId, msg.sender);
    }
    
    function updateVotingParameters(
        uint256 _votingPeriod,
        uint256 _appealPeriod,
        uint256 _quorumThreshold,
        uint256 _approvalThreshold
    ) external onlyOwner {
        require(_votingPeriod >= 1 days, "Voting period too short");
        require(_appealPeriod >= 1 days, "Appeal period too short");
        require(_quorumThreshold <= 100, "Invalid quorum threshold");
        require(_approvalThreshold <= 100, "Invalid approval threshold");
        
        votingPeriod = _votingPeriod;
        appealPeriod = _appealPeriod;
        quorumThreshold = _quorumThreshold;
        approvalThreshold = _approvalThreshold;
    }
    
    function _getTotalVotingWeight() internal view returns (uint256) {
        return 1000; // Simplified - would iterate through all voters in production
    }
    
    function getProposalStatus(uint256 _proposalId) external view returns (
        ProposalStatus status,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 timeRemaining
    ) {
        QuotaProposal memory proposal = quotaProposals[_proposalId];
        
        uint256 remaining = 0;
        if (proposal.status == ProposalStatus.Voting && block.timestamp < proposal.votingEndsAt) {
            remaining = proposal.votingEndsAt - block.timestamp;
        } else if (proposal.status == ProposalStatus.Approved && block.timestamp < proposal.appealEndsAt) {
            remaining = proposal.appealEndsAt - block.timestamp;
        }
        
        return (proposal.status, proposal.votesFor, proposal.votesAgainst, remaining);
    }
    
    function getActiveQuota(bytes32 _region) external view returns (uint256) {
        return activeQuotas[_region];
    }
}