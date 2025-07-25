use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rule {
    pub id: i64,
    pub name: String,
    pub natural_language: String,
    pub rule_json: String,
    pub is_active: bool,
    pub created_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewRule {
    pub name: String,
    pub natural_language: String,
    pub rule_json: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivityRecord {
    pub id: i64,
    pub timestamp: f64,
    pub activity: String,
    pub productive: bool,
    pub app: String,
    pub bundle_id: Option<String>,
    pub domain: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewActivityRecord {
    pub timestamp: f64,
    pub activity: String,
    pub productive: bool,
    pub app: String,
    pub bundle_id: Option<String>,
    pub domain: Option<String>,
}

pub struct Database {
    rules: Mutex<HashMap<i64, Rule>>,
    activities: Mutex<Vec<ActivityRecord>>,
    next_rule_id: Mutex<i64>,
    next_activity_id: Mutex<i64>,
}

impl Database {
    pub fn new() -> Self {
        Database {
            rules: Mutex::new(HashMap::new()),
            activities: Mutex::new(Vec::new()),
            next_rule_id: Mutex::new(1),
            next_activity_id: Mutex::new(1),
        }
    }

    pub async fn create_rule(&self, new_rule: NewRule) -> Result<Rule, String> {
        let now = chrono::Utc::now().timestamp();
        
        let mut next_id = self.next_rule_id.lock().unwrap();
        let rule_id = *next_id;
        *next_id += 1;
        
        let rule = Rule {
            id: rule_id,
            name: new_rule.name,
            natural_language: new_rule.natural_language,
            rule_json: new_rule.rule_json,
            is_active: true,
            created_at: now,
        };

        let mut rules = self.rules.lock().unwrap();
        rules.insert(rule_id, rule.clone());
        
        println!("Created rule: {} (ID: {})", rule.name, rule.id);
        Ok(rule)
    }

    pub async fn get_all_rules(&self) -> Result<Vec<Rule>, String> {
        let rules = self.rules.lock().unwrap();
        let mut rule_list: Vec<Rule> = rules.values().cloned().collect();
        rule_list.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        Ok(rule_list)
    }

    pub async fn get_active_rules(&self) -> Result<Vec<Rule>, String> {
        let rules = self.rules.lock().unwrap();
        let mut active_rules: Vec<Rule> = rules
            .values()
            .filter(|rule| rule.is_active)
            .cloned()
            .collect();
        active_rules.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        Ok(active_rules)
    }

    pub async fn toggle_rule(&self, rule_id: i64) -> Result<(), String> {
        let mut rules = self.rules.lock().unwrap();
        if let Some(rule) = rules.get_mut(&rule_id) {
            rule.is_active = !rule.is_active;
            println!("Toggled rule {} to: {}", rule.name, rule.is_active);
            Ok(())
        } else {
            Err("Rule not found".to_string())
        }
    }

    pub async fn delete_rule(&self, rule_id: i64) -> Result<(), String> {
        let mut rules = self.rules.lock().unwrap();
        if let Some(rule) = rules.remove(&rule_id) {
            println!("Deleted rule: {}", rule.name);
            Ok(())
        } else {
            Err("Rule not found".to_string())
        }
    }

    pub async fn log_activity(&self, new_activity: NewActivityRecord) -> Result<i64, String> {
        let mut next_id = self.next_activity_id.lock().unwrap();
        let activity_id = *next_id;
        *next_id += 1;

        let activity = ActivityRecord {
            id: activity_id,
            timestamp: new_activity.timestamp,
            activity: new_activity.activity,
            productive: new_activity.productive,
            app: new_activity.app,
            bundle_id: new_activity.bundle_id,
            domain: new_activity.domain,
        };

        let mut activities = self.activities.lock().unwrap();
        activities.push(activity);
        
        // Keep only last 1000 activities to prevent memory bloat
        if activities.len() > 1000 {
            let excess = activities.len() - 1000;
            activities.drain(0..excess);
        }

        Ok(activity_id)
    }

    pub async fn get_recent_activities(&self, limit: i64) -> Result<Vec<ActivityRecord>, String> {
        let activities = self.activities.lock().unwrap();
        let start_index = if activities.len() > limit as usize {
            activities.len() - limit as usize
        } else {
            0
        };
        
        let recent: Vec<ActivityRecord> = activities[start_index..].to_vec();
        Ok(recent)
    }

    pub async fn get_activities_in_range(
        &self,
        start_time: f64,
        end_time: f64,
    ) -> Result<Vec<ActivityRecord>, String> {
        let activities = self.activities.lock().unwrap();
        let filtered: Vec<ActivityRecord> = activities
            .iter()
            .filter(|activity| activity.timestamp >= start_time && activity.timestamp <= end_time)
            .cloned()
            .collect();
        Ok(filtered)
    }
}