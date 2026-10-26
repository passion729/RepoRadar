"use client";

import { useState } from "react";
import { ShieldIcon } from "./Icons";

const ROWS = [
  { id: "ci", tone: "red", icon: <span className="st st-f" />, title: "CI failed on main", meta: "RepoRadar #482 · 12m", action: "Re-run", done: "Re-running", pri: true },
  { id: "deploy", tone: "amber", icon: <ShieldIcon size={13} />, title: "Production deploy waiting", meta: "web Release #1290", action: "Approve", done: "Approved", pri: false },
];

export default function MenuBarDemo() {
  const [done, setDone] = useState<string[]>([]);

  return (
    <div className="glass menu">
      {ROWS.map((r) => {
        const isDone = done.includes(r.id);
        return (
          <div key={r.id} className="menu-row">
            <span className={`menu-icon ri-${isDone ? "green" : r.tone}`}>{isDone ? <span className={r.id === "ci" ? "st st-r" : "st st-s"} /> : r.icon}</span>
            <span className="menu-text">
              <b>{r.title}</b>
              <span className="muted">{isDone ? `${r.done} · just now` : r.meta}</span>
            </span>
            {isDone ? (
              <button type="button" className="mbtn" onClick={() => setDone((prev) => prev.filter((id) => id !== r.id))}>
                Undo
              </button>
            ) : (
              <button type="button" className={r.pri ? "mbtn pri" : "mbtn"} onClick={() => setDone((prev) => [...prev, r.id])}>
                {r.action}
              </button>
            )}
          </div>
        );
      })}
    </div>
  );
}
