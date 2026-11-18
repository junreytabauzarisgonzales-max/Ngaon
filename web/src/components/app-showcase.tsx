"use client";

import Image from "next/image";
import { useRef, useState, type ReactNode } from "react";
import { AnimatePresence, m, useIsPresent, useReducedMotion } from "motion/react";
import { ArrowLeft, ArrowRight, ArrowUpRight, Layers } from "lucide-react";
import { appScreens, applications, type AppRole } from "@/content/site-content";
import { appIconSources } from "./app-icons";

function PreviewSlide({ children, label, direction }: {
  children: ReactNode; label: string; direction: number;
}) {
  const present = useIsPresent();
  const reduced = useReducedMotion();

  return (
    <m.div
      className="showcase-slide"
      role="group"
      aria-roledescription="slide"
      aria-label={label}
      aria-hidden={!present}
      initial={{ opacity: 0, x: reduced ? 0 : direction * 10 }}
      animate={{ opacity: 1, x: 0 }}
      variants={{ exit: (exitDirection: number) => ({ opacity: 0, x: reduced ? 0 : exitDirection * -8 }) }}
      exit="exit"
      transition={{ duration: reduced ? 0 : 0.24, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </m.div>
  );
}

export function AppShowcase({ previews }: { previews: Record<string, ReactNode> }) {
  const [index, setIndex] = useState(0);
  const [direction, setDirection] = useState(1);
  const [role, setRole] = useState<AppRole | null>(null);
  const reduced = useReducedMotion();
  const swipeStart = useRef<{ x: number; y: number; pointer: number } | null>(null);
  const screens = role ? appScreens.filter((screen) => screen.role === role) : appScreens;
  const screen = screens[index % screens.length];
  const application = applications.find((app) => app.id === screen.role)!;

  function changeScreen(delta: number) {
    setDirection(delta > 0 ? 1 : -1);
    setIndex((current) => (current + delta + screens.length) % screens.length);
  }

  function selectRole(nextRole: AppRole | null) {
    setRole(nextRole);
    setDirection(1);
    setIndex(0);
  }

  return <div className="showcase-interactive" role="region" aria-roledescription="carousel" aria-label="Ngaon application previews" onKeyDown={(event) => {
    if (event.target instanceof HTMLElement && event.target.closest(".role-tabs")) return;
    if (event.key === "ArrowRight") { event.preventDefault(); changeScreen(1); }
    if (event.key === "ArrowLeft") { event.preventDefault(); changeScreen(-1); }
  }}>
    <div className="showcase-stage" id="showcase-viewport" role="group" tabIndex={0} aria-label="App preview. Use left and right arrow keys to browse.">
      <div className="showcase-ring" aria-hidden="true" /><span className="showcase-corner-label"><Layers size={13} aria-hidden="true" />{screen.image ? "ACTUAL APP SCREEN" : "ILLUSTRATIVE APP CONCEPT"}</span>
      <div className="showcase-draggable" onDragStart={(event) => event.preventDefault()} onPointerDown={(event) => {
        if (event.button !== 0 || !event.isPrimary) return;
        swipeStart.current = { x: event.clientX, y: event.clientY, pointer: event.pointerId };
        event.currentTarget.setPointerCapture(event.pointerId);
      }} onPointerCancel={() => { swipeStart.current = null; }} onPointerUp={(event) => {
        const start = swipeStart.current;
        swipeStart.current = null;
        if (!start || start.pointer !== event.pointerId) return;
        const dx = event.clientX - start.x;
        const dy = event.clientY - start.y;
        if (Math.abs(dx) > 45 && Math.abs(dx) > Math.abs(dy) * 1.5) changeScreen(dx < 0 ? 1 : -1);
      }}>
        <AnimatePresence initial={false} custom={direction}>
          <PreviewSlide key={screen.id} direction={direction} label={`${index + 1} of ${screens.length}: ${application.name} — ${screen.title}`}>
            {previews[screen.id]}
          </PreviewSlide>
        </AnimatePresence>
      </div>
      <span className="showcase-stage-caption">A closer look at your everyday.</span>
    </div>
    <div className="showcase-description">
      <div className="role-tabs" role="group" aria-label="Filter previews by application">
        {applications.map((app) => {
          const count = appScreens.filter((item) => item.role === app.id).length;
          return <button type="button" key={app.id} aria-pressed={role === app.id} aria-label={`Show ${app.name} previews, ${count} screens`} onClick={() => selectRole(app.id)}>{app.shortName}<span className="role-count" aria-hidden="true">{String(count).padStart(2, "0")}</span></button>;
        })}
        <button type="button" aria-pressed={role === null} aria-label={`Show all previews, ${appScreens.length} screens`} onClick={() => selectRole(null)}>All<span className="role-count" aria-hidden="true">{String(appScreens.length).padStart(2, "0")}</span></button>
      </div>
      <div className="showcase-app-label"><Image src={appIconSources[application.id]} width={28} height={28} alt="" /><span>{application.name}</span><span className="small-tag">{screen.image ? "App screenshot" : "Illustration"}</span></div>
      <p className="screen-counter" aria-hidden="true">{String(index + 1).padStart(2, "0")} <span>/ {String(screens.length).padStart(2, "0")}</span></p>
      <div className="showcase-live-copy">
        {/* Reserve exactly the tallest caption at each width, without a fixed-height gap. */}
        <div className="showcase-copy-sizer" aria-hidden="true">
          {screens.map((item) => <div key={item.id}><span className="showcase-copy-title">{item.title}</span><span className="showcase-copy-description">{item.description}</span></div>)}
        </div>
        <div className="showcase-caption" aria-live="polite" aria-atomic="true">
          <m.div key={screen.id} initial={false} animate={reduced ? { opacity: 1, y: 0 } : { opacity: [0.85, 1], y: [4, 0] }} transition={{ duration: reduced ? 0 : 0.24 }}>
          <span className="sr-only">{application.name}, preview {index + 1} of {screens.length}. </span>
          <h3>{screen.title}</h3><p>{screen.description}</p>
          </m.div>
        </div>
      </div>
      <div className="showcase-controls">
        <button className="icon-button carousel-previous" type="button" aria-label="Previous app preview" aria-controls="showcase-viewport" onClick={() => changeScreen(-1)}><ArrowLeft size={20} aria-hidden="true" /></button>
        <span className="carousel-hint" aria-hidden="true">Swipe to explore</span>
        <div className="carousel-dots" role="group" aria-label="Choose app preview">
          {screens.map((item, i) => <button type="button" key={item.id} aria-label={`Show ${item.title} (${i + 1} of ${screens.length})`} aria-controls="showcase-viewport" aria-current={i === index ? "true" : undefined} onClick={() => { setDirection(i > index ? 1 : -1); setIndex(i); }}><span /></button>)}
        </div>
        <button className="icon-button carousel-next" type="button" aria-label="Next app preview" aria-controls="showcase-viewport" onClick={() => changeScreen(1)}><ArrowRight size={20} aria-hidden="true" /></button>
      </div>
      {!screen.image && <p className="showcase-disclaimer">This is an illustrative preview, not an actual app screenshot. Genuine customer, rider, and merchant captures will replace these illustrations when supplied.</p>}
      <a href="#ecosystem" className="text-link">Meet the three Ngaon apps<ArrowUpRight size={16} aria-hidden="true" /></a>
    </div>
  </div>;
}
