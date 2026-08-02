export type DailyPlanItemType =
  | "weekdayMaterial"
  | "weeklyBoss"
  | "growthGoal"
  | "generalMaterial";

export interface DailyPlanEnrichItem {
  id: string;
  type: DailyPlanItemType;
  title: string;
  priority: number;
  reasons: string[];
  characterIds: string[];
  materialIds: string[];
  estimatedResinCost?: number | null;
}

export interface DailyPlanEnrichRequest {
  weekday: number;
  currentResin?: number | null;
  maxResin?: number | null;
  items: DailyPlanEnrichItem[];
}

export interface DailyPlanEnrichResult {
  orderedItemIds: string[];
  reasonsByItemId: Record<string, string[]>;
  enriched: boolean;
  model?: string;
}
