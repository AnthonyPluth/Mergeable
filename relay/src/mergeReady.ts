export interface PRStatus {
  state: "OPEN" | "CLOSED" | "MERGED"; isDraft: boolean;
  mergeable: "MERGEABLE" | "CONFLICTING" | "UNKNOWN";
  rollup: "SUCCESS" | "PENDING" | "FAILURE" | "ERROR" | "EXPECTED" | null;
  headOid: string; title: string; url: string; author: string | null;
}
export function isMergeReady(s: PRStatus): boolean {
  return s.state === "OPEN" && !s.isDraft && (s.rollup === null || s.rollup === "SUCCESS") && s.mergeable !== "CONFLICTING";
}
