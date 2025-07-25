// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod database;
mod websocket_server;

use database::{Database, NewRule};
use websocket_server::WebSocketServer;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::collections::VecDeque;
use tauri::{Manager, State};
use tokio::sync::{broadcast, Mutex};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtensionLog {
    pub timestamp: f64,
    pub domain: String,
    pub activity: String,
    pub url: String,
    pub title: String,
    pub elements: Option<serde_json::Value>,
}

// App State
pub struct AppState {
    pub db: Arc<Mutex<Database>>,
    pub extension_logs: Arc<Mutex<VecDeque<ExtensionLog>>>,
    pub websocket_server: Arc<WebSocketServer>,
    pub extension_receiver: Arc<Mutex<Option<broadcast::Receiver<ExtensionLog>>>>,
}

// Tauri commands
#[tauri::command]
async fn add_rule(
    state: State<'_, AppState>,
    name: String,
    natural_language: String,
    rule_json: String,
) -> Result<database::Rule, String> {
    let db = state.db.lock().await;
    
    let new_rule = NewRule {
        name,
        natural_language,
        rule_json,
    };
    
    match db.create_rule(new_rule).await {
        Ok(rule) => {
            println!("Added rule: {}", rule.name);
            Ok(rule)
        }
        Err(e) => {
            println!("Failed to add rule: {}", e);
            Err(format!("Failed to add rule: {}", e))
        }
    }
}

#[tauri::command]
async fn get_rules(state: State<'_, AppState>) -> Result<Vec<database::Rule>, String> {
    let db = state.db.lock().await;
    
    match db.get_all_rules().await {
        Ok(rules) => Ok(rules),
        Err(e) => {
            println!("Failed to get rules: {}", e);
            Err(format!("Failed to get rules: {}", e))
        }
    }
}

#[tauri::command]
async fn toggle_rule(state: State<'_, AppState>, rule_id: i64) -> Result<(), String> {
    let db = state.db.lock().await;
    
    match db.toggle_rule(rule_id).await {
        Ok(_) => {
            println!("Toggled rule: {}", rule_id);
            Ok(())
        }
        Err(e) => {
            println!("Failed to toggle rule: {}", e);
            Err(format!("Failed to toggle rule: {}", e))
        }
    }
}

#[tauri::command]
async fn delete_rule(state: State<'_, AppState>, rule_id: i64) -> Result<(), String> {
    let db = state.db.lock().await;
    
    match db.delete_rule(rule_id).await {
        Ok(_) => {
            println!("Deleted rule: {}", rule_id);
            Ok(())
        }
        Err(e) => {
            println!("Failed to delete rule: {}", e);
            Err(format!("Failed to delete rule: {}", e))
        }
    }
}

#[tauri::command]
async fn process_natural_language_rule(natural_language: String) -> Result<String, String> {
    // Basic LLM processing - in a real implementation this would call an actual LLM
    println!("Processing rule: {}", natural_language);
    
    // Generate a basic rule structure based on the input
    let rule_json = serde_json::json!({
        "name": format!("Rule from: {}", &natural_language[..std::cmp::min(natural_language.len(), 30)]),
        "type": "basic",
        "conditions": [{
            "field": "activity",
            "operator": "contains",
            "value": extract_activity_from_text(&natural_language)
        }],
        "actions": [{
            "type": "popup",
            "parameters": {
                "message": format!("Rule triggered: {}", natural_language)
            }
        }]
    });
    
    Ok(rule_json.to_string())
}

fn extract_activity_from_text(text: &str) -> String {
    let text_lower = text.to_lowercase();
    
    if text_lower.contains("instagram") || text_lower.contains("insta") {
        "instagram_activity".to_string()
    } else if text_lower.contains("youtube") {
        "youtube_activity".to_string()
    } else if text_lower.contains("twitter") || text_lower.contains("x.com") {
        "twitter_activity".to_string()
    } else if text_lower.contains("facebook") {
        "facebook_activity".to_string()
    } else if text_lower.contains("reddit") {
        "reddit_activity".to_string()
    } else if text_lower.contains("tiktok") {
        "tiktok_activity".to_string()
    } else {
        "general_activity".to_string()
    }
}

#[tauri::command]
async fn log_extension_activity(
    state: State<'_, AppState>,
    domain: String,
    activity: String,
    url: String,
    title: String,
    elements: Option<serde_json::Value>,
) -> Result<(), String> {
    let log = ExtensionLog {
        timestamp: chrono::Utc::now().timestamp_millis() as f64,
        domain: domain.clone(),
        activity: activity.clone(),
        url,
        title,
        elements,
    };
    
    let mut logs = state.extension_logs.lock().await;
    logs.push_back(log);
    
    // Keep only last 100 logs
    if logs.len() > 100 {
        logs.pop_front();
    }
    
    println!("Extension activity logged: {} on {}", activity, domain);
    Ok(())
}

#[tauri::command]
async fn get_extension_logs(state: State<'_, AppState>) -> Result<Vec<ExtensionLog>, String> {
    let logs = state.extension_logs.lock().await;
    Ok(logs.iter().cloned().collect())
}

#[tauri::command] 
async fn clear_extension_logs(state: State<'_, AppState>) -> Result<(), String> {
    let mut logs = state.extension_logs.lock().await;
    logs.clear();
    println!("Extension logs cleared");
    Ok(())
}

#[tauri::command]
async fn get_extension_status(state: State<'_, AppState>) -> Result<serde_json::Value, String> {
    let logs_count = state.extension_logs.lock().await.len();
    
    // Check if we received data recently (within last 60 seconds)
    let now = chrono::Utc::now().timestamp_millis() as f64;
    let recent_activity = {
        let logs = state.extension_logs.lock().await;
        logs.iter().any(|log| (now - log.timestamp) < 60000.0)  // 60 seconds
    };
    
    Ok(serde_json::json!({
        "connected": recent_activity,
        "server_running": true,
        "total_logs": logs_count,
        "server_url": "http://127.0.0.1:8080",
        "last_activity": recent_activity
    }))
}

#[tauri::command]
async fn simulate_extension_data(state: State<'_, AppState>) -> Result<(), String> {
    // This simulates receiving data from the Chrome extension
    // In a real implementation, this would poll the extension or use native messaging
    
    let sample_logs = vec![
        ExtensionLog {
            timestamp: chrono::Utc::now().timestamp_millis() as f64,
            domain: "instagram.com".to_string(),
            activity: "scrolling_instagram".to_string(),
            url: "https://instagram.com/".to_string(),
            title: "Instagram".to_string(),
            elements: Some(serde_json::json!({
                "headings": ["Stories", "Reels", "Feed"],
                "buttons": ["Like", "Comment", "Share"],
                "images": 15
            })),
        },
        ExtensionLog {
            timestamp: (chrono::Utc::now().timestamp_millis() - 5000) as f64,
            domain: "youtube.com".to_string(),
            activity: "watching_videos".to_string(),
            url: "https://youtube.com/watch?v=xyz".to_string(),
            title: "Funny Cat Video - YouTube".to_string(),
            elements: Some(serde_json::json!({
                "video_title": "Funny Cat Video",
                "duration": "5:23",
                "views": "1.2M"
            })),
        },
    ];
    
    let mut logs = state.extension_logs.lock().await;
    for log in sample_logs {
        logs.push_back(log);
    }
    
    // Keep only last 100 logs
    while logs.len() > 100 {
        logs.pop_front();
    }
    
    println!("Simulated extension data added");
    Ok(())
}

fn main() {
    let db = Database::new();
    let websocket_server = Arc::new(WebSocketServer::new());
    let extension_receiver = Arc::new(Mutex::new(Some(websocket_server.sender.subscribe())));
    
    let app_state = AppState {
        db: Arc::new(Mutex::new(db)),
        extension_logs: Arc::new(Mutex::new(VecDeque::new())),
        websocket_server: websocket_server.clone(),
        extension_receiver: extension_receiver.clone(),
    };
    
    // Clone references before moving into setup
    let websocket_server_setup = websocket_server.clone();
    let extension_logs_setup = app_state.extension_logs.clone();
    let extension_receiver_setup = extension_receiver.clone();
    
    tauri::Builder::default()
        .manage(app_state)
        .plugin(tauri_plugin_shell::init())
        .setup(move |_app| {
            // Start WebSocket server in background
            tauri::async_runtime::spawn(async move {
                if let Err(e) = websocket_server_setup.start(8080).await {
                    eprintln!("WebSocket server error: {}", e);
                }
            });
            
            // Start extension log receiver task
            tauri::async_runtime::spawn(async move {
                let receiver_opt = extension_receiver_setup.lock().await.take();
                if let Some(mut receiver) = receiver_opt {
                    while let Ok(log) = receiver.recv().await {
                        let mut logs = extension_logs_setup.lock().await;
                        logs.push_back(log);
                        
                        // Keep only last 100 logs
                        while logs.len() > 100 {
                            logs.pop_front();
                        }
                    }
                }
            });
            
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            add_rule,
            get_rules,
            toggle_rule,
            delete_rule,
            process_natural_language_rule,
            log_extension_activity,
            get_extension_logs,
            clear_extension_logs,
            get_extension_status,
            simulate_extension_data
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}