"use client";

import { useSyncExternalStore } from "react";
import { Monitor, Moon, Sun } from "lucide-react";
import { themeStorageKey as KEY } from "@/content/theme";

type ThemeChoice = "system" | "light" | "dark";
const ORDER: ThemeChoice[] = ["system", "light", "dark"];
const LABEL: Record<ThemeChoice, string> = { system: "Theme: match device", light: "Theme: light", dark: "Theme: dark" };

/** Applies a theme choice: "system" lets the device decide (CSS media query). */
export function applyTheme(choice: ThemeChoice) {
  const root = document.documentElement;
  if (choice === "system") delete root.dataset.theme;
  else root.dataset.theme = choice;
}

// Saved choice as an external store (localStorage), shared by every toggle.
const listeners = new Set<() => void>();
function readChoice(): ThemeChoice {
  try {
    const saved = localStorage.getItem(KEY);
    return saved === "light" || saved === "dark" ? saved : "system";
  } catch {
    return "system";
  }
}
function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** System → Light → Dark, remembered on this device. */
export function ThemeToggle() {
  const choice = useSyncExternalStore(subscribe, readChoice, () => "system" as ThemeChoice);

  function next() {
    const value = ORDER[(ORDER.indexOf(choice) + 1) % ORDER.length];
    applyTheme(value);
    try {
      if (value === "system") localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, value);
    } catch {}
    listeners.forEach((l) => l());
  }

  const Icon = choice === "light" ? Sun : choice === "dark" ? Moon : Monitor;
  return (
    <button type="button" className="theme-toggle" onClick={next} aria-label={`${LABEL[choice]}. Change theme`} title={LABEL[choice]}>
      <Icon size={18} strokeWidth={1.8} aria-hidden="true" />
    </button>
  );
}
