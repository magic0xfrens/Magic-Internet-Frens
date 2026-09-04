import { useMemo, useState, useEffect, useRef, useCallback } from "react";
import { marked } from "marked";
import DOMPurify from "dompurify";
import { Menu, ScrollText, X } from "lucide-react";
// Raw markdown is the single source of truth. The same file is copied to
// /public/magicfrens-llm.md and /public/llms-full.txt at build so assistants can
// fetch it directly; here we render it into the DOM so crawlers see full text.
import rawDoc from "./magicfrens-llm.md?raw";
import { FrenHelper } from "./FrenHelper";
import LiveDeployment from "./LiveDeployment";

interface TocItem {
  id: string;
  text: string;
  level: number;
}

/** Slugify a heading into a stable anchor id (matches marked's default-ish ids). */
function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}

/** Strip the leading "N." / "N.N" numbering so TOC entries read cleanly. */
function stripNumber(text: string): string {
  return text.replace(/^\d+(\.\d+)*\.?\s+/, "");
}

export default function Docs() {
  // Parse the markdown ONCE. We post-process to (a) inject heading ids for the
  // TOC + deep-linking and (b) sanitize before it ever touches innerHTML.
  const { html, toc } = useMemo(() => {
    marked.setOptions({ gfm: true, breaks: false });
    const rawHtml = marked.parse(rawDoc) as string;

    const toc: TocItem[] = [];
    const seen = new Map<string, number>();
    const withIds = rawHtml.replace(
      /<h([1-3])>(.*?)<\/h\1>/g,
      (_m, lvl: string, inner: string) => {
        const text = inner.replace(/<[^>]+>/g, "");
        // De-duplicate ids: two sections may legitimately share a heading, and a
        // duplicate id silently breaks both deep-linking and the scroll-spy.
        const base = slugify(text);
        const n = seen.get(base) ?? 0;
        seen.set(base, n + 1);
        const id = n === 0 ? base : `${base}-${n}`;
        if (Number(lvl) <= 2) toc.push({ id, text: stripNumber(text), level: Number(lvl) });
        return `<h${lvl} id="${id}"><a class="docs__anchor" href="#${id}" aria-label="Link to this section">#</a>${inner}</h${lvl}>`;
      },
    );

    const clean = DOMPurify.sanitize(withIds, {
      ADD_ATTR: ["id", "target", "rel", "class", "aria-label"],
    });
    return { html: clean, toc };
  }, []);

  const [active, setActive] = useState<string>("");
  const [query, setQuery] = useState("");
  const [progress, setProgress] = useState(0);
  const [tocOpen, setTocOpen] = useState(false);
  const bodyRef = useRef<HTMLElement | null>(null);

  // Scroll-spy: highlight the TOC entry for the section currently in view.
  useEffect(() => {
    const headings = Array.from(
      document.querySelectorAll<HTMLElement>(".docs__body h1[id], .docs__body h2[id]"),
    );
    if (!headings.length) return;
    const obs = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        if (visible[0]) setActive(visible[0].target.id);
      },
      { rootMargin: "-64px 0px -70% 0px", threshold: 0 },
    );
    headings.forEach((h) => obs.observe(h));
    return () => obs.disconnect();
  }, [html]);

  // Reading-progress bar. Throttled to animation frames so scrolling stays smooth.
  useEffect(() => {
    let raf = 0;
    const onScroll = () => {
      if (raf) return;
      raf = window.requestAnimationFrame(() => {
        raf = 0;
        const el = bodyRef.current;
        if (!el) return;
        const start = el.offsetTop;
        const span = el.offsetHeight - window.innerHeight;
        if (span <= 0) return setProgress(0);
        const p = (window.scrollY - start) / span;
        setProgress(Math.max(0, Math.min(1, p)));
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (raf) window.cancelAnimationFrame(raf);
    };
  }, [html]);

  useEffect(() => {
    document.title = "Docs · Magic Internet Frens";
  }, []);

  // Deep-link on load: the docs live under a hash route, so `#section` can't be
  // used directly — we scroll manually once the body has rendered.
  useEffect(() => {
    const target = window.location.hash.split("#").filter(Boolean).pop();
    if (!target) return;
    const el = document.getElementById(target);
    if (el) window.setTimeout(() => el.scrollIntoView({ block: "start" }), 60);
  }, [html]);

  const goTo = useCallback((id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
    setTocOpen(false);
  }, []);

  // Filter the TOC as you type. Matching on the heading text alone keeps this
  // instant and predictable — it is a jump-to-section box, not a full-text search.
  const filteredToc = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return toc;
    return toc.filter((t) => t.text.toLowerCase().includes(q));
  }, [toc, query]);

  return (
    <div className="docs">
      {/* Reading progress */}
      <div className="docs__progress" aria-hidden="true">
        <div className="docs__progress-bar" style={{ transform: `scaleX(${progress})` }} />
      </div>

      {/* Hero / "Feed This To Your AI" */}
      <div className="docs__hero">
        <div className="docs__hero-inner">
          <div className="docs__eyebrow">
            <ScrollText size={14} strokeWidth={2} aria-hidden />
            THE GRIMOIRE
          </div>
          <h1 className="docs__title">Documentation</h1>
          <p className="docs__lede">
            Every mechanic, fee split, parameter, contract and known limitation
            behind Magic Internet Frens &amp; The Cauldron — the eternal on-chain
            token machine. Written against the source, not the roadmap: every
            number below is a constant you can find in the Solidity. Everything
            renders as plain HTML in the DOM, so assistants and crawlers read the
            full text, not a summary.
          </p>

          <div className="docs__stats">
            <div className="docs__stat">
              <span className="docs__stat-n">23</span>
              <span className="docs__stat-l">contracts</span>
            </div>
            <div className="docs__stat">
              <span className="docs__stat-n">~9.2k</span>
              <span className="docs__stat-l">lines of Solidity</span>
            </div>
            <div className="docs__stat">
              <span className="docs__stat-n">339</span>
              <span className="docs__stat-l">tests passing</span>
            </div>
            <div className="docs__stat">
              <span className="docs__stat-n">0</span>
              <span className="docs__stat-l">ways to touch your wallet</span>
            </div>
          </div>

          <div className="docs__ai-card">
            <div className="docs__ai-glow" />
            <div className="docs__ai-content">
              <div className="docs__ai-head">
                <span className="docs__ai-spark">✦</span>
                <h2>Feed This To Your AI</h2>
              </div>
              <p>
                The entire project in one self-contained markdown file — every
                mechanic, fee split, tier weight, parameter, lifecycle path and
                known limitation. Download it and hand it to ChatGPT, Claude, or
                whatever you use, then ask it anything about MiFrens.
              </p>
              <div className="docs__ai-actions">
                <a
                  className="docs__dl docs__dl--primary"
                  href="/magicfrens-llm.md"
                  download="magicfrens-llm.md"
                >
                  ⬇ Download magicfrens-llm.md
                </a>
                <a className="docs__dl" href="/llms.txt" target="_blank" rel="noreferrer">
                  /llms.txt
                </a>
                <a className="docs__dl" href="/llms-full.txt" target="_blank" rel="noreferrer">
                  /llms-full.txt
                </a>
              </div>
              <p className="docs__ai-note">
                Served at the standard <code>llms.txt</code> paths, so assistants
                that look for machine-readable docs will find them on their own.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Live addresses — read from the running config, never hard-coded. */}
      <LiveDeployment />

      {/* Mobile TOC toggle (the sidebar is hidden under 860px). */}
      <button
        type="button"
        className="docs__toc-toggle"
        onClick={() => setTocOpen((v) => !v)}
        aria-expanded={tocOpen}
      >
        {tocOpen ? <X size={14} strokeWidth={2} aria-hidden /> : <Menu size={14} strokeWidth={2} aria-hidden />}
        {tocOpen ? "Close contents" : "Contents"}
      </button>

      <div className="docs__layout">
        {/* Table of contents */}
        <aside
          className={`docs__toc${tocOpen ? " docs__toc--open" : ""}`}
          aria-label="Table of contents"
        >
          <div className="docs__toc-title">On this page</div>
          <input
            className="docs__toc-search"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Filter sections…"
            aria-label="Filter sections"
          />
          <nav>
            <a
              href="#live-deployment"
              onClick={(e) => {
                e.preventDefault();
                goTo("live-deployment");
              }}
              className="docs__toc-link docs__toc-link--l1"
            >
              Live deployment
            </a>
            {filteredToc.map((item) => (
              <a
                key={item.id}
                href={`#${item.id}`}
                onClick={(e) => {
                  e.preventDefault();
                  goTo(item.id);
                }}
                className={`docs__toc-link docs__toc-link--l${item.level}${
                  active === item.id ? " docs__toc-link--active" : ""
                }`}
              >
                {item.text}
              </a>
            ))}
            {filteredToc.length === 0 && (
              <span className="docs__toc-empty">No section matches “{query}”.</span>
            )}
          </nav>
        </aside>

        {/* Rendered markdown — full text in the DOM */}
        <article
          ref={bodyRef}
          className="docs__body"
          // eslint-disable-next-line react/no-danger -- sanitized above with DOMPurify
          dangerouslySetInnerHTML={{ __html: html }}
        />
      </div>

      {/* The cute magic-fren helper */}
      <FrenHelper />

      <style>{docsStyles}</style>
    </div>
  );
}

const docsStyles = `
  .docs {
    min-height: 100vh;
    background:
      radial-gradient(1200px 600px at 50% -10%, rgba(124,92,252,0.10), transparent 60%),
      #0E0A1A;
    color: #E7E1F5;
    padding-bottom: 120px;
  }

  /* Reading progress */
  /* Tracks the article, so it starts where the article does — running it under
     the rail would read as a page-wide loading bar instead of reading progress. */
  .docs__progress {
    position: fixed; top: 0; left: var(--rail-w); right: 0; height: 2px;
    background: rgba(213,253,81,0.08); z-index: var(--z-toast); pointer-events: none;
  }
  /* Matches the rail's own collapse breakpoint, not the TOC's. */
  @media (max-width: 960px) { .docs__progress { left: 0; } }
  .docs__progress-bar {
    height: 100%; background: linear-gradient(90deg, #7c5cfc, #d5fd51);
    transform-origin: 0 50%; will-change: transform;
  }

  /* The rail replaced the sticky header, so the hero no longer has to clear it
     and the shell owns the horizontal gutter. */
  .docs__hero {
    padding: 48px 0 40px;
    border-bottom: 1px solid rgba(213,253,81,0.08);
  }
  .docs__hero-inner { max-width: 1180px; margin: 0 auto; }

  .docs__eyebrow {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-family: "Fredoka", sans-serif;
    font-size: 12px;
    letter-spacing: 0.22em;
    color: var(--lime);
    margin-bottom: 12px;
  }
  .docs__title {
    font-family: "Cinzel Decorative", serif;
    font-size: clamp(38px, 6vw, 64px);
    line-height: 1.05;
    color: #FFFFFF;
    margin: 0 0 16px;
  }
  .docs__lede {
    max-width: 760px;
    font-family: "DM Sans", sans-serif;
    font-size: 16px;
    line-height: 1.7;
    color: rgba(231,225,245,0.72);
    margin: 0 0 28px;
  }

  /* At-a-glance numbers */
  .docs__stats {
    display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 32px;
  }
  .docs__stat {
    display: flex; flex-direction: column; gap: 2px;
    padding: 10px 18px; border-radius: var(--r-sm);
    border: 1px solid rgba(124,92,252,0.22);
    background: rgba(124,92,252,0.07);
  }
  .docs__stat-n {
    font-family: "Cinzel", serif; font-size: 20px; color: #d5fd51; line-height: 1;
  }
  .docs__stat-l {
    font-family: "DM Sans", sans-serif; font-size: 11.5px;
    color: rgba(231,225,245,0.55); letter-spacing: 0.02em;
  }

  /* Feed-to-AI card */
  .docs__ai-card {
    position: relative;
    max-width: 760px;
    border: 1px solid rgba(213,253,81,0.22);
    border-radius: var(--r-md);
    background: linear-gradient(160deg, rgba(124,92,252,0.14), rgba(14,10,26,0.6));
    overflow: hidden;
  }
  .docs__ai-glow {
    position: absolute; inset: -40% 60% auto -20%; height: 240px;
    background: radial-gradient(circle, rgba(213,253,81,0.22), transparent 70%);
    filter: blur(30px); pointer-events: none;
  }
  .docs__ai-content { position: relative; padding: 26px 28px; }
  .docs__ai-head { display: flex; align-items: center; gap: 12px; margin-bottom: 10px; }
  .docs__ai-spark {
    display: grid; place-items: center;
    width: 34px; height: 34px; border-radius: var(--r-sm);
    background: #d5fd51; color: #0E0A1A; font-size: 18px;
    box-shadow: 0 0 22px rgba(213,253,81,0.5);
  }
  .docs__ai-head h2 {
    font-family: "Cinzel", serif; font-size: 22px; color: #FFFFFF; margin: 0;
  }
  .docs__ai-content > p {
    font-family: "DM Sans", sans-serif; font-size: 14px; line-height: 1.65;
    color: rgba(231,225,245,0.72); margin: 0 0 18px;
  }
  .docs__ai-actions { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 14px; }
  .docs__dl {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 10px 16px; border-radius: var(--r-md);
    border: 1px solid rgba(213,253,81,0.28);
    background: rgba(213,253,81,0.06);
    color: #d5fd51;
    font-family: "Fredoka", sans-serif; font-size: 13px; font-weight: 600;
    letter-spacing: 0.03em; transition: transform .2s ease, background .2s ease;
  }
  .docs__dl:hover { transform: translateY(-1px); background: rgba(213,253,81,0.14); }
  .docs__dl--primary {
    background: #d5fd51; color: #0E0A1A; border-color: #d5fd51;
    box-shadow: 0 6px 20px rgba(213,253,81,0.35);
  }
  .docs__dl--primary:hover { background: #e4ff7a; }
  .docs__ai-note {
    font-family: "DM Sans", sans-serif; font-size: 12.5px;
    color: rgba(231,225,245,0.5); margin: 0;
  }
  .docs__ai-note code {
    font-family: ui-monospace, monospace; color: #d5fd51;
    background: rgba(213,253,81,0.08); padding: 1px 6px; border-radius: var(--r-chip);
  }

  /* Layout */
  /* The app shell already provides a left rail, so the TOC lives on the RIGHT
     — two stacked left sidebars would read as a mistake. DOM order is unchanged
     (nav still precedes the article for screen readers); only the grid
     placement moves it. */
  .docs__layout {
    max-width: 1180px; margin: 0 auto; padding: 40px 0;
    display: grid; grid-template-columns: minmax(0, 1fr) 220px; gap: 48px;
    align-items: start;
  }

  .docs__toc-toggle { display: none; }

  .docs__toc {
    grid-column: 2; grid-row: 1;
    position: sticky; top: 24px; align-self: start;
    max-height: calc(100vh - 48px); overflow-y: auto;
  }
  .docs__toc-title {
    font-family: "Fredoka", sans-serif; font-size: 11px; letter-spacing: 0.16em;
    text-transform: uppercase; color: #8A7BAA; margin-bottom: 10px;
  }
  .docs__toc-search {
    width: 100%; box-sizing: border-box; margin-bottom: 12px;
    padding: 7px 10px; border-radius: var(--r-sm);
    border: 1px solid rgba(124,92,252,0.25);
    background: rgba(124,92,252,0.07); color: #E7E1F5;
    font-family: "DM Sans", sans-serif; font-size: 12.5px;
  }
  .docs__toc-search::placeholder { color: rgba(231,225,245,0.35); }
  .docs__toc-search:focus {
    outline: none; border-color: rgba(213,253,81,0.4);
    background: rgba(213,253,81,0.05);
  }
  .docs__toc nav { display: flex; flex-direction: column; gap: 2px; }
  .docs__toc-link {
    font-family: "DM Sans", sans-serif; font-size: 13px; line-height: 1.35;
    color: rgba(231,225,245,0.55); text-decoration: none;
    padding: 5px 12px; border-left: 2px solid transparent; cursor: pointer;
    transition: color .15s ease, border-color .15s ease;
  }
  .docs__toc-link--l2 { padding-left: 22px; font-size: 12.5px; }
  .docs__toc-link:hover { color: #E7E1F5; }
  .docs__toc-link--active {
    color: #d5fd51; border-left-color: #d5fd51;
  }
  .docs__toc-empty {
    font-family: "DM Sans", sans-serif; font-size: 12.5px;
    color: rgba(231,225,245,0.4); padding: 6px 12px;
  }

  /* Body typography */
  .docs__body { grid-column: 1; grid-row: 1; min-width: 0; font-family: "DM Sans", sans-serif; }
  .docs__body h1, .docs__body h2, .docs__body h3 {
    font-family: "Cinzel", serif; color: #FFFFFF; scroll-margin-top: 76px;
    position: relative;
  }
  .docs__body h1 {
    font-size: 30px; margin: 48px 0 16px; padding-bottom: 10px;
    border-bottom: 1px solid rgba(213,253,81,0.14);
  }
  .docs__body h1:first-child { margin-top: 0; }
  .docs__body h2 { font-size: 22px; margin: 40px 0 14px; color: #E9E3FB; }
  .docs__body h3 { font-size: 17px; margin: 28px 0 10px; color: #d5fd51; font-family: "Fredoka", sans-serif; }

  /* Hover-revealed anchor link on every heading. */
  .docs__anchor {
    position: absolute; left: -0.85em; top: 0;
    color: rgba(213,253,81,0.45); text-decoration: none;
    opacity: 0; transition: opacity .15s ease; font-weight: 400;
  }
  .docs__body h1:hover .docs__anchor,
  .docs__body h2:hover .docs__anchor,
  .docs__body h3:hover .docs__anchor,
  .docs__anchor:focus { opacity: 1; }

  .docs__body p, .docs__body li {
    font-size: 15px; line-height: 1.75; color: rgba(231,225,245,0.82);
  }
  .docs__body ul, .docs__body ol { padding-left: 22px; margin: 12px 0; }
  .docs__body li { margin: 6px 0; }
  .docs__body a { color: #d5fd51; text-decoration: underline; text-underline-offset: 3px; }
  .docs__body strong { color: #FFFFFF; }
  .docs__body code {
    font-family: ui-monospace, "SF Mono", monospace; font-size: 13px;
    background: rgba(124,92,252,0.16); color: #c9b8ff;
    padding: 1.5px 6px; border-radius: var(--r-chip); word-break: break-word;
  }
  .docs__body pre {
    background: rgba(0,0,0,0.35); border: 1px solid rgba(124,92,252,0.18);
    border-radius: var(--r-sm); padding: 16px; overflow-x: auto; margin: 16px 0;
  }
  .docs__body pre code { background: none; color: #E7E1F5; padding: 0; }
  .docs__body blockquote {
    margin: 18px 0; padding: 12px 18px;
    border-left: 3px solid #d5fd51; border-radius: 0 var(--r-sm) var(--r-sm) 0;
    background: rgba(213,253,81,0.05);
  }
  .docs__body blockquote p { color: rgba(231,225,245,0.9); margin: 4px 0; }
  .docs__body hr { border: none; border-top: 1px solid rgba(124,92,252,0.14); margin: 40px 0; }

  /* Tables */
  .docs__body table {
    width: 100%; border-collapse: collapse; margin: 18px 0; font-size: 13.5px;
    display: block; overflow-x: auto;
  }
  .docs__body th, .docs__body td {
    border: 1px solid rgba(124,92,252,0.16); padding: 9px 12px; text-align: left;
    vertical-align: top;
  }
  .docs__body th {
    background: rgba(124,92,252,0.14); color: #E9E3FB;
    font-family: "Fredoka", sans-serif; font-weight: 600; white-space: nowrap;
  }
  .docs__body td code { font-size: 12px; }
  .docs__body tr:nth-child(even) td { background: rgba(124,92,252,0.04); }

  @media (max-width: 860px) {
    .docs__layout { grid-template-columns: 1fr; gap: 16px; padding-top: 8px; }
    .docs__hero { padding-top: 32px; }
    .docs__stats { gap: 8px; }
    .docs__stat { padding: 8px 14px; }

    /* TOC becomes a collapsible panel instead of vanishing entirely. */
    .docs__toc-toggle {
      display: inline-flex; align-items: center; gap: 8px;
      margin: 20px auto 0; padding: 9px 18px;
      border-radius: var(--r-md); cursor: pointer;
      border: 1px solid rgba(213,253,81,0.28);
      background: rgba(213,253,81,0.07); color: #d5fd51;
      font-family: "Fredoka", sans-serif; font-size: 13px; font-weight: 600;
    }
    /* Single column: both children collapse onto row-independent auto flow. */
    .docs__toc, .docs__body { grid-column: 1; grid-row: auto; }
    .docs__toc { display: none; position: static; max-height: none; }
    .docs__toc--open {
      display: block; padding: 16px;
      border: 1px solid rgba(124,92,252,0.2); border-radius: var(--r-sm);
      background: rgba(124,92,252,0.06);
    }
    .docs__anchor { display: none; }
  }

  @media (prefers-reduced-motion: reduce) {
    .docs__dl:hover { transform: none; }
    .docs__progress-bar { transition: none; }
  }
`;
