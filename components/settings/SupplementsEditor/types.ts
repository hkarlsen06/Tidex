export interface SupplementRule {
  id: string;
  days: number[];
  from: string;
  to: string;
  rate?: number;
  percent?: number;
}

export interface SupplementsData {
  rules: Omit<SupplementRule, 'id'>[];
}
