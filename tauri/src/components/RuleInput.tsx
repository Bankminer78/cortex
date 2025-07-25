import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Rule } from "../types";

interface RuleInputProps {
  onRuleAdded: (rule: Rule) => void;
}

export default function RuleInput({ onRuleAdded }: RuleInputProps) {
  const [input, setInput] = useState("");
  const [isProcessing, setIsProcessing] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!input.trim()) return;

    setIsProcessing(true);
    
    try {
      // Process natural language input to generate rule JSON
      const ruleJson = await invoke<string>("process_natural_language_rule", {
        naturalLanguage: input.trim()
      });

      // Create the rule
      const rule = await invoke<Rule>("add_rule", {
        name: `Rule: ${input.slice(0, 50)}${input.length > 50 ? '...' : ''}`,
        naturalLanguage: input.trim(),
        ruleJson: ruleJson
      });

      onRuleAdded(rule);
      setInput("");
    } catch (error) {
      console.error("Failed to create rule:", error);
      alert("Failed to create rule. Please try again.");
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-lg p-6">
      <h2 className="text-xl font-semibold text-gray-900 mb-4">
        Add New Rule
      </h2>
      
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="rule-input" className="block text-sm font-medium text-gray-700 mb-2">
            Describe your accountability goal in natural language
          </label>
          <textarea
            id="rule-input"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="e.g., 'Don't let me scroll on Instagram during work hours' or 'Block YouTube videos but allow music'"
            className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 resize-none text-gray-900 bg-white"
            rows={3}
            disabled={isProcessing}
          />
        </div>
        
        <div className="flex justify-end">
          <button
            type="submit"
            disabled={!input.trim() || isProcessing}
            className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isProcessing ? (
              <>
                <svg className="animate-spin -ml-1 mr-3 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Processing...
              </>
            ) : (
              "Add Rule"
            )}
          </button>
        </div>
      </form>

      <div className="mt-4 text-xs text-gray-500">
        <p className="font-medium mb-1">Examples:</p>
        <ul className="space-y-1">
          <li>• "Don't let me use Instagram during work hours"</li>
          <li>• "Block YouTube videos but allow music"</li>
          <li>• "Only allow r/MachineLearning on Reddit"</li>
          <li>• "Stop me from texting my ex"</li>
        </ul>
      </div>
    </div>
  );
}