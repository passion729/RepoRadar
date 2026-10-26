import { fill, type Content } from "@/lib/content";
import { latestRelease } from "@/lib/release";
import ActionsDemo from "./ActionsDemo";
import CopyButton from "./CopyButton";
import { DownloadIcon, GitHubMark, RadarMark } from "./Icons";
import InboxDemo from "./InboxDemo";
import KeyboardGrid from "./KeyboardGrid";
import MenuBarDemo from "./MenuBarDemo";
import NowDemo from "./NowDemo";
import ReadinessDemo from "./ReadinessDemo";
import RunningNow from "./RunningNow";
import Tabs from "./Tabs";

const GITHUB = "https://github.com/passion729/RepoRadar";
const PILLAR_TONES = ["purple", "blue", "red"];

const HEALTH = [
  ["RepoRadar", "sssfssssff"],
  ["api-gateway", "ssssssssss"],
  ["web", "sfsssssssf"],
  ["glasskit", "sssssssssr"],
];

const BUILD = ["git clone https://github.com/passion729/RepoRadar.git", "cd RepoRadar", "./build.sh", "open RepoRadar.app"];
const UNQUARANTINE = ["xattr -dr com.apple.quarantine /Applications/RepoRadar.app"];

const MARKUP = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\])/;

/** `**bold**`, `` `code` `` and `[key]` keycaps inside a content string. */
function rich(text: string) {
  return text.split(MARKUP).map((part, i) => {
    if (i % 2 === 0) return part;
    if (part.startsWith("**")) return <b key={i}>{part.slice(2, -2)}</b>;
    if (part.startsWith("`")) return <code key={i} className="mono">{part.slice(1, -1)}</code>;
    return <kbd key={i} className="kbd">{part.slice(1, -1)}</kbd>;
  });
}

function Terminal({ lines, c }: { lines: string[]; c: Content["start"] }) {
  return (
    <div className="terminal">
      <CopyButton text={lines.join("\n")} copy={c.copy} copied={c.copied} label={c.copyLabel} />
      <div className="mono terminal-lines">
        {lines.map((line) => (
          <div key={line}>
            <span className="prompt">$ </span>
            {line}
          </div>
        ))}
      </div>
    </div>
  );
}

function Inspector() {
  return (
    <>
      <span className="insp-h">Running now</span>
      <RunningNow />
      <span className="insp-h">Repository health</span>
      {HEALTH.map(([name, cells]) => (
        <div key={name} className="health">
          <span className="health-name">{name}</span>
          <span className="health-cells" aria-label={`${name}: last 10 runs`}>
            {[...cells].map((cell, i) => (
              <span key={i} className={`cell k-${cell}`} />
            ))}
          </span>
        </div>
      ))}
    </>
  );
}

export default function Landing({ c }: { c: Content }) {
  const release = latestRelease();
  const home = c.nav.otherHref === "/" ? "/zh/" : "/";

  return (
    <>
      <header className="nav-bar">
        <nav className="wrap nav" aria-label="Main">
          <a className="brand" href={home}>
            <span className="brand-mark">
              <RadarMark />
            </span>
            RepoRadar
          </a>
          <div className="nav-links">
            <a className="navl" href="#features">
              {c.nav.features}
            </a>
            <a className="navl" href="#keyboard">
              {c.nav.keyboard}
            </a>
            <a className="navl" href="#trust">
              {c.nav.privacy}
            </a>
            <a className="navl" href="#start">
              {c.nav.start}
            </a>
            <a className="navl lang" href={c.nav.otherHref} hrefLang={c.nav.otherLang} lang={c.nav.otherLang}>
              {c.nav.other}
            </a>
            <a className="cta2 cta-sm" href={GITHUB}>
              <GitHubMark />
              {c.nav.github}
            </a>
          </div>
        </nav>
      </header>

      <main>
        <section id="top" className="hero">
          <div className="wrap hero-copy">
            <span className="eyebrow">{c.hero.eyebrow}</span>
            <h1 className="disp hero-title">{c.hero.title}</h1>
            <p className="lead center">{c.hero.lede}</p>
            <div className="cta-row">
              <a className="cta" href={release.url}>
                <DownloadIcon />
                {c.hero.download}
              </a>
              <a className="cta2" href="#features">
                {c.hero.see}
              </a>
            </div>
            <span className="muted small">{fill(c.hero.meta, release)}</span>
          </div>

          <div className="wrap hero-mock">
            <NowDemo label={c.hero.demoLabel} inspector={<Inspector />} />
            <p className="demo-hint">
              <span className="hint-keys">{rich(c.hero.hintKeys)}</span>
              <span className="hint-touch">{c.hero.hintTouch}</span>
              {c.hero.demoNote ? <span className="demo-note">{c.hero.demoNote}</span> : null}
            </p>
          </div>
        </section>

        <section id="features" className="wrap pillars">
          <div className="grid-3">
            {c.pillars.map((p, i) => (
              <div key={p.title} className="panel pillar reveal">
                <span className={`eyebrow t-${PILLAR_TONES[i]}`}>{p.eyebrow}</span>
                <h3 className="disp">{p.title}</h3>
                <p className="muted">{p.body}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="wrap section">
          <div className="feat">
            <div className="copy reveal">
              <span className="eyebrow">{c.pulls.eyebrow}</span>
              <h2 className="disp h2">{c.pulls.title}</h2>
              <p className="lead">{c.pulls.lede}</p>
            </div>
            <div className="vis reveal">
              <ReadinessDemo />
            </div>
          </div>
        </section>

        <section className="wrap section">
          <div className="feat reverse">
            <div className="copy reveal">
              <span className="eyebrow t-red">{c.actions.eyebrow}</span>
              <h2 className="disp h2">{c.actions.title}</h2>
              <p className="lead">{c.actions.lede}</p>
            </div>
            <div className="vis reveal">
              <ActionsDemo />
            </div>
          </div>
        </section>

        <section className="wrap section">
          <div className="grid-2">
            <div className="panel tile reveal">
              <span className="eyebrow t-purple">{c.inbox.eyebrow}</span>
              <h3 className="disp">{c.inbox.title}</h3>
              <p className="muted">{c.inbox.body}</p>
              <InboxDemo />
            </div>
            <div className="panel tile reveal">
              <span className="eyebrow t-green">{c.menu.eyebrow}</span>
              <h3 className="disp">{c.menu.title}</h3>
              <p className="muted">{c.menu.body}</p>
              <MenuBarDemo />
            </div>
          </div>
        </section>

        <section id="keyboard" className="wrap section keys-section">
          <span className="eyebrow">{c.keys.eyebrow}</span>
          <h2 className="disp h2 narrow">{c.keys.title}</h2>
          <p className="lead center">
            {c.keys.lede}
            <span className="hint-keys">{c.keys.press}</span>
          </p>
          <KeyboardGrid labels={c.keys.labels} />
        </section>

        <section id="trust" className="wrap section">
          <div className="panel trust reveal">
            <div className="trust-head">
              <span className="eyebrow">{c.trust.eyebrow}</span>
              <h2 className="disp">{c.trust.title}</h2>
            </div>
            <div className="trust-grid">
              {c.trust.items.map(([title, body]) => (
                <div key={title}>
                  <b>{title}</b>
                  <span className="muted">{body}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section id="start" className="wrap start">
          <h2 className="disp h2 narrow">{c.start.title}</h2>
          <p className="lead center">{c.start.lede}</p>
          <Tabs
            label={c.start.tabsLabel}
            tabs={[
              {
                label: c.start.downloadTab,
                panel: (
                  <div className="dl">
                    <a className="cta" href={release.url}>
                      <DownloadIcon />
                      {fill(c.start.downloadButton, release)}
                    </a>
                    <span className="muted small">{fill(c.start.downloadMeta, release)}</span>
                    <p className="note">{rich(c.start.gatekeeper)}</p>
                    <Terminal lines={UNQUARANTINE} c={c.start} />
                    <p className="note">{c.start.after}</p>
                  </div>
                ),
              },
              {
                label: c.start.buildTab,
                panel: (
                  <>
                    <p className="note">{c.start.buildNote}</p>
                    <Terminal lines={BUILD} c={c.start} />
                  </>
                ),
              },
            ]}
          />
          <a className="cta2" href={GITHUB}>
            <GitHubMark />
            {c.start.github}
          </a>
        </section>
      </main>

      <footer className="wrap footer">
        <span className="footer-brand">RepoRadar</span>
        <span>{fill(c.footer.tagline, release)}</span>
        <span className="footer-links">
          <a className="navl" href={GITHUB}>
            {c.nav.github}
          </a>
          <a className="navl" href={`${GITHUB}/releases`}>
            {c.footer.releases}
          </a>
          <a className="navl" href="#features">
            {c.nav.features}
          </a>
          <a className="navl" href="#start">
            {c.nav.start}
          </a>
          <a className="navl" href={c.nav.otherHref} hrefLang={c.nav.otherLang} lang={c.nav.otherLang}>
            {c.nav.other}
          </a>
        </span>
      </footer>
    </>
  );
}
