// Popup script for Cortex Accountability Extension

document.addEventListener('DOMContentLoaded', async () => {
  const statusElement = document.getElementById('status');
  const statusText = document.getElementById('status-text');
  const toggleBtn = document.getElementById('toggle-btn');
  const openAppBtn = document.getElementById('open-app-btn');
  const activityList = document.getElementById('activity-list');
  
  // Load initial status
  await updateStatus();
  await loadRecentActivity();
  
  // Set up event listeners
  toggleBtn.addEventListener('click', toggleMonitoring);
  openAppBtn.addEventListener('click', openMainApp);
  
  async function updateStatus() {
    try {
      const response = await chrome.runtime.sendMessage({ type: 'get_monitoring_status' });
      const isActive = response?.enabled ?? true;
      
      if (isActive) {
        statusElement.className = 'status active';
        statusText.textContent = 'Monitoring Active';
        toggleBtn.textContent = 'Pause Monitoring';
      } else {
        statusElement.className = 'status inactive';
        statusText.textContent = 'Monitoring Paused';
        toggleBtn.textContent = 'Resume Monitoring';
      }
    } catch (error) {
      console.error('Failed to get monitoring status:', error);
      statusElement.className = 'status inactive';
      statusText.textContent = 'Status Unknown';
    }
  }
  
  async function toggleMonitoring() {
    try {
      const response = await chrome.runtime.sendMessage({ type: 'toggle_monitoring' });
      await updateStatus();
    } catch (error) {
      console.error('Failed to toggle monitoring:', error);
    }
  }
  
  async function openMainApp() {
    // TODO: Implement native messaging to open the main Tauri app
    // For now, show a placeholder message
    alert('This would open the main Cortex app. Native messaging integration coming soon!');
  }
  
  async function loadRecentActivity() {
    try {
      const result = await chrome.storage.local.get(['activityLog']);
      const activityLog = result.activityLog || [];
      
      if (activityLog.length === 0) {
        activityList.innerHTML = '<div class=\"empty-state\">No recent activity</div>';
        return;
      }
      
      // Show last 5 activities
      const recentActivities = activityLog.slice(-5).reverse();
      
      activityList.innerHTML = recentActivities.map(entry => {
        const time = new Date(entry.timestamp).toLocaleTimeString([], { 
          hour: '2-digit', 
          minute: '2-digit' 
        });
        
        let domain = 'Unknown';
        let activityType = entry.event;
        
        if (entry.data) {
          if (entry.data.domain) {
            domain = entry.data.domain;
          }
          if (entry.data.activity) {
            activityType = entry.data.activity;
          }
        }
        
        return `
          <div class=\"activity-item\">
            <div class=\"activity-domain\">${domain}</div>
            <div class=\"activity-type\">${activityType.replace(/_/g, ' ')}</div>
            <div class=\"activity-time\">${time}</div>
          </div>
        `;
      }).join('');
      
    } catch (error) {
      console.error('Failed to load activity log:', error);
      activityList.innerHTML = '<div class=\"empty-state\">Failed to load activity</div>';
    }
  }
});