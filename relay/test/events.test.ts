import { describe, it, expect } from "vitest";
import { classify } from "../src/events";
const ME = "AnthonyPluth";
const repository = { name: "r", owner: { login: "o" } };
const pr = { number: 3, title: "T", html_url: "u", merged: false };
const pull = (action: string, sender = "bob", extra: any = {}) => classify("pull_request", { action, sender: { login: sender }, repository, pull_request: { ...pr, ...extra.pr }, ...extra.top }, ME);
const ref = { owner: "o", repo: "r", number: 3 };

describe("classify", () => {
  it("opened notifies even if self, and evaluates", () => {
    for (const s of ["bob", "anthonypluth"]) { const c = pull("opened", s); expect(c.notices[0]!.kind).toBe("opened"); expect(c.evaluate).toEqual([ref]); }
  });
  it("ready_for_review", () => {
    expect(pull("ready_for_review").notices[0]!.kind).toBe("readyForReview");
    const s = pull("ready_for_review", "ANTHONYPLUTH"); expect(s.notices).toEqual([]); expect(s.evaluate).toEqual([ref]);
  });
  it("synchronize/reopened evaluate only", () => {
    for (const a of ["synchronize", "reopened"]) { const c = pull(a); expect(c.notices).toEqual([]); expect(c.evaluate).toEqual([ref]); }
  });
  it("review_requested only for self", () => {
    expect(pull("review_requested", "bob", { top: { requested_reviewer: { login: "anthonypluth" } } }).notices[0]!.kind).toBe("reviewRequested");
    expect(pull("review_requested", "bob", { top: { requested_reviewer: { login: "carol" } } }).notices).toEqual([]);
  });
  it("closed: merged vs closed vs self", () => {
    expect(pull("closed", "bob", { pr: { merged: true } }).notices[0]!.kind).toBe("merged");
    expect(pull("closed").notices[0]!.kind).toBe("closed");
    expect(pull("closed", ME).notices).toEqual([]);
  });
  it("review submitted", () => {
    const f = (sender: string) => classify("pull_request_review", { action: "submitted", sender: { login: sender }, repository, pull_request: pr, review: { state: "APPROVED" } }, ME);
    expect(f("bob").notices[0]).toMatchObject({ kind: "reviewSubmitted", reviewState: "approved", actor: "bob" });
    expect(f(ME).notices).toEqual([]);
  });
  it("issue_comment on PR vs plain issue vs self", () => {
    const f = (sender: string, isPR: boolean) => classify("issue_comment", { action: "created", sender: { login: sender }, repository, issue: { ...pr, ...(isPR ? { pull_request: {} } : {}) } }, ME);
    expect(f("bob", true).notices[0]!.kind).toBe("comment");
    expect(f("bob", false).notices).toEqual([]);
    expect(f(ME, true).notices).toEqual([]);
  });
  it("check_suite completed", () => {
    const f = (conclusion: string) => classify("check_suite", { action: "completed", sender: { login: "x" }, repository, check_suite: { conclusion, pull_requests: [{ number: 3 }] } }, ME);
    expect(f("failure").notices[0]!.kind).toBe("checksFailed");
    expect(f("timed_out").notices).toHaveLength(1);
    const ok = f("success"); expect(ok.notices).toEqual([]); expect(ok.evaluate).toEqual([ref]);
  });
  it("status", () => {
    const f = (state: string) => classify("status", { sha: "abc", state, repository, sender: { login: "x" } }, ME);
    expect(f("failure").sha).toEqual({ owner: "o", repo: "r", sha: "abc", failed: true });
    expect(f("success").sha!.failed).toBe(false);
  });
  it("unknown", () => expect(classify("push", {}, ME)).toEqual({ notices: [], evaluate: [] }));
});
