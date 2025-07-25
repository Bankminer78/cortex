import { useState } from "react";
import { Rule } from "../types";

interface RuleCardProps {
  rule: Rule;
  onToggle: (ruleId: number) => void;
  onDelete: (ruleId: number) => void;
}

export default function RuleCard({ rule, onToggle, onDelete }: RuleCardProps) {
  const [showDetails, setShowDetails] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleToggle = () => {
    if (rule.id) {
      onToggle(rule.id);
    }
  };

  const handleDelete = () => {
    if (rule.id) {
      onDelete(rule.id);
      setShowDeleteConfirm(false);
    }
  };

  const formatDate = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleDateString();
  };

  const getRuleJSON = () => {
    try {
      return JSON.parse(rule.rule_json);
    } catch {
      return null;
    }
  };

  const ruleData = getRuleJSON();

  return (
    <div className={`bg-white rounded-lg shadow-sm border-2 transition-all duration-200 ${
      rule.is_active 
        ? 'border-green-200 bg-green-50' 
        : 'border-gray-200'
    }`}>
      <div className="p-4">
        <div className="flex items-start justify-between">
          <div className="flex-1 min-w-0">
            <div className="flex items-center space-x-3 mb-2">
              <h3 className={`text-lg font-medium truncate ${
                rule.is_active ? 'text-gray-900' : 'text-gray-500'
              }`}>
                {rule.name}
              </h3>
              <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                rule.is_active 
                  ? 'bg-green-100 text-green-800' 
                  : 'bg-gray-100 text-gray-800'
              }`}>
                {rule.is_active ? 'Active' : 'Inactive'}
              </span>
            </div>
            
            <p className="text-sm text-gray-600 mb-3">
              "{rule.natural_language}"
            </p>
            
            <div className="text-xs text-gray-500">
              Created: {formatDate(rule.created_at)}
            </div>
          </div>

          <div className="flex items-center space-x-2 ml-4">
            {/* Toggle button */}
            <button
              onClick={handleToggle}
              className={`p-2 rounded-full transition-colors ${
                rule.is_active 
                  ? 'text-green-600 hover:bg-green-100' 
                  : 'text-gray-400 hover:bg-gray-100'
              }`}
              title={rule.is_active ? 'Disable rule' : 'Enable rule'}
            >
              {rule.is_active ? (
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
              ) : (
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <circle cx="12" cy="12" r="10" strokeWidth="2"/>
                </svg>
              )}
            </button>

            {/* Details button */}
            <button
              onClick={() => setShowDetails(!showDetails)}
              className="p-2 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-full transition-colors"
              title="Show details"
            >
              <svg 
                className={`w-5 h-5 transition-transform ${showDetails ? 'rotate-180' : ''}`} 
                fill="none" 
                stroke="currentColor" 
                viewBox="0 0 24 24"
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 9l-7 7-7-7" />
              </svg>
            </button>

            {/* Delete button */}
            <button
              onClick={() => setShowDeleteConfirm(true)}
              className="p-2 text-red-400 hover:text-red-600 hover:bg-red-50 rounded-full transition-colors"
              title="Delete rule"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
              </svg>
            </button>
          </div>
        </div>

        {/* Details section */}
        {showDetails && ruleData && (
          <div className="mt-4 pt-4 border-t border-gray-200">
            <div className="bg-gray-50 rounded-md p-3">
              <h4 className="text-sm font-medium text-gray-900 mb-2">Rule Configuration:</h4>
              <pre className="text-xs text-gray-600 whitespace-pre-wrap overflow-x-auto">
                {JSON.stringify(ruleData, null, 2)}
              </pre>
            </div>
          </div>
        )}

        {/* Delete confirmation dialog */}
        {showDeleteConfirm && (
          <div className="mt-4 pt-4 border-t border-gray-200">
            <div className="bg-red-50 border border-red-200 rounded-md p-3">
              <p className="text-sm text-red-800 mb-3">
                Are you sure you want to delete this rule? This action cannot be undone.
              </p>
              <div className="flex justify-end space-x-2">
                <button
                  onClick={() => setShowDeleteConfirm(false)}
                  className="px-3 py-1 text-sm text-gray-600 bg-white border border-gray-300 rounded hover:bg-gray-50"
                >
                  Cancel
                </button>
                <button
                  onClick={handleDelete}
                  className="px-3 py-1 text-sm text-white bg-red-600 rounded hover:bg-red-700"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}