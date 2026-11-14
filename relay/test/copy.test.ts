import { it, expect } from "vitest";
import { renderAlert } from "../src/copy";
import type { Notice } from "../src/events";
const base = { pr: { owner: "o", repo: "r", number: 7 }, prTitle: "T", url: "u", actor: "bob" };
const t = (n: Partial<Notice> & { kind: Notice["kind"] }) => renderAlert({ ...base, ...n } as Notice);
it("renders every kind", () => {
  expect(t({ kind: "mergeReady" })).toEqual({ title: "Ready to merge", subtitle: "o/r #7", body: "T" });
  expect(t({ kind: "opened" }).title).toBe("New pull request");
  expect(t({ kind: "readyForReview" }).title).toBe("Ready for review");
  expect(t({ kind: "reviewRequested" }).title).toBe("Review requested");
  expect(t({ kind: "reviewSubmitted", reviewState: "approved" }).title).toBe("bob approved");
  expect(t({ kind: "reviewSubmitted", reviewState: "changes_requested" }).title).toBe("bob requested changes");
  expect(t({ kind: "reviewSubmitted", reviewState: "commented" }).title).toBe("bob reviewed");
  expect(t({ kind: "comment" }).title).toBe("bob commented");
  expect(t({ kind: "checksFailed" }).title).toBe("Checks failed");
  expect(t({ kind: "merged" }).title).toBe("Merged by bob");
  expect(t({ kind: "closed" }).title).toBe("Closed by bob");
});
