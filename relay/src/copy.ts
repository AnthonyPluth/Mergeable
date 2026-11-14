import type { Notice } from "./events";
export function renderAlert(n: Notice): { title: string; subtitle: string; body: string } {
  const a = n.actor ?? "Someone";
  let title: string;
  switch (n.kind) {
    case "mergeReady": title = "Ready to merge"; break;
    case "opened": title = "New pull request"; break;
    case "readyForReview": title = "Ready for review"; break;
    case "reviewRequested": title = "Review requested"; break;
    case "reviewSubmitted":
      title = n.reviewState === "approved" ? `${a} approved` : n.reviewState === "changes_requested" ? `${a} requested changes` : `${a} reviewed`;
      break;
    case "comment": title = `${a} commented`; break;
    case "checksFailed": title = "Checks failed"; break;
    case "merged": title = `Merged by ${a}`; break;
    case "closed": title = `Closed by ${a}`; break;
  }
  return { title, subtitle: `${n.pr.owner}/${n.pr.repo} #${n.pr.number}`, body: n.prTitle };
}
