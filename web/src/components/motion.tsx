"use client";

import { LazyMotion, domAnimation, m, MotionConfig, useReducedMotion } from "motion/react";
import type { ReactNode } from "react";

export function MotionProvider({ children }: { children: ReactNode }) {
  return <LazyMotion features={domAnimation}><MotionConfig reducedMotion="user">{children}</MotionConfig></LazyMotion>;
}

// Content is server-rendered visibly. Only the mounted, in-view element animates.
export function Reveal({ children, className = "", delay = 0 }: {
  children: ReactNode; className?: string; delay?: number;
}) {
  const reduced = useReducedMotion();
  return (
    <m.div className={className} initial={false} whileInView={reduced ? { opacity: 1, y: 0 } : { opacity: [0.8, 1], y: [12, 0] }} viewport={{ once: true, amount: 0.12 }} transition={{ duration: reduced ? 0 : 0.42, delay: reduced ? 0 : Math.min(delay, 0.12), ease: [0.22, 1, 0.36, 1] }}>
      {children}
    </m.div>
  );
}

export function HeroEntrance({ children, className = "", delay = 0, mockup = false }: { children: ReactNode; className?: string; delay?: number; mockup?: boolean }) {
  const reduced = useReducedMotion();
  return <m.div initial={false} animate={reduced ? { opacity: 1, y: 0, scale: 1 } : { opacity: [0.85, 1], y: [mockup ? 18 : 12, 0], scale: [mockup ? 0.985 : 1, 1] }} transition={{ duration: reduced ? 0 : 0.55, delay: reduced ? 0 : delay, ease: [0.22, 1, 0.36, 1] }} className={className}>{children}</m.div>;
}

export function WorkflowConnector() {
  const reduced = useReducedMotion();
  // CSS selects scaleX or scaleY at the layout breakpoint; the progress is shared.
  return <m.span aria-hidden="true" className="workflow-connector" initial={false} whileInView={{ "--connector-progress": reduced ? 1 : [0, 1] }} viewport={{ once: true }} transition={{ duration: reduced ? 0 : 0.5, delay: reduced ? 0 : 0.08 }} />;
}
