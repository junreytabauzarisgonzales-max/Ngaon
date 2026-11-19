"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, m, useIsPresent, useReducedMotion } from "motion/react";
import { ArrowUpRight, Menu, X } from "lucide-react";
import { navigation } from "@/content/site-content";

function MobileMenu({ onNavigate }: { onNavigate: (href: string) => void }) {
  const present = useIsPresent();
  const reduced = useReducedMotion();

  return (
    <m.nav
      id="mobile-menu"
      aria-label="Mobile navigation"
      aria-hidden={!present}
      inert={!present}
      className="mobile-menu"
      initial={{ opacity: 0, y: reduced ? 0 : -6 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: reduced ? 0 : -4 }}
      transition={{ duration: reduced ? 0 : 0.16, ease: [0.22, 1, 0.36, 1] }}
    >
       {[...navigation, { label: "Explore the apps", href: "#showcase" }].map((link) => (
        <a key={link.href} href={link.href} onClick={() => onNavigate(link.href)}>
          {link.label}<ArrowUpRight size={17} aria-hidden="true" />
        </a>
      ))}
    </m.nav>
  );
}

export function MobileNavigation() {
  const [open, setOpen] = useState(false);
  const button = useRef<HTMLButtonElement>(null);
  const wrapper = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") { setOpen(false); button.current?.focus(); }
    };
    const onPointer = (event: PointerEvent) => {
      if (!wrapper.current?.contains(event.target as Node)) setOpen(false);
    };
    const onResize = () => { if (window.innerWidth >= 900) setOpen(false); };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    window.addEventListener("resize", onResize);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
      window.removeEventListener("resize", onResize);
    };
  }, [open]);

  return (
    <div ref={wrapper} className="mobile-navigation" onBlur={(event) => {
      if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false);
    }}>
      <button ref={button} type="button" className="icon-button" aria-label={open ? "Close navigation" : "Open navigation"} aria-expanded={open} aria-controls="mobile-menu" onClick={() => setOpen(!open)}>
        {open ? <X size={22} aria-hidden="true" /> : <Menu size={22} aria-hidden="true" />}
      </button>
      <AnimatePresence>
        {open && <MobileMenu onNavigate={(href) => {
          setOpen(false);
          document.querySelector<HTMLElement>(href)?.focus({ preventScroll: true });
        }} />}
      </AnimatePresence>
    </div>
  );
}
