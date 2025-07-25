use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::{broadcast, Mutex};
use warp::Filter;
use serde::{Deserialize, Serialize};
use crate::ExtensionLog;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtensionMessage {
    pub event_type: String,
    pub data: ExtensionMessageData,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtensionMessageData {
    pub domain: String,
    pub activity: String,
    pub url: String,
    pub title: String,
    pub elements: Option<serde_json::Value>,
}

pub struct WebSocketServer {
    pub sender: broadcast::Sender<ExtensionLog>,
    pub connection_count: Arc<Mutex<u32>>,
}

impl WebSocketServer {
    pub fn new() -> Self {
        let (sender, _) = broadcast::channel(100);
        
        WebSocketServer {
            sender,
            connection_count: Arc::new(Mutex::new(0)),
        }
    }

    pub async fn start(&self, port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let sender = self.sender.clone();
        let connection_count = self.connection_count.clone();

        // CORS headers for all routes
        let cors = warp::cors()
            .allow_any_origin()
            .allow_headers(vec!["content-type"])
            .allow_methods(vec!["GET", "POST", "OPTIONS"]);

        // Health check endpoint
        let health = warp::path("health")
            .and(warp::get())
            .map(|| {
                warp::reply::json(&serde_json::json!({
                    "status": "ok",
                    "service": "cortex-extension-bridge"
                }))
            });

        // Extension data endpoint (HTTP POST)
        let extension_data = warp::path("extension-data")
            .and(warp::post())
            .and(warp::body::json())
            .and(warp::any().map(move || sender.clone()))
            .and_then(handle_extension_data);

        // Extension connection status
        let connection_status = warp::path("status")
            .and(warp::get())
            .and(warp::any().map(move || connection_count.clone()))
            .and_then(handle_connection_status);

        let routes = health
            .or(extension_data)
            .or(connection_status)
            .with(cors)
            .recover(handle_rejection);

        let addr: SocketAddr = ([127, 0, 0, 1], port).into();
        println!("🌐 Extension bridge server starting on http://127.0.0.1:{}", port);

        warp::serve(routes)
            .run(addr)
            .await;

        Ok(())
    }

    pub async fn get_connection_count(&self) -> u32 {
        *self.connection_count.lock().await
    }
}

async fn handle_extension_data(
    message: ExtensionMessage,
    sender: broadcast::Sender<ExtensionLog>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let log = ExtensionLog {
        timestamp: chrono::Utc::now().timestamp_millis() as f64,
        domain: message.data.domain,
        activity: message.data.activity,
        url: message.data.url,
        title: message.data.title,
        elements: message.data.elements,
    };

    // Send to broadcast channel (this will be picked up by the Tauri app)
    if let Err(e) = sender.send(log.clone()) {
        eprintln!("Failed to broadcast extension log: {}", e);
    }

    println!("📦 Received extension data: {} on {}", log.activity, log.domain);

    Ok(warp::reply::json(&serde_json::json!({
        "status": "received",
        "timestamp": log.timestamp
    })))
}

async fn handle_connection_status(
    connection_count: Arc<Mutex<u32>>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let count = *connection_count.lock().await;
    Ok(warp::reply::json(&serde_json::json!({
        "connected_extensions": count,
        "server_status": "running"
    })))
}

async fn handle_rejection(err: warp::Rejection) -> Result<impl warp::Reply, std::convert::Infallible> {
    let code;
    let message;

    if err.is_not_found() {
        code = warp::http::StatusCode::NOT_FOUND;
        message = "Not Found";
    } else if let Some(_) = err.find::<warp::filters::body::BodyDeserializeError>() {
        code = warp::http::StatusCode::BAD_REQUEST;
        message = "Invalid JSON";
    } else {
        code = warp::http::StatusCode::INTERNAL_SERVER_ERROR;
        message = "Internal Server Error";
    }

    let json = warp::reply::json(&serde_json::json!({
        "error": message
    }));

    Ok(warp::reply::with_status(json, code))
}