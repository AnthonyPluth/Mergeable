import type { Env } from "./env";
import { sendPush, type ApnsConfig } from "./apns";
import { classify, type Notice, type PRRef } from "./events";
import { renderAlert } from "./copy";
import { appJwt, installationToken, fetchPRStatus, prsForSha } from "./githubApp";
import { isMergeReady } from "./mergeReady";
import { claim, confirm, release } from "./dedupe";
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
  const claims = new Map<Notice, string>();
  for (const pr of evaluate) {
    const k = `${pr.owner}/${pr.repo}#${pr.number}`.toLowerCase();
    if (seen.has(k) || !token) continue;
    seen.add(k);
    const s = await fetchPRStatus(token, pr);
    for (const n of notices) if (!n.prTitle && n.pr.number === pr.number && n.pr.repo === pr.repo) { n.prTitle = s.title; n.url = s.url; }
    const key = `ready:${pr.owner}/${pr.repo}#${pr.number}@${s.headOid}`;
    if (isMergeReady(s) && (await claim(env.MERGEABLE, key))) {
      notices.push({ kind: "mergeReady", pr, prTitle: s.title, url: s.url });
      claims.set(notices[notices.length - 1]!, key);
    }
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
    let delivered = devices.length === 0;
    try {
      for (const d of devices) {
        const r = await sendPush(cfg, d.token, d.environment, body);
        if (r.status === 200) delivered = true;
        if (r.status === 410 || (r.status === 400 && r.reason === "BadDeviceToken")) await removeDevice(env.MERGEABLE, d.token);
      }
    } finally {
      const key = claims.get(n);
      if (key) await (delivered ? confirm(env.MERGEABLE, key, 2592000) : release(env.MERGEABLE, key));
    }
  }
}
