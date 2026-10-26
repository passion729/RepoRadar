"use client";

import { useEffect, useState } from "react";

const TYPICAL = 220; // 3:40, the run's usual length
const SEGMENTS = 5;

const clock = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

/** The inspector's running workflow; its own island so the tick re-renders only this. */
export default function RunningNow() {
  const [elapsed, setElapsed] = useState(135);

  useEffect(() => {
    const id = setInterval(() => setElapsed((s) => (s >= TYPICAL ? 20 : s + 1)), 1000);
    return () => clearInterval(id);
  }, []);

  const done = Math.min(SEGMENTS - 1, Math.floor((elapsed / TYPICAL) * SEGMENTS));

  return (
    <div className="running">
      <span className="running-head">
        <span className="st st-r" />
        <b>RepoRadar</b>
        <span className="muted">CI</span>
      </span>
      <span className="steps" aria-hidden="true">
        {Array.from({ length: SEGMENTS }, (_, i) => (
          <span key={i} className={i < done ? "k-s" : i === done ? "k-r" : "k-0"} />
        ))}
      </span>
      <span className="muted running-time">{clock(elapsed)} · usually 3:40</span>
    </div>
  );
}
