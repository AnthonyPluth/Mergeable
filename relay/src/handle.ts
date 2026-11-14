import type { Env } from "./env";
import { sendPush, type ApnsConfig } from "./apns";
import { classify, type Notice, type PRRef } from "./events";
import { renderAlert } from "./copy";
import { appJwt, installationToken, fetchPRStatus, prsForSha } from "./githubApp";
import { isMergeReady } from "./mergeReady";
import { firstTime } from "./dedupe";
import { listDevices, removeDevice } from "./devices";

export async function handleWebhook(env: Env, event: string, payload: any): Promise<void> {
  const c = classify(event, payload, env.SELF_LOGIN);
  const notices: Notice[] = [...c.notices];
  const evaluate: PRRef[] = [...c.evaluate];
  const installId: number | undefined = payload?.installation?.id;
  const needsGitHub = evaluate.length > 0 || c.sha || notices.some((n) => !n.prTitle);
  let token: string | undefined;
  if (needsGitHub && installId) token = await installationToken(await appJwt(env.NOTIFIER_APP_ID, env.NOTIFIER_PRIVATE_KEY, Math.floor(Date.now() / 1000)), installId);

  if (c.sha && token) {
    for (const n of await prsForSha(token, c.sha.owner, c.sha.repo, c.sha.sha)) {
      const ref = { owner: c.sha.owner, repo: c.sha.repo, number: n };
      evaluate.push(ref);
      if (c.sha.failed) notices.push({ kind: "checksFailed", pr: ref, prTitle: "", url: `https://github.com/${ref.owner}/${ref.repo}/pull/${n}` });
    }
  }

  const seen = new Set<string>();
  for (const pr of evaluate) {
    const k = `${pr.owner}/${pr.repo}#${pr.number}`.toLowerCase();
    if (seen.has(k) || !token) continue;
    seen.add(k);
    const s = await fetchPRStatus(token, pr);
    for (const n of notices) if (!n.prTitle && n.pr.number === pr.number && n.pr.repo === pr.repo) { n.prTitle = s.title; n.url = s.url; }
    if (isMergeReady(s) && (await firstTime(env.MERGEABLE, `ready:${pr.owner}/${pr.repo}#${pr.number}@${s.headOid}`, 2592000)))
      notices.push({ kind: "mergeReady", pr, prTitle: s.title, url: s.url });
  }

  const sendable = notices.filter((n) => n.prTitle);
  if (!sendable.length) return;
  const cfg: ApnsConfig = { keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, p8Pem: env.APNS_PRIVATE_KEY, topic: "com.pluth.mergeable" };
  const devices = await listDevices(env.MERGEABLE);
  for (const n of sendable) {
    const alert = renderAlert(n);
    const body = {
      aps: { alert, sound: "default", "thread-id": `${n.pr.owner}/${n.pr.repo}#${n.pr.number}` },
      mergeable: { v: 1, kind: n.kind, owner: n.pr.owner, repo: n.pr.repo, number: n.pr.number, url: n.url },
    };
    for (const d of devices) {
      const r = await sendPush(cfg, d.token, d.environment, body);
      if (r.status === 410 || (r.status === 400 && r.reason === "BadDeviceToken")) await removeDevice(env.MERGEABLE, d.token);
    }
  }
}
