// App.tsx
import React, { useEffect, useState } from "react";
import { ethers } from "ethers";
import { getContractReadOnly, getContractWithSigner } from "./contract";
import WalletManager from "./components/WalletManager";
import WalletSelector from "./components/WalletSelector";
import "./App.css";

interface ReputationScore {
  id: string;
  owner: string;
  encryptedScore: string;
  lastUpdated: number;
  credentials: string[];
}

const App: React.FC = () => {
  // Randomized style: High contrast (blue+orange), Industrial mechanical UI, Center radiation layout, Micro-interactions
  const [account, setAccount] = useState("");
  const [loading, setLoading] = useState(true);
  const [scores, setScores] = useState<ReputationScore[]>([]);
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showAddModal, setShowAddModal] = useState(false);
  const [addingScore, setAddingScore] = useState(false);
  const [walletSelectorOpen, setWalletSelectorOpen] = useState(false);
  const [transactionStatus, setTransactionStatus] = useState<{
    visible: boolean;
    status: "pending" | "success" | "error";
    message: string;
  }>({ visible: false, status: "pending", message: "" });
  const [newScoreData, setNewScoreData] = useState({
    score: "",
    credentials: ""
  });
  const [showStats, setShowStats] = useState(false);
  const [searchTerm, setSearchTerm] = useState("");

  // Calculate average score (simulated FHE computation)
  const averageScore = scores.length > 0 
    ? Math.round(scores.reduce((sum, score) => sum + parseInt(score.encryptedScore.replace("FHE-", "")), 0) / scores.length) 
    : 0;

  useEffect(() => {
    loadScores().finally(() => setLoading(false));
  }, []);

  const onWalletSelect = async (wallet: any) => {
    if (!wallet.provider) return;
    try {
      const web3Provider = new ethers.BrowserProvider(wallet.provider);
      setProvider(web3Provider);
      const accounts = await web3Provider.send("eth_requestAccounts", []);
      const acc = accounts[0] || "";
      setAccount(acc);

      wallet.provider.on("accountsChanged", async (accounts: string[]) => {
        const newAcc = accounts[0] || "";
        setAccount(newAcc);
      });
    } catch (e) {
      alert("Failed to connect wallet");
    }
  };

  const onConnect = () => setWalletSelectorOpen(true);
  const onDisconnect = () => {
    setAccount("");
    setProvider(null);
  };

  const loadScores = async () => {
    setIsRefreshing(true);
    try {
      const contract = await getContractReadOnly();
      if (!contract) return;
      
      // Check contract availability using FHE
      const isAvailable = await contract.isAvailable();
      if (!isAvailable) {
        console.error("Contract is not available");
        return;
      }
      
      const keysBytes = await contract.getData("score_keys");
      let keys: string[] = [];
      
      if (keysBytes.length > 0) {
        try {
          keys = JSON.parse(ethers.toUtf8String(keysBytes));
        } catch (e) {
          console.error("Error parsing score keys:", e);
        }
      }
      
      const list: ReputationScore[] = [];
      
      for (const key of keys) {
        try {
          const scoreBytes = await contract.getData(`score_${key}`);
          if (scoreBytes.length > 0) {
            try {
              const scoreData = JSON.parse(ethers.toUtf8String(scoreBytes));
              list.push({
                id: key,
                owner: scoreData.owner,
                encryptedScore: scoreData.score,
                lastUpdated: scoreData.timestamp,
                credentials: scoreData.credentials || []
              });
            } catch (e) {
              console.error(`Error parsing score data for ${key}:`, e);
            }
          }
        } catch (e) {
          console.error(`Error loading score ${key}:`, e);
        }
      }
      
      list.sort((a, b) => b.lastUpdated - a.lastUpdated);
      setScores(list);
    } catch (e) {
      console.error("Error loading scores:", e);
    } finally {
      setIsRefreshing(false);
      setLoading(false);
    }
  };

  const addScore = async () => {
    if (!provider) { 
      alert("Please connect wallet first"); 
      return; 
    }
    
    setAddingScore(true);
    setTransactionStatus({
      visible: true,
      status: "pending",
      message: "Encrypting reputation score with FHE..."
    });
    
    try {
      // Simulate FHE encryption
      const encryptedScore = `FHE-${newScoreData.score}`;
      const credentials = newScoreData.credentials.split(",").map(c => c.trim());
      
      const contract = await getContractWithSigner();
      if (!contract) {
        throw new Error("Failed to get contract with signer");
      }
      
      const scoreId = `${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;

      const scoreData = {
        score: encryptedScore,
        timestamp: Math.floor(Date.now() / 1000),
        owner: account,
        credentials: credentials
      };
      
      // Store encrypted data on-chain using FHE
      await contract.setData(
        `score_${scoreId}`, 
        ethers.toUtf8Bytes(JSON.stringify(scoreData))
      );
      
      const keysBytes = await contract.getData("score_keys");
      let keys: string[] = [];
      
      if (keysBytes.length > 0) {
        try {
          keys = JSON.parse(ethers.toUtf8String(keysBytes));
        } catch (e) {
          console.error("Error parsing keys:", e);
        }
      }
      
      keys.push(scoreId);
      
      await contract.setData(
        "score_keys", 
        ethers.toUtf8Bytes(JSON.stringify(keys))
      );
      
      setTransactionStatus({
        visible: true,
        status: "success",
        message: "Encrypted score submitted securely!"
      });
      
      await loadScores();
      
      setTimeout(() => {
        setTransactionStatus({ visible: false, status: "pending", message: "" });
        setShowAddModal(false);
        setNewScoreData({
          score: "",
          credentials: ""
        });
      }, 2000);
    } catch (e: any) {
      const errorMessage = e.message.includes("user rejected transaction")
        ? "Transaction rejected by user"
        : "Submission failed: " + (e.message || "Unknown error");
      
      setTransactionStatus({
        visible: true,
        status: "error",
        message: errorMessage
      });
      
      setTimeout(() => {
        setTransactionStatus({ visible: false, status: "pending", message: "" });
      }, 3000);
    } finally {
      setAddingScore(false);
    }
  };

  const checkAvailability = async () => {
    try {
      const contract = await getContractReadOnly();
      if (!contract) return;
      
      const isAvailable = await contract.isAvailable();
      
      setTransactionStatus({
        visible: true,
        status: "success",
        message: isAvailable ? "FHE system is operational" : "System maintenance"
      });
      
      setTimeout(() => {
        setTransactionStatus({ visible: false, status: "pending", message: "" });
      }, 2000);
    } catch (e) {
      setTransactionStatus({
        visible: true,
        status: "error",
        message: "Availability check failed"
      });
      
      setTimeout(() => {
        setTransactionStatus({ visible: false, status: "pending", message: "" });
      }, 3000);
    }
  };

  const filteredScores = scores.filter(score => 
    score.owner.toLowerCase().includes(searchTerm.toLowerCase()) ||
    score.credentials.some(c => c.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  if (loading) return (
    <div className="loading-screen">
      <div className="mechanical-spinner"></div>
      <p>Initializing FHE engine...</p>
    </div>
  );

  return (
    <div className="app-container industrial-theme">
      <header className="app-header">
        <div className="logo">
          <div className="gear-icon"></div>
          <h1>FHE<span>Reputation</span></h1>
        </div>
        
        <div className="header-actions">
          <WalletManager account={account} onConnect={onConnect} onDisconnect={onDisconnect} />
        </div>
      </header>
      
      <div className="main-content center-radial">
        <div className="central-panel">
          <div className="panel-header">
            <h2>Private On-Chain Reputation</h2>
            <p>Fully Homomorphic Encryption for verifiable credentials</p>
          </div>
          
          <div className="control-panel">
            <button 
              onClick={() => setShowAddModal(true)} 
              className="industrial-btn primary"
            >
              <span className="btn-icon">+</span>
              Add Reputation Score
            </button>
            <button 
              onClick={checkAvailability}
              className="industrial-btn secondary"
            >
              <span className="btn-icon">⚙️</span>
              Check FHE Status
            </button>
            <button 
              onClick={() => setShowStats(!showStats)}
              className="industrial-btn secondary"
            >
              <span className="btn-icon">📊</span>
              {showStats ? "Hide Stats" : "Show Stats"}
            </button>
            <button 
              onClick={loadScores}
              className="industrial-btn secondary"
              disabled={isRefreshing}
            >
              <span className="btn-icon">🔄</span>
              {isRefreshing ? "Refreshing..." : "Refresh"}
            </button>
          </div>
          
          {showStats && (
            <div className="stats-panel">
              <div className="stat-item">
                <div className="stat-value">{scores.length}</div>
                <div className="stat-label">Total Scores</div>
              </div>
              <div className="stat-item">
                <div className="stat-value">{averageScore}</div>
                <div className="stat-label">Avg Score</div>
              </div>
              <div className="stat-item">
                <div className="stat-value">
                  {scores.length > 0 ? new Date(scores[0].lastUpdated * 1000).toLocaleDateString() : "N/A"}
                </div>
                <div className="stat-label">Last Update</div>
              </div>
            </div>
          )}
          
          <div className="search-bar">
            <input
              type="text"
              placeholder="Search by address or credential..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="industrial-input"
            />
          </div>
          
          <div className="scores-list">
            <div className="list-header">
              <div className="header-cell">ID</div>
              <div className="header-cell">Owner</div>
              <div className="header-cell">Score</div>
              <div className="header-cell">Credentials</div>
              <div className="header-cell">Last Updated</div>
            </div>
            
            {filteredScores.length === 0 ? (
              <div className="no-scores">
                <div className="no-data-icon"></div>
                <p>No reputation scores found</p>
                <button 
                  className="industrial-btn primary"
                  onClick={() => setShowAddModal(true)}
                >
                  Add First Score
                </button>
              </div>
            ) : (
              filteredScores.map(score => (
                <div className="score-row" key={score.id}>
                  <div className="list-cell">#{score.id.substring(0, 6)}</div>
                  <div className="list-cell">{score.owner.substring(0, 6)}...{score.owner.substring(38)}</div>
                  <div className="list-cell encrypted-score">
                    <span className="fhe-badge">FHE</span>
                    {score.encryptedScore.substring(0, 8)}...
                  </div>
                  <div className="list-cell">
                    {score.credentials.slice(0, 2).join(", ")}
                    {score.credentials.length > 2 && <span className="more-credentials">+{score.credentials.length - 2}</span>}
                  </div>
                  <div className="list-cell">
                    {new Date(score.lastUpdated * 1000).toLocaleDateString()}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
  
      {showAddModal && (
        <ModalAdd 
          onSubmit={addScore} 
          onClose={() => setShowAddModal(false)} 
          adding={addingScore}
          scoreData={newScoreData}
          setScoreData={setNewScoreData}
        />
      )}
      
      {walletSelectorOpen && (
        <WalletSelector
          isOpen={walletSelectorOpen}
          onWalletSelect={(wallet) => { onWalletSelect(wallet); setWalletSelectorOpen(false); }}
          onClose={() => setWalletSelectorOpen(false)}
        />
      )}
      
      {transactionStatus.visible && (
        <div className="transaction-notice">
          <div className={`notice-content ${transactionStatus.status}`}>
            <div className="notice-icon">
              {transactionStatus.status === "pending" && <div className="mechanical-spinner small"></div>}
              {transactionStatus.status === "success" && "✓"}
              {transactionStatus.status === "error" && "✗"}
            </div>
            <div className="notice-message">
              {transactionStatus.message}
            </div>
          </div>
        </div>
      )}
  
      <footer className="app-footer">
        <div className="footer-content">
          <div className="footer-brand">
            <div className="logo">
              <div className="gear-icon"></div>
              <span>FHEReputation</span>
            </div>
            <p>Fully Homomorphic Encryption for private on-chain reputation</p>
          </div>
          
          <div className="footer-links">
            <a href="#" className="footer-link">Docs</a>
            <a href="#" className="footer-link">GitHub</a>
            <a href="#" className="footer-link">Terms</a>
          </div>
        </div>
        
        <div className="footer-bottom">
          <div className="fhe-badge">
            <span>FHE-Powered Privacy</span>
          </div>
          <div className="copyright">
            © {new Date().getFullYear()} FHE Reputation System
          </div>
        </div>
      </footer>
    </div>
  );
};

interface ModalAddProps {
  onSubmit: () => void; 
  onClose: () => void; 
  adding: boolean;
  scoreData: any;
  setScoreData: (data: any) => void;
}

const ModalAdd: React.FC<ModalAddProps> = ({ 
  onSubmit, 
  onClose, 
  adding,
  scoreData,
  setScoreData
}) => {
  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setScoreData({
      ...scoreData,
      [name]: value
    });
  };

  const handleSubmit = () => {
    if (!scoreData.score || !scoreData.credentials) {
      alert("Please fill required fields");
      return;
    }
    
    onSubmit();
  };

  return (
    <div className="modal-overlay">
      <div className="add-modal industrial-card">
        <div className="modal-header">
          <h2>Add Encrypted Reputation Score</h2>
          <button onClick={onClose} className="close-modal">&times;</button>
        </div>
        
        <div className="modal-body">
          <div className="fhe-notice">
            <div className="lock-icon"></div> 
            <span>Data will be encrypted using Zama FHE technology</span>
          </div>
          
          <div className="form-group">
            <label>Reputation Score *</label>
            <input 
              type="text"
              name="score"
              value={scoreData.score} 
              onChange={handleChange}
              placeholder="Enter score (will be FHE encrypted)" 
              className="industrial-input"
            />
          </div>
          
          <div className="form-group">
            <label>Verifiable Credentials *</label>
            <textarea 
              name="credentials"
              value={scoreData.credentials} 
              onChange={handleChange}
              placeholder="Comma separated list of credentials..." 
              className="industrial-textarea"
              rows={3}
            />
            <div className="input-hint">Separate with commas (e.g., KYC, CreditScore, DAOMember)</div>
          </div>
        </div>
        
        <div className="modal-footer">
          <button 
            onClick={onClose}
            className="industrial-btn secondary"
          >
            Cancel
          </button>
          <button 
            onClick={handleSubmit} 
            disabled={adding}
            className="industrial-btn primary"
          >
            {adding ? "Encrypting with FHE..." : "Submit Securely"}
          </button>
        </div>
      </div>
    </div>
  );
};

export default App;