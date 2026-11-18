"use client";

import { Moon, Sun } from "lucide-react";
import { useSyncExternalStore } from "react";

type Theme = "light" | "dark";
const storageKey = "ngaon-theme";
const subscribe = (onStoreChange: () => void) => {
  window.addEventListener("ngaon-theme-change", onStoreChange);
  return () => window.removeEventListener("ngaon-theme-change", onStoreChange);
};
const getSnapshot = (): Theme => document.documentElement.dataset.theme === "dark" ? "dark" : "light";
const getServerSnapshot = (): Theme => "light";

export function ThemeToggle({ className = "" }: { className?: string }) {
  const theme = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);

  function toggleTheme() {
    const nextTheme: Theme = theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = nextTheme;
    window.localStorage.setItem(storageKey, nextTheme);
    window.dispatchEvent(new Event("ngaon-theme-change"));
  }

  const label = theme === "dark" ? "Switch to light theme" : "Switch to dark theme";
  return <button type="button" className={`icon-button theme-toggle ${className}`} aria-label={label} title={label} onClick={toggleTheme}>
    {theme === "dark" ? <Sun size={19} aria-hidden="true" /> : <Moon size={19} aria-hidden="true" />}
  </button>;
}
