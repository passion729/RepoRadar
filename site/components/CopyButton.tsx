"use client";

import { useState } from "react";

export default function CopyButton({ text, copy: copyText, copied: copiedText, label }: { text: string; copy: string; copied: string; label: string }) {
  const [copied, setCopied] = useState(false);

  function copy() {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    });
  }

  return (
    <button type="button" className="copy-btn" onClick={copy} aria-label={copied ? copiedText : label}>
      {copied ? copiedText : copyText}
    </button>
  );
}
