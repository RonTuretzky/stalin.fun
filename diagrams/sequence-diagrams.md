# Holodomor Oversight System - Sequence Diagrams

## 1. Proof-of-Life Treasury Lock Flow

```mermaid
sequenceDiagram
    participant Citizen
    participant AttestationRegistry
    participant TreasuryVault
    participant Official
    participant EmergencyOracle
    
    Note over Citizen,EmergencyOracle: Daily Attestation Cycle
    
    Citizen->>AttestationRegistry: submitProofOfLife(region, zkProof)
    AttestationRegistry->>AttestationRegistry: Verify ZK proof
    AttestationRegistry->>AttestationRegistry: Update region count
    
    alt Attestation count < threshold
        AttestationRegistry->>TreasuryVault: triggerEmergencyLock(region)
        TreasuryVault->>TreasuryVault: Lock enforcement funds
        TreasuryVault-->>Official: Access Denied
        Official->>Official: Cannot access border enforcement funds
    else Attestation count >= threshold
        Official->>TreasuryVault: requestEnforcementFunds(amount)
        TreasuryVault->>AttestationRegistry: checkThreshold(region)
        AttestationRegistry-->>TreasuryVault: Return true
        TreasuryVault-->>Official: Funds Released (with delay)
    end
    
    EmergencyOracle->>TreasuryVault: Monitor metrics continuously
```

## 2. Whistleblower Report & Fund Freeze Flow

```mermaid
sequenceDiagram
    participant Whistleblower
    participant WhistleblowerProtection
    participant IPFS
    participant ArbitrationCourt
    participant TreasuryVault
    participant CollateralizedEnforcement
    
    Note over Whistleblower,CollateralizedEnforcement: Anonymous Violation Reporting
    
    Whistleblower->>IPFS: Upload evidence (photos, documents)
    IPFS-->>Whistleblower: Return evidenceHash
    
    Whistleblower->>WhistleblowerProtection: submitAnonymousReport(evidenceHash, zkProof)
    WhistleblowerProtection->>WhistleblowerProtection: Verify ZK proof
    WhistleblowerProtection->>ArbitrationCourt: submitEvidence(evidenceHash)
    
    ArbitrationCourt->>ArbitrationCourt: Review evidence
    ArbitrationCourt->>ArbitrationCourt: Validator consensus
    
    alt Evidence verified
        ArbitrationCourt->>TreasuryVault: freezeViolentEnforcement(region)
        TreasuryVault->>TreasuryVault: Lock all enforcement funds
        ArbitrationCourt->>CollateralizedEnforcement: slashCollateral(official)
        CollateralizedEnforcement->>CollateralizedEnforcement: Transfer collateral to victims
        WhistleblowerProtection->>Whistleblower: Pay bounty (anonymous claim)
    else Evidence rejected
        ArbitrationCourt-->>WhistleblowerProtection: Evidence insufficient
        WhistleblowerProtection->>WhistleblowerProtection: Update reporter reputation
    end
```

## 3. Humanitarian Circuit Breaker Flow

```mermaid
sequenceDiagram
    participant Oracle
    participant EmergencyFreeze
    participant TreasuryVault
    participant OversightGovernor
    participant Official
    
    Note over Oracle,Official: Automatic Humanitarian Monitoring
    
    loop Every hour
        Oracle->>EmergencyFreeze: Push metrics (mortality, food prices, migration)
        EmergencyFreeze->>EmergencyFreeze: Check thresholds
        
        alt Threshold breached
            EmergencyFreeze->>TreasuryVault: freezeViolentEnforcement(region)
            TreasuryVault->>TreasuryVault: Emergency lockdown activated
            EmergencyFreeze-->>OversightGovernor: Notify emergency state
            
            Official->>TreasuryVault: requestEnforcementFunds()
            TreasuryVault-->>Official: DENIED - Humanitarian crisis active
            
            Official->>EmergencyFreeze: overrideEmergency(stake: 1000 ETH)
            alt Override approved by supermajority
                EmergencyFreeze->>TreasuryVault: Temporary unlock (24 hours)
                TreasuryVault-->>Official: Limited access granted
            else Override rejected
                EmergencyFreeze-->>Official: Override denied
                EmergencyFreeze->>CollateralizedEnforcement: Slash override stake
            end
        else Metrics normal
            Oracle-->>EmergencyFreeze: Continue monitoring
        end
    end
```

## 4. Community Veto Network Flow

```mermaid
sequenceDiagram
    participant Official
    participant TreasuryVault
    participant CommunityMultisig
    participant Citizens
    participant OversightGovernor
    
    Note over Official,OversightGovernor: Multi-signature Treasury Control
    
    Official->>TreasuryVault: requestEnforcementFunds(amount, purpose)
    TreasuryVault->>CommunityMultisig: Propose withdrawal
    CommunityMultisig->>CommunityMultisig: Start 72-hour veto window
    
    CommunityMultisig-->>Citizens: Public notification broadcast
    
    par Citizens review proposal
        Citizens->>Citizens: Review enforcement purpose
        Citizens->>Citizens: Gather signatures for veto
    and Community signers deliberate
        CommunityMultisig->>CommunityMultisig: Signer discussion
        CommunityMultisig->>CommunityMultisig: Vote on approval
    end
    
    alt Veto threshold met (30% of signers)
        Citizens->>CommunityMultisig: Submit veto petition
        CommunityMultisig->>TreasuryVault: Block withdrawal
        TreasuryVault-->>Official: Funds DENIED - Community veto
        CommunityMultisig->>OversightGovernor: Log veto for review
    else No veto / Approval
        CommunityMultisig->>TreasuryVault: Approve withdrawal
        TreasuryVault->>TreasuryVault: Release funds after delay
        TreasuryVault-->>Official: Funds transferred
    end
```

## 5. Collateralized Enforcement Bond Flow

```mermaid
sequenceDiagram
    participant Official
    participant CollateralizedEnforcement
    participant TreasuryVault
    participant CitizenReporter
    participant ArbitrationCourt
    
    Note over Official,ArbitrationCourt: Personal Stake Requirement
    
    Official->>CollateralizedEnforcement: postBond{value: 20 ETH}(region, purpose)
    CollateralizedEnforcement->>CollateralizedEnforcement: Lock collateral
    
    Official->>CollateralizedEnforcement: accessFunds(100 ETH)
    CollateralizedEnforcement->>TreasuryVault: Verify collateral ratio (20%)
    TreasuryVault-->>Official: Funds released for enforcement
    
    Official->>Official: Execute border enforcement
    
    alt Violence reported
        CitizenReporter->>ArbitrationCourt: Report violence with evidence
        ArbitrationCourt->>ArbitrationCourt: Verify evidence
        ArbitrationCourt->>CollateralizedEnforcement: slashCollateral(official, evidenceHash)
        CollateralizedEnforcement->>CollateralizedEnforcement: Forfeit 20 ETH collateral
        CollateralizedEnforcement-->>CitizenReporter: Compensation from collateral
        CollateralizedEnforcement->>TreasuryVault: Freeze official's future access
    else No violations
        Official->>CollateralizedEnforcement: releaseCollateral() (after 30 days)
        CollateralizedEnforcement-->>Official: Return 20 ETH collateral
    end
```

## 6. International Observer Integration Flow

```mermaid
sequenceDiagram
    participant InternationalObserver
    participant OracleAggregator
    participant EmergencyFreeze
    participant TreasuryVault
    participant UN_RedCross
    
    Note over InternationalObserver,UN_RedCross: External Monitoring & Intervention
    
    InternationalObserver->>OracleAggregator: Submit humanitarian data
    UN_RedCross->>OracleAggregator: Submit mortality/famine data
    
    OracleAggregator->>OracleAggregator: Aggregate & verify data
    OracleAggregator->>EmergencyFreeze: Push verified metrics
    
    alt Crisis detected
        EmergencyFreeze->>TreasuryVault: Trigger international intervention lock
        TreasuryVault->>TreasuryVault: Freeze all enforcement funds
        TreasuryVault-->>InternationalObserver: Notify of intervention
        
        InternationalObserver->>InternationalObserver: Document violations
        InternationalObserver->>ArbitrationCourt: Submit to international tribunal
    else Metrics within bounds
        OracleAggregator-->>InternationalObserver: Continue monitoring
    end
```