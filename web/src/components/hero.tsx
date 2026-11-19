"use client";

import Image from "next/image";
import { ArrowDown, ArrowUpRight, Languages, MapPin, Utensils, Route } from "lucide-react";
import { m } from "motion/react";
import { HeroEntrance } from "./motion";
import { PhonePreview } from "./phone-preview";
import { LinkButton } from "./ui";
import { appScreens } from "@/content/site-content";

export function Hero() {
  const screen = appScreens.find((item) => item.id === "customer-home");
  return <section className="hero" aria-labelledby="hero-heading">
    <div className="hero-glow" aria-hidden="true" />
    <div className="container hero-grid">
      <HeroEntrance className="hero-content">
        <p className="location-pill"><span className="location-dot" />Made for Bongao, Tawi-Tawi · Sinama · Tausug · Bisaya<ArrowUpRight size={13} aria-hidden="true" /></p>
        <div className="hero-chip-group" aria-label="Ngaon services"><span className="hero-chip">Ride</span><span className="hero-chip">Food</span><span className="hero-chip">Pabili</span><span className="hero-chip">Padala</span></div>
        <m.h1 id="hero-heading" initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }}>Grab a ride.{" "}<br /><span>Gather to eat.</span><m.div initial={{ opacity: 0, scale: 0.4 }} animate={{ opacity: 1, scale: 1 }} transition={{ duration: 0.8, delay: 0.8 }} className="hero-logo-wrap" style={{ marginLeft: 8, display: "inline-block", verticalAlign: "middle" }}><Image src="/brand/ngaon-mark.png" alt="Ngaon logo" width={150} height={100} className="hero-logo" /></m.div></m.h1>
        <p className="hero-description"><strong>Ngaon</strong> is the <strong>Sinama</strong> word for <em>“to get or grab”</em>—and in <strong>Bisaya</strong>, it means <em>“kumain” (to eat)</em>. One local super-app for rides, meals, errands, and parcels in Bongao, with dialect support for <strong>Sinama, Tausug, and Bisaya</strong>.</p>
        <div className="hero-etymology" aria-label="Meaning of the word Ngaon">
          <div className="hero-etymology-item">
            <span className="hero-etymology-lang">SINAMA</span>
            <strong>“To get or grab”</strong>
            <span>Ride · Pabili · Padala</span>
          </div>
          <div className="hero-etymology-divider" aria-hidden="true" />
          <div className="hero-etymology-item">
            <span className="hero-etymology-lang">BISAYA</span>
            <strong>“Kumain” (To eat)</strong>
            <span>Food · Local Kitchens</span>
          </div>
          <div className="hero-etymology-divider" aria-hidden="true" />
          <a href="#dialects" className="hero-etymology-item hero-etymology-link">
            <span className="hero-etymology-lang"><Languages size={11} aria-hidden="true" /> DIALECTS</span>
            <strong>Sinama · Tausug · Bisaya</strong>
            <span>Explore local dialect features →</span>
          </a>
        </div>
        <div className="hero-actions"><LinkButton href="#dialects">Why “Ngaon” &amp; Dialects</LinkButton><LinkButton href="#showcase" secondary>See the App</LinkButton></div>
        <a className="hero-scroll" href="#features"><span><ArrowDown size={14} aria-hidden="true" /></span>A little more about your everyday</a>
      </HeroEntrance>
      <HeroEntrance className="hero-visual" delay={0.08} mockup>
        <div className="hero-orbit orbit-one" aria-hidden="true" /><div className="hero-orbit orbit-two" aria-hidden="true" />
        <span className="hero-visual-label"><span />{screen?.image ? "SINAMA: TO GRAB · BISAYA: KUMAIN" : "ILLUSTRATIVE PREVIEW · NOT AN APP SCREENSHOT"}</span>
        <div className="hero-phone-wrap"><PhonePreview image={screen?.image} video={screen?.video} eager /></div>
        <div className="floating-note note-one"><span className="note-icon"><Route size={21} aria-hidden="true" /></span><div><strong>Sinama: “To get or grab”</strong><span>Rides, errands &amp; parcels.</span></div><ArrowUpRight size={16} aria-hidden="true" /></div>
        <div className="floating-note note-two"><span className="note-icon"><Utensils size={20} aria-hidden="true" /></span><div><strong>Bisaya: “Kumain”</strong><span>Hot meals from local kitchens.</span></div></div>
        <p className="hero-location"><MapPin size={13} aria-hidden="true" />Speaks Sinama, Tausug &amp; Bisaya in Bongao.</p>
      </HeroEntrance>
    </div>
    <div className="hero-bottom"><div className="container hero-bottom-inner"><p>In Sinama: <strong>“To get or grab.”</strong><br />In Bisaya: <strong>“Kumain — to eat.”</strong></p><div><span>LOCAL DIALECTS /</span><p>Built to speak your language.<br /><strong>Sinama · Tausug · Bisaya · English</strong></p></div><ArrowUpRight size={28} strokeWidth={1.2} aria-hidden="true" /></div></div>
  </section>;
}
