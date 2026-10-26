"use client";

import { useEffect, useState } from "react";

const cmd = (e: KeyboardEvent) => e.metaKey || e.ctrlKey;
const plain = (e: KeyboardEvent) => !cmd(e) && !e.altKey;

// Shortcuts from Commands.swift, in the order of the page's labels; `match` lights the card when you press the real key.
const KEYS: { caps: string[]; match: (e: KeyboardEvent, k: string) => boolean }[] = [
  { caps: ["J", "K"], match: (e, k) => plain(e) && (k === "j" || k === "k") },
  { caps: ["E"], match: (e, k) => plain(e) && k === "e" },
  { caps: ["A"], match: (e, k) => plain(e) && k === "a" },
  { caps: ["R"], match: (e, k) => plain(e) && k === "r" },
  { caps: ["⇧", "⌘", "M"], match: (e, k) => cmd(e) && e.shiftKey && k === "m" },
  { caps: ["⌘", "K"], match: (e, k) => cmd(e) && k === "k" },
  { caps: ["⌘", "Z"], match: (e, k) => cmd(e) && k === "z" },
  { caps: ["⌘", "↵"], match: (e, k) => cmd(e) && k === "enter" },
];

export default function KeyboardGrid({ labels }: { labels: string[] }) {
  const [hit, setHit] = useState(-1);

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    function onKey(e: KeyboardEvent) {
      if (e.target instanceof HTMLElement && e.target.closest("input, textarea")) return;
      const key = e.key.toLowerCase();
      const i = KEYS.findIndex((k) => k.match(e, key));
      if (i < 0) return;
      setHit(i);
      clearTimeout(timer);
      timer = setTimeout(() => setHit(-1), 700);
    }
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
      clearTimeout(timer);
    };
  }, []);

  return (
    <div className="keys-grid">
      {KEYS.map((k, i) => (
        <div key={k.caps.join("")} className={i === hit ? "panel key-card hit" : "panel key-card"}>
          <span className="key-caps">
            {k.caps.map((c) => (
              <kbd key={c} className="key">
                {c}
              </kbd>
            ))}
          </span>
          <span className="key-what">{labels[i]}</span>
        </div>
      ))}
    </div>
  );
}
