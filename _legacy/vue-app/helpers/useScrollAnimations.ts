import { onUnmounted } from "vue";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

gsap.registerPlugin(ScrollTrigger);

export function useScrollAnimations() {
  const triggers: ScrollTrigger[] = [];
  const tweens: gsap.core.Tween[] = [];
  const timelines: gsap.core.Timeline[] = [];

  function animateOnScroll(
    selector: string | Element,
    from: gsap.TweenVars,
    to: gsap.TweenVars
  ) {
    const tween = gsap.fromTo(selector, from, {
      ...to,
      scrollTrigger: {
        trigger: selector as gsap.DOMTarget,
        start: "top 85%",
        once: true,
      },
    });
    tweens.push(tween);
    if (tween.scrollTrigger) triggers.push(tween.scrollTrigger);
    return tween;
  }

  function staggerOnScroll(
    selector: string,
    from: gsap.TweenVars,
    to: gsap.TweenVars,
    stagger = 0.15
  ) {
    const tween = gsap.fromTo(selector, from, {
      ...to,
      stagger,
      scrollTrigger: {
        trigger: selector,
        start: "top 85%",
        once: true,
      },
    });
    tweens.push(tween);
    if (tween.scrollTrigger) triggers.push(tween.scrollTrigger);
    return tween;
  }

  function createTimeline(trigger: string | Element) {
    const tl = gsap.timeline({
      scrollTrigger: {
        trigger: trigger as gsap.DOMTarget,
        start: "top 80%",
        once: true,
      },
    });
    timelines.push(tl);
    if (tl.scrollTrigger) triggers.push(tl.scrollTrigger);
    return tl;
  }

  onUnmounted(() => {
    tweens.forEach((t) => t.kill());
    timelines.forEach((t) => t.kill());
    triggers.forEach((t) => t.kill());
  });

  return { animateOnScroll, staggerOnScroll, createTimeline };
}
