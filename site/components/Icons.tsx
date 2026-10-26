export function RadarMark() {
  return (
    <svg viewBox="0 0 16 16" fill="none" stroke="#8cc4ff" strokeWidth="1.5" strokeLinecap="round" aria-hidden="true">
      <circle cx="8" cy="8" r="6" />
      <circle cx="8" cy="8" r="2.6" />
      <path d="M8 8l4.2-4.2" />
    </svg>
  );
}

export function GitHubMark() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" className="icon" aria-hidden="true">
      <path d="M8 .2a8 8 0 0 0-2.5 15.6c.4.1.5-.2.5-.4v-1.5c-2.2.5-2.7-1-2.7-1-.4-.9-.9-1.2-.9-1.2-.7-.5.1-.5.1-.5.8.1 1.2.8 1.2.8.7 1.3 1.9.9 2.3.7.1-.5.3-.9.5-1.1-1.8-.2-3.6-.9-3.6-4 0-.9.3-1.6.8-2.1-.1-.2-.4-1 .1-2.1 0 0 .7-.2 2.2.8a7.6 7.6 0 0 1 4 0c1.5-1 2.2-.8 2.2-.8.4 1.1.2 1.9.1 2.1.5.6.8 1.3.8 2.1 0 3.1-1.9 3.8-3.6 4 .3.3.6.8.6 1.5v2.2c0 .2.1.5.6.4A8 8 0 0 0 8 .2z" />
    </svg>
  );
}

export function DownloadIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className="icon" aria-hidden="true">
      <path d="M8 2v8.5M4.5 7.2 8 10.7l3.5-3.5M3 13.5h10" />
    </svg>
  );
}

/** The deployment shield; `check` adds the tick used in the Now queue. */
export function ShieldIcon({ check = false, size = 15 }: { check?: boolean; size?: number }) {
  return (
    <svg viewBox="0 0 16 16" width={size} height={size} fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M8 1.8l5 2v4c0 3.2-2.2 5.3-5 6.4-2.8-1.1-5-3.2-5-6.4v-4z" />
      {check ? <path d="M5.8 8l1.6 1.6 2.9-3.1" /> : null}
    </svg>
  );
}
