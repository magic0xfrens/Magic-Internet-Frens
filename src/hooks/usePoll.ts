import { useEffect, useRef } from "react";

/**
 * Interval polling that stops while the tab is in the background.
 *
 * Why this exists: a browser tab left open is the protocol's single largest
 * source of request volume. Every panel on the brew page polls the indexer, and
 * a plain `setInterval` keeps firing at full rate whether or not anyone is
 * looking — so one forgotten background tab costs exactly as much as an engaged
 * user, all day. Most open-tab time is background time, so gating on visibility
 * removes the majority of that traffic for no loss of interactivity.
 *
 * Behaviour:
 * - Runs `fn` immediately on mount (when visible), then every `intervalMs`.
 * - On `hidden`, the timer is cleared entirely — not merely skipped — so a
 *   backgrounded tab issues zero requests.
 * - On becoming visible again it fires **once immediately**, then resumes. That
 *   is what keeps the UI honest: returning to the tab shows fresh data rather
 *   than whatever was on screen when you left, without needing a faster interval.
 * - `fn` is held in a ref, so a caller passing an inline arrow does not restart
 *   the timer on every render.
 *
 * @param fn         work to run; async is fine, rejections are the caller's problem
 * @param intervalMs polling period; `null` disables polling entirely
 * @param enabled    set false to stop (e.g. before a generation is live)
 */
export function usePoll(
  fn: () => void | Promise<void>,
  intervalMs: number | null,
  enabled = true,
): void {
  const saved = useRef(fn);
  saved.current = fn;

  useEffect(() => {
    if (!enabled || intervalMs == null) return;

    let timer: ReturnType<typeof setInterval> | null = null;
    const run = () => { void saved.current(); };

    const start = () => {
      if (timer != null) return;
      run();                                   // fire now, then on the interval
      timer = setInterval(run, intervalMs);
    };
    const stop = () => {
      if (timer == null) return;
      clearInterval(timer);
      timer = null;
    };

    const onVisibility = () => (document.hidden ? stop() : start());

    if (!document.hidden) start();
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      stop();
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [intervalMs, enabled]);
}
