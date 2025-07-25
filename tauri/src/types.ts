export interface Rule {
  id?: number;
  name: string;
  natural_language: string;
  rule_json: string;
  is_active: boolean;
  created_at: number;
}

export interface ActivityRecord {
  id?: number;
  timestamp: number;
  activity: string;
  productive: boolean;
  app: string;
  bundle_id?: string;
  domain?: string;
}

export interface ExtensionLog {
  timestamp: number;
  domain: string;
  activity: string;
  url: string;
  title: string;
  elements?: any;
}