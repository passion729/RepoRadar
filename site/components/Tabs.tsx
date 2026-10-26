"use client";

import { useId, useRef, useState } from "react";

type Tab = { label: string; panel: React.ReactNode };

/** ARIA tabs. Every panel is rendered (hidden ones too) so the static HTML carries all the copy. */
export default function Tabs({ label, tabs }: { label: string; tabs: Tab[] }) {
  const [active, setActive] = useState(0);
  const id = useId();
  const list = useRef<HTMLDivElement>(null);

  function onKeyDown(e: React.KeyboardEvent) {
    const step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
    if (!step) return;
    const next = (active + step + tabs.length) % tabs.length;
    setActive(next);
    list.current?.querySelectorAll<HTMLButtonElement>('[role="tab"]')[next]?.focus();
  }

  return (
    <div className="tabs">
      <div role="tablist" aria-label={label} className="tablist" ref={list} onKeyDown={onKeyDown}>
        {tabs.map((t, i) => (
          <button
            key={t.label}
            type="button"
            role="tab"
            className="tab"
            id={`${id}-tab-${i}`}
            aria-selected={i === active}
            aria-controls={`${id}-panel-${i}`}
            tabIndex={i === active ? 0 : -1}
            onClick={() => setActive(i)}
          >
            {t.label}
          </button>
        ))}
      </div>
      {tabs.map((t, i) => (
        <div key={t.label} role="tabpanel" className="tabpanel" id={`${id}-panel-${i}`} aria-labelledby={`${id}-tab-${i}`} hidden={i !== active}>
          {t.panel}
        </div>
      ))}
    </div>
  );
}
