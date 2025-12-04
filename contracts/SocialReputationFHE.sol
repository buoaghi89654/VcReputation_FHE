// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract SocialReputationFHE is SepoliaConfig {
    struct EncryptedVC {
        uint256 id;
        address issuer;
        address subject;
        euint32 encryptedType;     // Encrypted credential type
        euint32 encryptedScore;    // Encrypted reputation score
        euint32 encryptedWeight;   // Encrypted credential weight
        uint256 timestamp;
        bool isActive;
    }
    
    struct ReputationProfile {
        euint32 encryptedTotalScore; // Encrypted total reputation score
        euint32 encryptedTrustLevel; // Encrypted trust level
        euint32 encryptedCredentialCount; // Encrypted credential count
        bool isInitialized;
    }
    
    struct ReputationProof {
        euint32 encryptedMinScore; // Encrypted minimum score requirement
        euint32 encryptedProof;    // Encrypted proof value
        bool isValid;
    }
    
    struct DecryptedProof {
        uint32 minScore;
        uint32 proofValue;
        bool isRevealed;
    }

    uint256 public vcCount;
    mapping(uint256 => EncryptedVC) public verifiableCredentials;
    mapping(address => ReputationProfile) public reputationProfiles;
    mapping(uint256 => ReputationProof) public reputationProofs;
    mapping(uint256 => DecryptedProof) public decryptedProofs;
    
    mapping(address => uint256[]) private userCredentials;
    mapping(address => bool) private trustedIssuers;
    
    mapping(uint256 => uint256) private requestToProofId;
    
    event VCIssued(uint256 indexed id, address indexed issuer, address indexed subject);
    event ReputationUpdated(address indexed subject);
    event ProofGenerated(uint256 indexed proofId);
    event ProofDecrypted(uint256 indexed proofId);
    
    address public systemAdmin;
    
    modifier onlyAdmin() {
        require(msg.sender == systemAdmin, "Not admin");
        _;
    }
    
    modifier onlyIssuer() {
        require(trustedIssuers[msg.sender], "Not trusted issuer");
        _;
    }
    
    constructor() {
        systemAdmin = msg.sender;
    }
    
    /// @notice Authorize a credential issuer
    function authorizeIssuer(address issuer) public onlyAdmin {
        trustedIssuers[issuer] = true;
    }
    
    /// @notice Issue encrypted verifiable credential
    function issueEncryptedVC(
        address subject,
        euint32 encryptedType,
        euint32 encryptedScore,
        euint32 encryptedWeight
    ) public onlyIssuer {
        vcCount += 1;
        uint256 newId = vcCount;
        
        verifiableCredentials[newId] = EncryptedVC({
            id: newId,
            issuer: msg.sender,
            subject: subject,
            encryptedType: encryptedType,
            encryptedScore: encryptedScore,
            encryptedWeight: encryptedWeight,
            timestamp: block.timestamp,
            isActive: true
        });
        
        userCredentials[subject].push(newId);
        
        // Initialize reputation profile if needed
        if (!reputationProfiles[subject].isInitialized) {
            reputationProfiles[subject] = ReputationProfile({
                encryptedTotalScore: FHE.asEuint32(0),
                encryptedTrustLevel: FHE.asEuint32(0),
                encryptedCredentialCount: FHE.asEuint32(0),
                isInitialized: true
            });
        }
        
        emit VCIssued(newId, msg.sender, subject);
    }
    
    /// @notice Update reputation profile
    function updateReputationProfile(address subject) public {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        uint256[] memory credentials = userCredentials[subject];
        euint32 totalScore = FHE.asEuint32(0);
        euint32 totalWeight = FHE.asEuint32(0);
        euint32 credentialCount = FHE.asEuint32(0);
        
        for (uint i = 0; i < credentials.length; i++) {
            EncryptedVC storage vc = verifiableCredentials[credentials[i]];
            if (vc.isActive) {
                totalScore = FHE.add(totalScore, FHE.mul(vc.encryptedScore, vc.encryptedWeight));
                totalWeight = FHE.add(totalWeight, vc.encryptedWeight);
                credentialCount = FHE.add(credentialCount, FHE.asEuint32(1));
            }
        }
        
        profile.encryptedTotalScore = FHE.div(totalScore, FHE.max(totalWeight, FHE.asEuint32(1)));
        profile.encryptedCredentialCount = credentialCount;
        
        // Calculate trust level
        profile.encryptedTrustLevel = calculateTrustLevel(profile);
        
        emit ReputationUpdated(subject);
    }
    
    /// @notice Generate reputation proof
    function generateReputationProof(
        address subject,
        euint32 encryptedMinScore
    ) public returns (uint256) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        vcCount += 1;
        uint256 newProofId = vcCount;
        
        ebool meetsRequirement = FHE.gte(profile.encryptedTotalScore, encryptedMinScore);
        euint32 proofValue = FHE.cmux(meetsRequirement, profile.encryptedTotalScore, FHE.asEuint32(0));
        
        reputationProofs[newProofId] = ReputationProof({
            encryptedMinScore: encryptedMinScore,
            encryptedProof: proofValue,
            isValid: true
        });
        
        decryptedProofs[newProofId] = DecryptedProof({
            minScore: 0,
            proofValue: 0,
            isRevealed: false
        });
        
        emit ProofGenerated(newProofId);
        return newProofId;
    }
    
    /// @notice Request proof decryption
    function requestProofDecryption(uint256 proofId) public {
        ReputationProof storage proof = reputationProofs[proofId];
        require(proof.isValid, "Invalid proof");
        require(!decryptedProofs[proofId].isRevealed, "Already decrypted");
        
        bytes32[] memory ciphertexts = new bytes32[](2);
        ciphertexts[0] = FHE.toBytes32(proof.encryptedMinScore);
        ciphertexts[1] = FHE.toBytes32(proof.encryptedProof);
        
        uint256 reqId = FHE.requestDecryption(ciphertexts, this.decryptReputationProof.selector);
        requestToProofId[reqId] = proofId;
    }
    
    /// @notice Process decrypted reputation proof
    function decryptReputationProof(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory proof
    ) public {
        uint256 proofId = requestToProofId[requestId];
        require(proofId != 0, "Invalid request");
        
        ReputationProof storage rProof = reputationProofs[proofId];
        DecryptedProof storage dProof = decryptedProofs[proofId];
        require(rProof.isValid, "Invalid proof");
        require(!dProof.isRevealed, "Already decrypted");
        
        FHE.checkSignatures(requestId, cleartexts, proof);
        
        (uint32 minScore, uint32 proofValue) = abi.decode(cleartexts, (uint32, uint32));
        
        dProof.minScore = minScore;
        dProof.proofValue = proofValue;
        dProof.isRevealed = true;
        
        emit ProofDecrypted(proofId);
    }
    
    /// @notice Calculate trust level
    function calculateTrustLevel(ReputationProfile storage profile) private view returns (euint32) {
        // Trust level based on score and credential count
        euint32 scoreFactor = FHE.div(profile.encryptedTotalScore, FHE.asEuint32(10));
        euint32 countFactor = FHE.div(profile.encryptedCredentialCount, FHE.asEuint32(5));
        
        return FHE.add(scoreFactor, countFactor);
    }
    
    /// @issue Anonymous reputation attestation
    function issueAnonymousAttestation(address subject, euint32 encryptedScore) public onlyIssuer {
        // Issue VC without issuer identity
        issueEncryptedVC(subject, FHE.asEuint32(0), encryptedScore, FHE.asEuint32(1));
    }
    
    /// @notice Verify credential validity
    function verifyCredential(uint256 vcId) public view returns (ebool) {
        EncryptedVC storage vc = verifiableCredentials[vcId];
        return FHE.and(
            FHE.asEbool(vc.isActive),
            FHE.gt(vc.encryptedScore, FHE.asEuint32(0))
        );
    }
    
    /// @notice Calculate credential diversity
    function calculateCredentialDiversity(address subject) public view returns (euint32) {
        uint256[] memory credentials = userCredentials[subject];
        if (credentials.length < 2) return FHE.asEuint32(0);
        
        euint32 diversity = FHE.asEuint32(0);
        for (uint i = 0; i < credentials.length; i++) {
            for (uint j = i + 1; j < credentials.length; j++) {
                EncryptedVC storage vc1 = verifiableCredentials[credentials[i]];
                EncryptedVC storage vc2 = verifiableCredentials[credentials[j]];
                
                ebool differentType = FHE.neq(vc1.encryptedType, vc2.encryptedType);
                diversity = FHE.add(
                    diversity,
                    FHE.cmux(differentType, FHE.asEuint32(1), FHE.asEuint32(0))
                );
            }
        }
        
        return diversity;
    }
    
    /// @notice Generate zero-knowledge proof
    function generateZKProof(address subject, euint32 encryptedThreshold) public view returns (ebool) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        return FHE.gte(profile.encryptedTotalScore, encryptedThreshold);
    }
    
    /// @notice Calculate reputation decay
    function calculateReputationDecay(address subject) public view returns (euint32) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        uint256[] memory credentials = userCredentials[subject];
        euint32 decay = FHE.asEuint32(0);
        uint32 currentTime = uint32(block.timestamp);
        
        for (uint i = 0; i < credentials.length; i++) {
            EncryptedVC storage vc = verifiableCredentials[credentials[i]];
            euint32 age = FHE.asEuint32(currentTime - uint32(vc.timestamp));
            
            // Decay = score * age / (365 days)
            decay = FHE.add(
                decay,
                FHE.div(
                    FHE.mul(vc.encryptedScore, age),
                    FHE.asEuint32(31536000) // Seconds in a year
                )
            );
        }
        
        return decay;
    }
    
    /// @notice Revoke verifiable credential
    function revokeCredential(uint256 vcId) public {
        EncryptedVC storage vc = verifiableCredentials[vcId];
        require(vc.issuer == msg.sender, "Not issuer");
        vc.isActive = false;
    }
    
    /// @notice Calculate sybil resistance
    function calculateSybilResistance(address subject) public view returns (euint32) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        // Higher credential diversity increases sybil resistance
        euint32 diversity = calculateCredentialDiversity(subject);
        return FHE.div(
            FHE.mul(diversity, FHE.asEuint32(100)),
            profile.encryptedCredentialCount
        );
    }
    
    /// @notice Get encrypted VC details
    function getEncryptedVC(uint256 vcId) public view returns (
        address issuer,
        address subject,
        euint32 encryptedType,
        euint32 encryptedScore,
        euint32 encryptedWeight,
        uint256 timestamp,
        bool isActive
    ) {
        EncryptedVC storage vc = verifiableCredentials[vcId];
        return (
            vc.issuer,
            vc.subject,
            vc.encryptedType,
            vc.encryptedScore,
            vc.encryptedWeight,
            vc.timestamp,
            vc.isActive
        );
    }
    
    /// @notice Get reputation profile
    function getReputationProfile(address subject) public view returns (
        euint32 encryptedTotalScore,
        euint32 encryptedTrustLevel,
        euint32 encryptedCredentialCount,
        bool isInitialized
    ) {
        ReputationProfile storage p = reputationProfiles[subject];
        return (
            p.encryptedTotalScore,
            p.encryptedTrustLevel,
            p.encryptedCredentialCount,
            p.isInitialized
        );
    }
    
    /// @notice Get reputation proof
    function getReputationProof(uint256 proofId) public view returns (
        euint32 encryptedMinScore,
        euint32 encryptedProof,
        bool isValid
    ) {
        ReputationProof storage p = reputationProofs[proofId];
        return (p.encryptedMinScore, p.encryptedProof, p.isValid);
    }
    
    /// @notice Get decrypted proof
    function getDecryptedProof(uint256 proofId) public view returns (
        uint32 minScore,
        uint32 proofValue,
        bool isRevealed
    ) {
        DecryptedProof storage p = decryptedProofs[proofId];
        return (p.minScore, p.proofValue, p.isRevealed);
    }
    
    /// @notice Calculate reputation portability
    function calculatePortability(address subject) public view returns (euint32) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        // Portability based on trust level and credential count
        return FHE.div(
            FHE.add(profile.encryptedTrustLevel, profile.encryptedCredentialCount),
            FHE.asEuint32(2)
        );
    }
    
    /// @notice Issue cross-platform credential
    function issueCrossPlatformCredential(address subject, euint32 encryptedPlatformScore) public onlyIssuer {
        // Issue VC with platform-specific score
        issueEncryptedVC(subject, FHE.asEuint32(999), encryptedPlatformScore, FHE.asEuint32(2));
    }
    
    /// @notice Calculate reputation consistency
    function calculateConsistency(address subject) public view returns (euint32) {
        uint256[] memory credentials = userCredentials[subject];
        if (credentials.length < 2) return FHE.asEuint32(100); // Perfect consistency
        
        euint32 totalDeviation = FHE.asEuint32(0);
        euint32 avgScore = reputationProfiles[subject].encryptedTotalScore;
        
        for (uint i = 0; i < credentials.length; i++) {
            EncryptedVC storage vc = verifiableCredentials[credentials[i]];
            euint32 deviation = FHE.sub(vc.encryptedScore, avgScore);
            totalDeviation = FHE.add(totalDeviation, FHE.mul(deviation, deviation));
        }
        
        euint32 variance = FHE.div(totalDeviation, FHE.asEuint32(uint32(credentials.length)));
        return FHE.sub(
            FHE.asEuint32(100),
            FHE.div(variance, FHE.asEuint32(10))
        );
    }
    
    /// @notice Generate time-bound proof
    function generateTimeBoundProof(
        address subject,
        euint32 encryptedMinScore,
        uint256 validityPeriod
    ) public returns (uint256) {
        uint256 proofId = generateReputationProof(subject, encryptedMinScore);
        reputationProofs[proofId].isValid = false; // Invalidate after period
        
        // Schedule invalidation (simplified)
        return proofId;
    }
    
    /// @notice Calculate governance weight
    function calculateGovernanceWeight(address subject) public view returns (euint32) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        return FHE.div(profile.encryptedTrustLevel, FHE.asEuint32(10));
    }
    
    /// @notice Verify credential ownership
    function verifyCredentialOwnership(address subject, uint256 vcId) public view returns (ebool) {
        EncryptedVC storage vc = verifiableCredentials[vcId];
        return FHE.asEbool(vc.subject == subject);
    }
    
    /// @notice Calculate reputation velocity
    function calculateReputationVelocity(address subject) public view returns (euint32) {
        uint256[] memory credentials = userCredentials[subject];
        if (credentials.length < 2) return FHE.asEuint32(0);
        
        EncryptedVC storage firstVC = verifiableCredentials[credentials[0]];
        EncryptedVC storage lastVC = verifiableCredentials[credentials[credentials.length - 1]];
        
        euint32 scoreDelta = FHE.sub(lastVC.encryptedScore, firstVC.encryptedScore);
        euint32 timeDelta = FHE.asEuint32(uint32(lastVC.timestamp - firstVC.timestamp));
        
        return FHE.div(scoreDelta, FHE.max(timeDelta, FHE.asEuint32(1)));
    }
    
    /// @notice Issue community endorsement
    function issueCommunityEndorsement(address subject, euint32 encryptedEndorsement) public {
        // Issue VC with community endorsement type
        issueEncryptedVC(subject, FHE.asEuint32(100), encryptedEndorsement, FHE.asEuint32(3));
    }
    
    /// @notice Calculate social capital
    function calculateSocialCapital(address subject) public view returns (euint32) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        // Social capital = trust level * credential count
        return FHE.mul(profile.encryptedTrustLevel, profile.encryptedCredentialCount);
    }
    
    /// @notice Generate composite proof
    function generateCompositeProof(address subject, euint32[] memory encryptedRequirements) public returns (uint256) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        ebool meetsAll = FHE.asEbool(true);
        euint32 compositeProof = FHE.asEuint32(0);
        
        for (uint i = 0; i < encryptedRequirements.length; i++) {
            ebool meetsRequirement = FHE.gte(profile.encryptedTotalScore, encryptedRequirements[i]);
            meetsAll = FHE.and(meetsAll, meetsRequirement);
            compositeProof = FHE.add(compositeProof, FHE.cmux(meetsRequirement, encryptedRequirements[i], FHE.asEuint32(0)));
        }
        
        vcCount += 1;
        uint256 newProofId = vcCount;
        
        reputationProofs[newProofId] = ReputationProof({
            encryptedMinScore: FHE.cmux(meetsAll, FHE.asEuint32(1), FHE.asEuint32(0)),
            encryptedProof: compositeProof,
            isValid: true
        });
        
        decryptedProofs[newProofId] = DecryptedProof({
            minScore: 0,
            proofValue: 0,
            isRevealed: false
        });
        
        emit ProofGenerated(newProofId);
        return newProofId;
    }
    
    /// @notice Protect user privacy
    function protectUserPrivacy(address subject) public onlyAdmin {
        // In real implementation, implement privacy measures
        // For example: delete userCredentials[subject];
    }
    
    /// @notice Calculate reputation stability
    function calculateStability(address subject) public view returns (euint32) {
        euint32 consistency = calculateConsistency(subject);
        euint32 velocity = calculateReputationVelocity(subject);
        
        return FHE.sub(
            consistency,
            FHE.div(velocity, FHE.asEuint32(10))
        );
    }
    
    /// @notice Issue skill certification
    function issueSkillCertification(address subject, euint32 encryptedSkillLevel) public onlyIssuer {
        // Issue VC with skill certification type
        issueEncryptedVC(subject, FHE.asEuint32(200), encryptedSkillLevel, FHE.asEuint32(2));
    }
    
    /// @notice Calculate weighted reputation
    function calculateWeightedReputation(address subject) public view returns (euint32) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        return profile.encryptedTotalScore;
    }
    
    /// @notice Verify proof without decryption
    function verifyProofWithoutDecryption(uint256 proofId) public view returns (ebool) {
        ReputationProof storage proof = reputationProofs[proofId];
        require(proof.isValid, "Invalid proof");
        
        return FHE.gt(proof.encryptedProof, FHE.asEuint32(0));
    }
    
    /// @notice Calculate ecosystem contribution
    function calculateEcosystemContribution(address subject) public view returns (euint32) {
        uint256[] memory credentials = userCredentials[subject];
        euint32 contribution = FHE.asEuint32(0);
        
        for (uint i = 0; i < credentials.length; i++) {
            EncryptedVC storage vc = verifiableCredentials[credentials[i]];
            if (vc.encryptedType == FHE.asEuint32(300)) { // Ecosystem contribution type
                contribution = FHE.add(contribution, vc.encryptedScore);
            }
        }
        
        return contribution;
    }
    
    /// @notice Generate reputation scorecard
    function generateScorecard(address subject) public view returns (euint32[5] memory) {
        ReputationProfile storage profile = reputationProfiles[subject];
        require(profile.isInitialized, "Profile not initialized");
        
        euint32[5] memory scorecard;
        scorecard[0] = profile.encryptedTotalScore;
        scorecard[1] = profile.encryptedTrustLevel;
        scorecard[2] = calculateConsistency(subject);
        scorecard[3] = calculateSybilResistance(subject);
        scorecard[4] = calculateStability(subject);
        
        return scorecard;
    }
    
    /// @notice Issue decentralized identity score
    function issueDIDScore(address subject, euint32 encryptedDIDScore) public onlyIssuer {
        // Issue VC with DID score type
        issueEncryptedVC(subject, FHE.asEuint32(400), encryptedDIDScore, FHE.asEuint32(3));
    }
    
    /// @notice Calculate web3 reputation index
    function calculateWeb3ReputationIndex(address subject) public view returns (euint32) {
        euint32 socialCapital = calculateSocialCapital(subject);
        euint32 ecosystemContribution = calculateEcosystemContribution(subject);
        euint32 didScore = FHE.asEuint32(0);
        
        // Find DID score credential
        uint256[] memory credentials = userCredentials[subject];
        for (uint i = 0; i < credentials.length; i++) {
            EncryptedVC storage vc = verifiableCredentials[credentials[i]];
            if (FHE.decrypt(FHE.eq(vc.encryptedType, FHE.asEuint32(400)))) {
                didScore = vc.encryptedScore;
                break;
            }
        }
        
        return FHE.div(
            FHE.add(FHE.add(socialCapital, ecosystemContribution), didScore),
            FHE.asEuint32(3)
        );
    }
}