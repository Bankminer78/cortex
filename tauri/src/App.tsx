import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Rule } from "./types";
import RuleInput from "./components/RuleInput";
import RuleList from "./components/RuleList";
import DebugLogs from "./components/DebugLogs";

function App() {
  const [rules, setRules] = useState<Rule[]>([]);
  const [activeTab, setActiveTab] = useState<'rules' | 'debug'>('rules');

  const loadRules = async () => {
    try {
      const loadedRules = await invoke<Rule[]>("get_rules");
      setRules(loadedRules);
    } catch (error) {
      console.error("Failed to load rules:", error);
    }
  };

  useEffect(() => {
    loadRules();
  }, []);

  const handleRuleAdded = (rule: Rule) => {
    setRules(prev => [...prev, rule]);
  };

  const handleRuleToggle = async (ruleId: number) => {
    try {
      await invoke("toggle_rule", { ruleId });
      setRules(prev => 
        prev.map(rule => 
          rule.id === ruleId 
            ? { ...rule, is_active: !rule.is_active }
            : rule
        )
      );
    } catch (error) {
      console.error("Failed to toggle rule:", error);
    }
  };

  const handleRuleDelete = async (ruleId: number) => {
    try {
      await invoke("delete_rule", { ruleId });
      setRules(prev => prev.filter(rule => rule.id !== ruleId));
    } catch (error) {
      console.error("Failed to delete rule:", error);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">
            Cortex Accountability
          </h1>
          <p className="text-lg text-gray-600">
            Set natural language rules to stay focused and productive
          </p>
        </div>

        {/* Status indicator */}
        <div className="flex justify-center mb-8">
          <div className="flex items-center space-x-2 bg-green-100 text-green-800 px-4 py-2 rounded-full">
            <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
            <span className="text-sm font-medium">Active</span>
          </div>
        </div>

        {/* Tabs */}
        <div className="mb-8">
          <div className="border-b border-gray-200">
            <nav className="-mb-px flex space-x-8">
              <button
                onClick={() => setActiveTab('rules')}
                className={`py-2 px-1 border-b-2 font-medium text-sm ${
                  activeTab === 'rules'
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Rules
              </button>
              <button
                onClick={() => setActiveTab('debug')}
                className={`py-2 px-1 border-b-2 font-medium text-sm ${
                  activeTab === 'debug'
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Debug Logs
              </button>
            </nav>
          </div>
        </div>

        {/* Tab Content */}
        {activeTab === 'rules' && (
          <>
            {/* Rule Input */}
            <div className="mb-8">
              <RuleInput onRuleAdded={handleRuleAdded} />
            </div>

            {/* Rules List */}
            <div className="mb-8">
              <RuleList 
                rules={rules}
                onToggle={handleRuleToggle}
                onDelete={handleRuleDelete}
              />
            </div>
          </>
        )}

        {activeTab === 'debug' && (
          <div className="mb-8">
            <DebugLogs />
          </div>
        )}

        {/* Stats */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-white p-6 rounded-lg shadow">
            <div className="text-2xl font-bold text-gray-900">
              {rules.length}
            </div>
            <div className="text-sm text-gray-600">Total Rules</div>
          </div>
          <div className="bg-white p-6 rounded-lg shadow">
            <div className="text-2xl font-bold text-green-600">
              {rules.filter(r => r.is_active).length}
            </div>
            <div className="text-sm text-gray-600">Active Rules</div>
          </div>
          <div className="bg-white p-6 rounded-lg shadow">
            <div className="text-2xl font-bold text-gray-400">
              {rules.filter(r => !r.is_active).length}
            </div>
            <div className="text-sm text-gray-600">Inactive Rules</div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;