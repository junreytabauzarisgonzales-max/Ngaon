"use client";

import Image from "next/image";
import { ArrowDown, ArrowUpRight, MapPin, Package, Route } from "lucide-react";
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
        <p className="location-pill"><span className="location-dot" />Made for Bongao, Tawi-Tawi<ArrowUpRight size={13} aria-hidden="true" /></p>
        <div className="hero-chip-group" aria-label="Ngaon services"><span className="hero-chip">Ride</span><span className="hero-chip">Food</span><span className="hero-chip">Pabili</span><span className="hero-chip">Padala</span></div>
        <m.div initial={{ opacity: 0, scale: 0.7 }} animate={{ opacity: 1, scale: 1 }} transition={{ duration: 0.8 }} className="hero-logo-wrap">
          <Image src="/brand/ngaon-logo.gif" alt="Ngaon logo" width={160} height={160} className="hero-logo" />
        </m.div>
        <m.h1 id="hero-heading" initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5, delay: 0.9 }}>Your everyday,{" "}<br /><span>delivered.</span></m.h1>
        <p className="hero-description">Rides, food, shopping errands, and parcel delivery—together in Ngaon, built for Bongao, Tawi-Tawi.</p>
        <div className="hero-actions"><LinkButton href="#features">Explore Ngaon</LinkButton><LinkButton href="#showcase" secondary>See the App</LinkButton></div>
        <a className="hero-scroll" href="#features"><span><ArrowDown size={14} aria-hidden="true" /></span>A little more about your everyday</a>
      </HeroEntrance>
      <HeroEntrance className="hero-visual" delay={0.08} mockup>
        <div className="hero-orbit orbit-one" aria-hidden="true" /><div className="hero-orbit orbit-two" aria-hidden="true" />
        <span className="hero-visual-label"><span />{screen?.image ? "FOUR SERVICES. ONE NGAON." : "ILLUSTRATIVE PREVIEW · NOT AN APP SCREENSHOT"}</span>
        <div className="hero-phone-wrap"><PhonePreview image={screen?.image} eager /></div>
        <div className="floating-note note-one"><span className="note-icon"><Route size={21} aria-hidden="true" /></span><div><strong>A little closer.</strong><span>Every journey starts here.</span></div><ArrowUpRight size={16} aria-hidden="true" /></div>
        <div className="floating-note note-two"><span className="note-icon"><Package size={20} aria-hidden="true" /></span><div><strong>Big on the everyday.</strong><span>Even the little deliveries.</span></div></div>
        <p className="hero-location"><MapPin size={13} aria-hidden="true" />Locally connected. Simply Ngaon.</p>
      </HeroEntrance>
    </div>
    <div className="hero-bottom"><div className="container hero-bottom-inner"><p>Less running around.<br /><strong>More getting on with your day.</strong></p><div><span>01 /</span><p>Go somewhere.<br /><strong>Or let it come to you.</strong></p></div><ArrowUpRight size={28} strokeWidth={1.2} aria-hidden="true" /></div></div>
  </section>;
}
