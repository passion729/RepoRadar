"use client";

import { useEffect, useState } from "react";
import { ShieldIcon } from "./Icons";

type Tone = "blue" | "red" | "amber" | "purple" | "green" | "plain";
type Action = { label: string; key?: string; toast: string; spin?: boolean };
type Item = {
  id: string;
  tone: Tone;
  icon: React.ReactNode;
  title: string;
  meta: string;
  chip: string;
  tags?: [Tone, string][];
  quote?: string;
  primary?: Action;
  secondary?: Action;
  done: string;
};

// The app's own Now queue, ranked by urgency. Keys match Commands.swift.
const ITEMS: Item[] = [
  {
    id: "pr",
    tone: "blue",
    icon: "PR",
    title: "Add ETag caching to the notifications poller",
    meta: "api-gateway #214 · mika-chen",
    chip: "Review requested",
    tags: [["amber", "Checks 7/8 · 1 running"], ["amber", "Reviews 0/2 · you're next"], ["green", "No conflicts"]],
    primary: { label: "Approve", key: "A", toast: "Approved api-gateway #214" },
    secondary: { label: "Request changes", toast: "Requested changes on #214" },
    done: "Marked #214 done",
  },
  {
    id: "ci",
    tone: "red",
    icon: <span className="st st-f" />,
    title: "CI failed on main · test (macos-26)",
    meta: "RepoRadar · run #482 · your push",
    chip: "Your push failed",
    tags: [["red", "test (macos-26) failed"], ["plain", "build passed"], ["plain", "package skipped"]],
    primary: { label: "Re-run failed jobs", key: "R", toast: "Re-running 1 failed job", spin: true },
    done: "Marked run #482 done",
  },
  {
    id: "deploy",
    tone: "amber",
    icon: <ShieldIcon check />,
    title: "Deploy to production is waiting for you",
    meta: "web · Release #1290",
    chip: "Approval needed",
    tags: [["amber", "production"], ["plain", "Release #1290 · 4 commits"]],
    primary: { label: "Approve deploy", key: "A", toast: "Approved deploy to production" },
    secondary: { label: "Reject", toast: "Rejected deploy to production" },
    done: "Marked Release #1290 done",
  },
  {
    id: "mention",
    tone: "purple",
    icon: "@",
    title: "Rate limit regression after Tuesday deploy",
    meta: "web #1093 · jtorres mentioned you",
    chip: "Mention",
    quote: "@you can you check the rate limit regression?",
    done: "Marked web #1093 done",
  },
];

type Toast = { text: string; spin?: boolean; item: Item; index: number };

const UNDO_MS = 4000; // the app holds every action this long before it reaches GitHub

export default function NowDemo({ label, inspector }: { label: string; inspector: React.ReactNode }) {
  const [items, setItems] = useState(ITEMS);
  const [selected, setSelected] = useState(0);
  const [toast, setToast] = useState<Toast | null>(null);

  useEffect(() => {
    if (!toast) return;
    const id = setTimeout(() => setToast(null), UNDO_MS);
    return () => clearTimeout(id);
  }, [toast]);

  const current = Math.min(selected, items.length - 1);
  const has = (id: string) => items.some((i) => i.id === id);

  function act(item: Item, text: string, spin?: boolean) {
    const index = items.indexOf(item);
    setItems((prev) => prev.filter((i) => i !== item));
    setToast({ text, spin, item, index });
  }

  function undo() {
    if (!toast) return;
    const { item, index } = toast;
    setItems((prev) => prev.toSpliced(index, 0, item));
    setSelected(index);
    setToast(null);
  }

  function reset() {
    setItems(ITEMS);
    setSelected(0);
    setToast(null);
  }

  function onKeyDown(e: React.KeyboardEvent) {
    if (e.altKey) return;
    const key = e.key.toLowerCase();
    if (e.metaKey || e.ctrlKey) {
      if (key === "z" && toast) {
        e.preventDefault();
        undo();
      }
      return;
    }
    const item = items[current];
    if (key === "j" || key === "arrowdown") setSelected(Math.min(current + 1, items.length - 1));
    else if (key === "k" || key === "arrowup") setSelected(Math.max(current - 1, 0));
    else if (key === "e" && item) act(item, item.done);
    else if (item?.primary?.key?.toLowerCase() === key) act(item, item.primary.toast, item.primary.spin);
    else return;
    e.preventDefault();
  }

  const stats = [
    { n: has("pr") ? 3 : 2, label: "Reviews", sub: "oldest 2 days", tone: "blue" },
    { n: has("ci") ? 2 : 1, label: "Failing", sub: has("ci") ? "CI · Lint" : "Lint", tone: "red" },
    { n: 3, label: "Running", sub: "done in ~5 min", tone: "amber" },
    { n: has("mention") ? 12 : 11, label: "Unread", sub: has("mention") ? "2 mentions" : "1 mention", tone: "" },
  ];

  return (
    <div
      className="glass app-window"
      tabIndex={0}
      onKeyDown={onKeyDown}
      role="group"
      aria-label={label}
    >
      <aside className="side" aria-hidden="true">
        <div className="traffic">
          <span />
          <span />
          <span />
        </div>
        <span className="nv on">
          <span className="nv-dot" style={{ background: "#7d7bff" }} />
          Now<span className="b hot">{items.length}</span>
        </span>
        <span className="nv">
          <span className="nv-dot" style={{ background: "#3a8fff" }} />
          Inbox<span className="b">{stats[3].n}</span>
        </span>
        <span className="nv">
          <span className="nv-dot" style={{ background: "#a57cf0" }} />
          Pull Requests<span className="b">8</span>
        </span>
        <span className="nv">
          <span className="nv-dot" style={{ background: "#ff5c62" }} />
          Actions<span className="b alert">{stats[1].n}</span>
        </span>
        <span className="sync">
          <span className="live-dot" />
          Live · synced 8s ago
        </span>
      </aside>

      <div className="app-main">
        <div className="toolbar">
          <span className="toolbar-title">Now</span>
          <span className="search hide-sm" aria-hidden="true">
            Search or jump to…<kbd className="kbd">⌘K</kbd>
          </span>
        </div>

        <div className="stats">
          {stats.map((s) => (
            <div key={s.label} className="stat">
              <span className={`disp stat-n t-${s.tone}`}>{s.n}</span>
              <span className="stat-label">
                {s.label}
                <span>{s.sub}</span>
              </span>
            </div>
          ))}
        </div>

        <div className="app-body">
          <div className="queue">
            {items.length ? (
              <ul className="rows">
                {items.map((item, i) => (
                  <Row key={item.id} item={item} selected={i === current} onSelect={() => setSelected(i)} onAct={act} />
                ))}
              </ul>
            ) : (
              <div className="empty">
                <b>Nothing needs you.</b>
                <span>The queue refills when something new happens on GitHub.</span>
                <button type="button" className="mbtn" onClick={reset}>
                  Reset demo
                </button>
              </div>
            )}

            <div className="toast-slot" aria-live="polite">
              {toast ? (
                <div className="glass toast" key={toast.text + toast.index}>
                  <span className={toast.spin ? "st st-r" : "st st-s"} />
                  {toast.text}
                  <button type="button" className="mbtn" onClick={undo}>
                    Undo<kbd className="kbd">⌘Z</kbd>
                  </button>
                </div>
              ) : null}
            </div>
          </div>

          <div className="inspector hide-sm">{inspector}</div>
        </div>
      </div>
    </div>
  );
}

function Row({
  item,
  selected,
  onSelect,
  onAct,
}: {
  item: Item;
  selected: boolean;
  onSelect: () => void;
  onAct: (item: Item, text: string, spin?: boolean) => void;
}) {
  return (
    <li className={selected ? "row sel" : "row"}>
      <button type="button" className="row-head" onClick={onSelect} aria-expanded={selected}>
        <span className={`row-icon ri-${item.tone}`}>{item.icon}</span>
        <span className="row-text">
          <span className="row-title">{item.title}</span>
          <span className="row-meta muted">{item.meta}</span>
        </span>
        <span className={`chip c-${item.tone} hide-sm`}>{item.chip}</span>
      </button>

      {selected ? (
        <div className="row-detail">
          {item.tags ? (
            <div className="tags">
              {item.tags.map(([tone, text]) => (
                <span key={text} className={`chip c-${tone}`}>
                  {text}
                </span>
              ))}
            </div>
          ) : null}
          {item.quote ? <p className="quote">{item.quote}</p> : null}
          <div className="actions">
            {item.primary ? (
              <button type="button" className="mbtn pri" onClick={() => onAct(item, item.primary!.toast, item.primary!.spin)}>
                {item.primary.label}
                <kbd className="kbd kbd-on">{item.primary.key}</kbd>
              </button>
            ) : null}
            {item.secondary ? (
              <button type="button" className="mbtn" onClick={() => onAct(item, item.secondary!.toast)}>
                {item.secondary.label}
              </button>
            ) : null}
            <button type="button" className="mbtn ghost" onClick={() => onAct(item, item.done)}>
              Done<kbd className="kbd">E</kbd>
            </button>
          </div>
        </div>
      ) : null}
    </li>
  );
}
