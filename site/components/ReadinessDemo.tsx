"use client";

import { useState } from "react";

type Review = "pending" | "approved" | "changes";

const CHECKS = [
  { name: "integration", st: "r", left: "31%", width: "50%", dur: "6:02" },
  { name: "codeql", st: "s", left: "0%", width: "44%", dur: "4:48" },
  { name: "build (macos)", st: "s", left: "0%", width: "31%", dur: "3:24" },
  { name: "lint", st: "s", left: "0%", width: "7%", dur: "0:48" },
];

function Step({ icon, title, sub, current = false, quiet = false }: { icon: React.ReactNode; title: string; sub: React.ReactNode; current?: boolean; quiet?: boolean }) {
  return (
    <div className={`rstep${current ? " current" : ""}${quiet ? " quiet" : ""}`}>
      {icon}
      <span>
        <b>{title}</b>
        <span className="muted">{sub}</span>
      </span>
    </div>
  );
}

/** The readiness bar: the blocking step is highlighted, and moves once you review. */
export default function ReadinessDemo() {
  const [review, setReview] = useState<Review>("pending");
  const reviewed = review !== "pending";

  return (
    <div className="glass card">
      <div className="pr-meta muted">
        <span>lumen-labs/api-gateway #214</span>
        <span className="mono chip chip-branch">feat/etag-cache → main</span>
      </div>
      <div className="pr-title">Add ETag caching to the notifications poller</div>

      <div className="readiness" aria-live="polite">
        <Step icon={<span className="st st-r" />} title="Checks" sub={reviewed ? "Waiting on integration" : "7 of 8"} current={review === "approved"} />
        {review === "pending" ? (
          <Step icon={<span className="badge-count">0/2</span>} title="Reviews" sub={<span className="t-blue">You&apos;re next</span>} current />
        ) : review === "approved" ? (
          <Step icon={<span className="st st-s" />} title="Reviews" sub="1 of 2 · you approved" />
        ) : (
          <Step icon={<span className="st st-f" />} title="Reviews" sub={<span className="t-red">Changes requested</span>} current />
        )}
        <Step icon={<span className="st st-s" />} title="Branch" sub="No conflicts" />
        <Step icon={<span className="ring" />} title="Merge" sub={review === "approved" ? "Auto-merge on" : "Auto-merge"} quiet />
      </div>

      <div className="checks">
        {CHECKS.map((c) => (
          <div key={c.name} className="check">
            <span className={`st st-${c.st}`} />
            <span className="check-name">{c.name}</span>
            <span className="track">
              <span className={`bar k-${c.st}`} style={{ left: c.left, width: c.width }} />
            </span>
            <span className="muted mono check-dur">{c.dur}</span>
          </div>
        ))}
      </div>

      <div className="btn-row">
        {reviewed ? (
          <>
            <span className="verdict">
              <span className={review === "approved" ? "st st-s" : "st st-f"} />
              {review === "approved" ? "You approved. It merges when checks pass." : "You requested changes."}
            </span>
            <button type="button" className="mbtn" onClick={() => setReview("pending")}>
              Undo
            </button>
          </>
        ) : (
          <>
            <button type="button" className="mbtn" onClick={() => setReview("changes")}>
              Request changes
            </button>
            <button type="button" className="mbtn pri" onClick={() => setReview("approved")}>
              Approve<kbd className="kbd kbd-on">A</kbd>
            </button>
          </>
        )}
      </div>
    </div>
  );
}
