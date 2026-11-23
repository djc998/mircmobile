// Turns the JSON from GET /admin/reports into a readable list, newest
// first, with reports from the last 24 hours marked NEW. Used by
// check-reports.sh; reads the JSON on stdin when run directly.

const DAY = 24 * 60 * 60 * 1000;

/** How long ago [iso] was, e.g. "3 h ago". */
export function ago(iso, now = Date.now()) {
  const ms = now - Date.parse(iso);
  if (!Number.isFinite(ms)) return 'unknown time';
  const min = Math.round(ms / 60000);
  if (min < 1) return 'just now';
  if (min < 60) return `${min} min ago`;
  const h = Math.round(min / 60);
  if (h < 48) return `${h} h ago`;
  return `${Math.round(h / 24)} days ago`;
}

/** The report list as text. */
export function formatReports(body, now = Date.now()) {
  const reports = [...(body?.reports ?? [])].sort((a, b) =>
    a.reportedAt < b.reportedAt ? 1 : -1,
  );
  if (reports.length === 0) return 'No reports. Nothing to review.';
  const fresh = reports.filter((r) => now - Date.parse(r.reportedAt) < DAY);
  const lines = [
    `${reports.length} report${reports.length === 1 ? '' : 's'}, ` +
      `${fresh.length} in the last 24 hours (review those today).`,
    '',
  ];
  for (const r of reports) {
    const isNew = now - Date.parse(r.reportedAt) < DAY;
    const what = r.kind === 'message' ? 'Message' : 'Photo';
    const where = r.kind === 'message' ? (r.room ?? 'a private chat') : null;
    lines.push(
      `${isNew ? 'NEW  ' : '     '}${what} from ${r.sender || '?'} on ` +
        `${r.network || '?'}${where ? ` in ${where}` : ''}, ` +
        `${ago(r.reportedAt, now)} (${r.reportedAt})`,
    );
    lines.push(`     Reason: ${r.reason || '(none given)'}`);
    if (r.kind === 'message') {
      lines.push(`     Text:   ${String(r.text ?? '').replace(/\s+/g, ' ')}`);
    } else {
      lines.push(`     Photo:  ${r.link ?? r.id ?? '?'}`);
    }
    lines.push('');
  }
  return lines.join('\n').trimEnd();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => (input += chunk));
  process.stdin.on('end', () => {
    let body;
    try {
      body = JSON.parse(input);
    } catch {
      console.error(`The server sent something unexpected:\n${input}`);
      process.exit(1);
    }
    if (body.error) {
      console.error(`The server said: ${body.error}`);
      process.exit(1);
    }
    console.log(formatReports(body));
  });
}
