"use client";

import { useEffect, useRef, useState } from "react";

type Phase = "failed" | "running" | "passed";

const RERUN_MS = 2600;

const NODE = {
  failed: { test: ["failed", "st-f"], pkg: ["skipped", "st-k"] },
  running: { test: ["running", "st-r"], pkg: ["skipped", "st-k"] },
  passed: { test: ["", "st-s"], pkg: ["", "st-s"] },
} as const;

/** A failed run: re-running the failed job takes it through running to green. */
export default function ActionsDemo() {
  const [phase, setPhase] = useState<Phase>("failed");
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => () => clearTimeout(timer.current), []);

  function rerun() {
    setPhase("running");
    timer.current = setTimeout(() => setPhase("passed"), RERUN_MS);
  }

  function reset() {
    clearTimeout(timer.current);
    setPhase("failed");
  }

  const [testClass, testSt] = NODE[phase].test;
  const [pkgClass, pkgSt] = NODE[phase].pkg;

  return (
    <div className="glass card">
      <div className="graph">
        <span className="node">
          <span className="st st-s" />
          build
        </span>
        <span className="muted">→</span>
        <span className={`node ${testClass}`}>
          <span className={`st ${testSt}`} />
          test (macos-26)
        </span>
        <span className="muted">→</span>
        <span className={`node ${pkgClass}`}>
          <span className={`st ${pkgSt}`} />
          package
        </span>
      </div>

      <div className="tags" aria-live="polite">
        {phase === "failed" ? (
          <>
            <span className="chip c-red">testNestedListIndent :88</span>
            <span className="chip c-plain">testTableAlignment :142</span>
            <span className="chip c-plain">testAutolinkTrailingDot :61</span>
          </>
        ) : phase === "running" ? (
          <span className="chip c-amber">Re-running 1 failed job · attempt 2</span>
        ) : (
          <span className="chip c-green">All jobs passed on attempt 2</span>
        )}
      </div>

      <div className="mono log">
        {phase === "failed" ? (
          <>
            <div className="log-dim">▾ Run swift test · 1,906 lines</div>
            <div className="log-fold">┄ 1,688 passing lines folded</div>
            <div className="log-ok">1703  ✓ testFencedCode</div>
            <div className="log-bad">1704  ✕ testNestedListIndent</div>
            <div className="log-err">1705    XCTAssertEqual failed: (&quot;4&quot;) is not equal to (&quot;2&quot;)</div>
          </>
        ) : phase === "running" ? (
          <>
            <div className="log-dim">▾ Run swift test · attempt 2</div>
            <div>Building for debugging...</div>
            <div>[412/418] Compiling RepoRadar Markdown.swift</div>
            <div className="caret">Test Suite &apos;All tests&apos; started</div>
          </>
        ) : (
          <>
            <div className="log-dim">▾ Run swift test · attempt 2</div>
            <div className="log-ok">✓ testNestedListIndent</div>
            <div className="log-ok">✓ testTableAlignment</div>
            <div className="log-ok">✓ Test Suite &apos;All tests&apos; passed</div>
          </>
        )}
      </div>

      <div className="btn-row">
        {phase === "failed" ? (
          <>
            <button type="button" className="mbtn pri" onClick={rerun}>
              Re-run failed jobs<kbd className="kbd kbd-on">⇧⌘R</kbd>
            </button>
            <button type="button" className="mbtn" onClick={rerun}>
              Re-run all
            </button>
          </>
        ) : phase === "running" ? (
          <button type="button" className="mbtn" onClick={reset}>
            Cancel<kbd className="kbd">⌘.</kbd>
          </button>
        ) : (
          <button type="button" className="mbtn" onClick={reset}>
            Reset demo
          </button>
        )}
      </div>
    </div>
  );
}
