"use client";

import { useState } from "react";

/** A mention thread with a reply box that works: what you send joins the thread. */
export default function InboxDemo() {
  const [draft, setDraft] = useState("");
  const [replies, setReplies] = useState<string[]>([]);

  function send(e?: React.FormEvent) {
    e?.preventDefault();
    const text = draft.trim();
    if (!text) return;
    setReplies((prev) => [...prev, text]);
    setDraft("");
  }

  return (
    <div className="thread">
      <Comment who="jtorres" initials="JT" when="commented 1h ago">
        <span className="at">@you</span> can you check the rate limit regression?
      </Comment>
      {replies.map((text, i) => (
        <Comment key={i} who="you" initials="You" when="commented just now" mine>
          {text}
        </Comment>
      ))}
      <form className="reply" onSubmit={send}>
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && (e.metaKey || e.ctrlKey) && send()}
          placeholder="Reply to jtorres…"
          aria-label="Reply to jtorres"
          maxLength={280}
        />
        <button type="submit" className="mbtn pri" disabled={!draft.trim()}>
          Comment<kbd className="kbd kbd-on">⌘↵</kbd>
        </button>
      </form>
    </div>
  );
}

function Comment({ who, initials, when, mine = false, children }: { who: string; initials: string; when: string; mine?: boolean; children: React.ReactNode }) {
  return (
    <div className={mine ? "comment-row mine" : "comment-row"}>
      <span className="avatar">{initials}</span>
      <div className="comment">
        <div className="comment-head">
          <b>{who}</b> <span className="muted">{when}</span>
        </div>
        <div className="comment-body">{children}</div>
      </div>
    </div>
  );
}
