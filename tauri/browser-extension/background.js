// Background script for Cortex Accountability Extension
// Handles communication between content scripts and native app

let activeTab = null;
let monitoringEnabled = true;

// Track active tab changes
chrome.tabs.onActivated.addListener(async (activeInfo) => {
  activeTab = activeInfo.tabId;
  
  try {
    const tab = await chrome.tabs.get(activeInfo.tabId);
    if (tab.url && !tab.url.startsWith('chrome://')) {
      // Extract domain and basic info
      const url = new URL(tab.url);
      const domain = url.hostname;
      
      console.log('Tab activated:', {
        domain,
        title: tab.title,
        url: tab.url
      });
      
      // Send to native app (placeholder for now)
      sendToNativeApp('tab_activated', {
        domain,
        title: tab.title,
        url: tab.url,
        timestamp: Date.now()
      });
    }
  } catch (error) {
    console.error('Error handling tab activation:', error);
  }
});

// Track URL changes within the same tab
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.url && !tab.url.startsWith('chrome://')) {
    try {
      const url = new URL(tab.url);
      const domain = url.hostname;
      
      console.log('Tab updated:', {
        domain,
        title: tab.title,
        url: tab.url
      });
      
      // Send to native app (placeholder for now)
      sendToNativeApp('tab_updated', {
        domain,
        title: tab.title,
        url: tab.url,
        timestamp: Date.now()
      });
    } catch (error) {
      console.error('Error handling tab update:', error);
    }
  }
});

// Listen for messages from content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('Background received message:', message);
  
  switch (message.type) {
    case 'page_activity':
      // Forward activity data to native app
      sendToNativeApp('page_activity', {
        ...message.data,
        tabId: sender.tab?.id,
        url: sender.tab?.url,
        timestamp: Date.now()
      });
      break;
      
    case 'get_monitoring_status':
      sendResponse({ enabled: monitoringEnabled });
      break;
      
    case 'toggle_monitoring':
      monitoringEnabled = !monitoringEnabled;
      // Notify all content scripts
      chrome.tabs.query({}, (tabs) => {
        tabs.forEach(tab => {
          if (tab.id) {
            chrome.tabs.sendMessage(tab.id, {
              type: 'monitoring_toggled',
              enabled: monitoringEnabled
            }).catch(() => {
              // Ignore errors for tabs that don't have content scripts
            });
          }
        });
      });
      sendResponse({ enabled: monitoringEnabled });
      break;
      
    default:
      console.log('Unknown message type:', message.type);
  }
  
  return true; // Keep message channel open for async response
});

// Function to send data to native app
function sendToNativeApp(eventType, data) {
  console.log('Sending to native app:', {
    event: eventType,
    data: data
  });
  
  // Send to Tauri app via HTTP (simple approach)
  sendToTauriApp(eventType, data);
  
  // Store in local storage as fallback
  chrome.storage.local.get(['activityLog'], (result) => {
    const activityLog = result.activityLog || [];
    activityLog.push({
      event: eventType,
      data: data,
      timestamp: Date.now()
    });
    
    // Keep only last 100 entries
    if (activityLog.length > 100) {
      activityLog.splice(0, activityLog.length - 100);
    }
    
    chrome.storage.local.set({ activityLog });
  });
}

// Send data to Tauri app via HTTP
async function sendToTauriApp(eventType, data) {
  try {
    const logEntry = {
      domain: data.domain || new URL(data.url || 'http://unknown').hostname,
      activity: data.activity || eventType,
      url: data.url || '',
      title: data.title || '',
      elements: data.elements || null,
      timestamp: Date.now()
    };
    
    // Send to Tauri HTTP server
    const response = await fetch('http://127.0.0.1:8080/extension-data', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        event_type: eventType,
        data: logEntry
      })
    });
    
    if (response.ok) {
      const result = await response.json();
      console.log('✅ Successfully sent to Tauri app:', result);
      
      // Update connection status
      chrome.storage.local.set({ 
        lastTauriConnection: Date.now(),
        tauriConnected: true 
      });
    } else {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    
  } catch (error) {
    console.error('❌ Failed to send to Tauri app:', error);
    
    // Mark as disconnected and store locally as fallback
    chrome.storage.local.set({ 
      tauriConnected: false,
      lastTauriError: error.message 
    });
    
    // Store locally as fallback
    chrome.storage.local.get(['tauriQueue'], (result) => {
      const tauriQueue = result.tauriQueue || [];
      
      const logEntry = {
        domain: data.domain || new URL(data.url || 'http://unknown').hostname,
        activity: data.activity || eventType,
        url: data.url || '',
        title: data.title || '',
        elements: data.elements || null,
        timestamp: Date.now()
      };
      
      tauriQueue.push(logEntry);
      
      // Keep only last 50 entries for Tauri
      if (tauriQueue.length > 50) {
        tauriQueue.splice(0, tauriQueue.length - 50);
      }
      
      chrome.storage.local.set({ tauriQueue });
    });
  }
}

// Check Tauri app connection
async function checkTauriConnection() {
  try {
    const response = await fetch('http://127.0.0.1:8080/health', {
      method: 'GET',
      timeout: 3000
    });
    
    if (response.ok) {
      const result = await response.json();
      chrome.storage.local.set({ 
        tauriConnected: true,
        lastTauriConnection: Date.now(),
        tauriStatus: result
      });
      return true;
    } else {
      throw new Error(`Health check failed: ${response.status}`);
    }
  } catch (error) {
    chrome.storage.local.set({ 
      tauriConnected: false,
      lastTauriError: error.message,
      lastTauriCheck: Date.now()
    });
    return false;
  }
}

// Initialize extension
chrome.runtime.onInstalled.addListener(() => {
  console.log('Cortex Accountability Extension installed');
  
  // Set default settings
  chrome.storage.local.set({
    monitoringEnabled: true,
    activityLog: [],
    tauriConnected: false
  });
  
  // Initial connection check
  checkTauriConnection();
});

// Periodic health check (every 30 seconds)
setInterval(checkTauriConnection, 30000);

// Handle extension startup
chrome.runtime.onStartup.addListener(() => {
  console.log('Cortex Accountability Extension started');
});