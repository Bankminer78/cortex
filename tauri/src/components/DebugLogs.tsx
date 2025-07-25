import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { ExtensionLog } from "../types";

export default function DebugLogs() {
  const [logs, setLogs] = useState<ExtensionLog[]>([]);
  const [isAutoRefresh, setIsAutoRefresh] = useState(true);
  const [extensionStatus, setExtensionStatus] = useState<any>(null);

  const loadLogs = async () => {
    try {
      const extensionLogs = await invoke<ExtensionLog[]>("get_extension_logs");
      setLogs(extensionLogs.slice().reverse()); // Show newest first
    } catch (error) {
      console.error("Failed to load extension logs:", error);
    }
  };

  const loadExtensionStatus = async () => {
    try {
      const status = await invoke("get_extension_status");
      setExtensionStatus(status);
    } catch (error) {
      console.error("Failed to load extension status:", error);
    }
  };

  const clearLogs = async () => {
    try {
      await invoke("clear_extension_logs");
      setLogs([]);
    } catch (error) {
      console.error("Failed to clear extension logs:", error);
    }
  };

  const simulateData = async () => {
    try {
      await invoke("simulate_extension_data");
      await loadLogs(); // Refresh after simulation
    } catch (error) {
      console.error("Failed to simulate extension data:", error);
    }
  };

  useEffect(() => {
    // Load logs and status immediately
    loadLogs();
    loadExtensionStatus();

    // Set up auto-refresh every 3 seconds if enabled
    let interval: ReturnType<typeof setInterval> | null = null;
    if (isAutoRefresh) {
      interval = setInterval(() => {
        loadLogs();
        loadExtensionStatus();
      }, 3000);
    }

    return () => {
      if (interval) {
        clearInterval(interval);
      }
    };
  }, [isAutoRefresh]);

  const formatTimestamp = (timestamp: number) => {
    return new Date(timestamp).toLocaleTimeString();
  };

  const formatElements = (elements: any) => {
    if (!elements) return "None";
    
    try {
      return JSON.stringify(elements, null, 2);
    } catch {
      return "Invalid JSON";
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-lg p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-xl font-semibold text-gray-900 mb-2">
            Chrome Extension Debug Logs
          </h2>
          {/* Connection Status */}
          <div className="flex items-center space-x-4">
            <div className={`flex items-center space-x-2 px-3 py-1 rounded-full text-sm ${
              extensionStatus?.connected 
                ? 'bg-green-100 text-green-800' 
                : 'bg-red-100 text-red-800'
            }`}>
              <div className={`w-2 h-2 rounded-full ${
                extensionStatus?.connected ? 'bg-green-500' : 'bg-red-500'
              }`}></div>
              <span>
                {extensionStatus?.connected ? 'Connected' : 'Disconnected'}
              </span>
            </div>
            {extensionStatus?.server_url && (
              <span className="text-xs text-gray-500">
                Server: {extensionStatus.server_url}
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center space-x-4">
          <label className="flex items-center">
            <input
              type="checkbox"
              checked={isAutoRefresh}
              onChange={(e) => setIsAutoRefresh(e.target.checked)}
              className="mr-2"
            />
            <span className="text-sm text-gray-600">Auto-refresh (3s)</span>
          </label>
          <button
            onClick={loadLogs}
            className="px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
          >
            Refresh
          </button>
          <button
            onClick={simulateData}
            className="px-3 py-1 text-sm bg-green-600 text-white rounded hover:bg-green-700"
          >
            Simulate Data
          </button>
          <button
            onClick={clearLogs}
            className="px-3 py-1 text-sm bg-red-600 text-white rounded hover:bg-red-700"
          >
            Clear
          </button>
        </div>
      </div>

      {logs.length === 0 ? (
        <div className="text-center py-12">
          <div className="text-gray-500 mb-4">
            <svg className="mx-auto h-12 w-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
          </div>
          <h3 className="text-lg font-medium text-gray-900 mb-2">No logs yet</h3>
          <p className="text-gray-600">
            Install and activate the Chrome extension to see activity logs here
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="text-sm text-gray-600 mb-4">
            Showing {logs.length} logs (newest first)
          </div>
          
          <div className="max-h-96 overflow-y-auto space-y-3">
            {logs.map((log, index) => (
              <div key={index} className="border border-gray-200 rounded-lg p-4 bg-gray-50">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center space-x-3">
                    <span className="text-sm font-medium text-blue-600">
                      {log.domain}
                    </span>
                    <span className="text-xs bg-gray-200 text-gray-700 px-2 py-1 rounded">
                      {log.activity}
                    </span>
                  </div>
                  <span className="text-xs text-gray-500">
                    {formatTimestamp(log.timestamp)}
                  </span>
                </div>
                
                <div className="text-sm text-gray-700 mb-2">
                  <strong>Title:</strong> {log.title || "No title"}
                </div>
                
                <div className="text-xs text-gray-600 mb-2 break-all">
                  <strong>URL:</strong> {log.url}
                </div>
                
                {log.elements && (
                  <details className="mt-2">
                    <summary className="text-xs text-gray-500 cursor-pointer hover:text-gray-700">
                      UI Elements (click to expand)
                    </summary>
                    <pre className="mt-2 text-xs bg-white p-2 rounded border overflow-x-auto">
                      {formatElements(log.elements)}
                    </pre>
                  </details>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}