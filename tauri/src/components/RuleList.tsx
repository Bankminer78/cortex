import { Rule } from "../types";
import RuleCard from "./RuleCard";

interface RuleListProps {
  rules: Rule[];
  onToggle: (ruleId: number) => void;
  onDelete: (ruleId: number) => void;
}

export default function RuleList({ rules, onToggle, onDelete }: RuleListProps) {
  if (rules.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow p-8 text-center">
        <div className="w-16 h-16 mx-auto mb-4 text-gray-400">
          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path 
              strokeLinecap="round" 
              strokeLinejoin="round" 
              strokeWidth={1} 
              d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
            />
          </svg>
        </div>
        <h3 className="text-lg font-medium text-gray-900 mb-2">
          No rules yet
        </h3>
        <p className="text-gray-600">
          Add your first accountability rule above to get started
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold text-gray-900">
          Your Rules ({rules.length})
        </h2>
        <div className="text-sm text-gray-600">
          {rules.filter(r => r.is_active).length} active, {rules.filter(r => !r.is_active).length} inactive
        </div>
      </div>
      
      <div className="space-y-3">
        {rules.map((rule) => (
          <RuleCard
            key={rule.id}
            rule={rule}
            onToggle={onToggle}
            onDelete={onDelete}
          />
        ))}
      </div>
    </div>
  );
}