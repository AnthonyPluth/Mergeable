export type EventKind = "mergeReady" | "opened" | "readyForReview" | "reviewRequested" | "reviewSubmitted" | "comment" | "checksFailed" | "merged" | "closed";
export interface PRRef { owner: string; repo: string; number: number }
export interface Notice { kind: EventKind; pr: PRRef; prTitle: string; url: string; actor?: string; reviewState?: "approved" | "changes_requested" | "commented" }
export interface Classified { notices: Notice[]; evaluate: PRRef[]; sha?: { owner: string; repo: string; sha: string; failed: boolean } }

const same = (a: string | undefined, b: string) => (a ?? "").toLowerCase() === b.toLowerCase();

export function classify(event: string, payload: any, selfLogin: string): Classified {
  const out: Classified = { notices: [], evaluate: [] };
  const sender: string | undefined = payload?.sender?.login;
  const isSelf = same(sender, selfLogin);
  const repo = payload?.repository;
  const ref = (n: number): PRRef => ({ owner: repo.owner.login, repo: repo.name, number: n });
  const notice = (kind: EventKind, pr: any, extra: Partial<Notice> = {}): Notice =>
    ({ kind, pr: ref(pr.number), prTitle: pr.title, url: pr.html_url, actor: sender, ...extra });

  switch (event) {
    case "pull_request": {
      const pr = payload.pull_request;
      switch (payload.action) {
        case "opened":
          out.notices.push(notice("opened", pr)); out.evaluate.push(ref(pr.number)); break;
        case "ready_for_review":
          if (!isSelf) out.notices.push(notice("readyForReview", pr));
          out.evaluate.push(ref(pr.number)); break;
        case "synchronize": case "reopened":
          out.evaluate.push(ref(pr.number)); break;
        case "review_requested":
          if (same(payload.requested_reviewer?.login, selfLogin)) out.notices.push(notice("reviewRequested", pr));
          break;
        case "closed":
          if (!isSelf) out.notices.push(notice(pr.merged ? "merged" : "closed", pr));
          break;
      }
      break;
    }
    case "pull_request_review":
      if (payload.action === "submitted" && !isSelf) {
        const st = String(payload.review?.state ?? "").toLowerCase();
        const reviewState = st === "approved" ? "approved" : st === "changes_requested" ? "changes_requested" : "commented";
        out.notices.push(notice("reviewSubmitted", payload.pull_request, { reviewState }));
      }
      break;
    case "issue_comment":
      if (payload.action === "created" && payload.issue?.pull_request && !isSelf)
        out.notices.push(notice("comment", payload.issue));
      break;
    case "check_suite": {
      if (payload.action !== "completed") break;
      const failed = ["failure", "timed_out"].includes(payload.check_suite?.conclusion);
      for (const p of payload.check_suite?.pull_requests ?? []) {
        out.evaluate.push(ref(p.number));
        if (failed) out.notices.push({ kind: "checksFailed", pr: ref(p.number), prTitle: "", url: `https://github.com/${repo.owner.login}/${repo.name}/pull/${p.number}` });
      }
      break;
    }
    case "status":
      out.sha = { owner: repo.owner.login, repo: repo.name, sha: payload.sha, failed: ["failure", "error"].includes(payload.state) };
      break;
  }
  return out;
}
