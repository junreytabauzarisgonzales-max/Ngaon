import Image from "next/image";
import { ArrowUpRight, BatteryFull, Motorbike, Check, ChevronRight, CircleCheck, MapPin, Navigation, Package, ShoppingBasket, Signal, Store, Utensils, Wallet, Wifi } from "lucide-react";
import type { AppScreen, PreviewKind } from "@/content/site-content";
import { AutoplayVideo } from "./autoplay-video";

function MapIllustration() {
  return <div className="map-illustration" aria-hidden="true">
    <svg viewBox="0 0 300 230" fill="none"><path d="M-20 42 110 105 325 16M-10 170 165 90 310 167M72-10 110 105 78 250M210-10 165 90 231 248" className="map-road" /><path d="m98 176 28-45 39-20 28-52" className="map-route" /><circle cx="98" cy="176" r="8" className="map-point" /><circle cx="193" cy="59" r="8" className="map-point-end" /></svg>
    <span className="map-place place-one">BONGAO</span><span className="map-place place-two">YOUR EVERYDAY, CONNECTED</span>
    <span className="map-rider"><Navigation size={18} fill="currentColor" /></span>
  </div>;
}

function ScreenIllustration({ kind }: { kind: PreviewKind }) {
  if (kind === "tracking") return <>
    <p className="preview-kicker">A LITTLE MORE CONNECTED</p><h3>Along the way.</h3>
    <MapIllustration />
    <div className="preview-info"><span className="preview-mini-icon"><Motorbike size={21} /></span><div><strong>Your assigned rider</strong><span>Follow their progress in the app</span></div></div>
    <div className="preview-timeline"><span><Check size={12} />Confirmed</span><span><Navigation size={12} />On the way</span><span><MapPin size={12} />Arriving</span></div>
  </>;
  if (kind === "pabili") return <>
    <p className="preview-kicker">ONE LESS THING ON YOUR LIST</p><h3>A helping hand.</h3>
    <div className="preview-large-icon"><ShoppingBasket size={48} strokeWidth={1.3} /></div>
    <div className="preview-list">{["Create your shopping list", "Set your item budget", "Review the rider’s receipt"].map((item, i) => <div key={item}><span>{String(i + 1).padStart(2, "0")}</span><strong>{item}</strong><Check size={15} /></div>)}</div>
    <p className="preview-note">Your everyday essentials.<br />With you, every step.</p>
  </>;
  if (kind === "food") return <>
    <p className="preview-kicker">FROM LOCAL KITCHENS</p><h3>Something good.</h3>
    <div className="preview-large-icon"><Utensils size={48} strokeWidth={1.3} /></div>
    <div className="preview-list">{["Browse merchants", "Choose meals and add-ons", "Follow preparation and delivery"].map((item, i) => <div key={item}><span>{String(i + 1).padStart(2, "0")}</span><strong>{item}</strong><ChevronRight size={15} /></div>)}</div>
    <p className="preview-note">From their kitchen.<br />To your door.</p>
  </>;
  if (kind === "padala") return <>
    <p className="preview-kicker">SEND A LITTLE CARE</p><h3>On its way.</h3>
    <div className="preview-large-icon"><Package size={48} strokeWidth={1.3} /></div>
    <div className="preview-list">{["Parcel pickup and drop-off", "Recipient information", "Proof of delivery"].map((item, i) => <div key={item}><span>{String(i + 1).padStart(2, "0")}</span><strong>{item}</strong><Check size={15} /></div>)}</div>
    <p className="preview-note">From your hands.<br />To theirs.</p>
  </>;
  if (kind === "rider") return <>
    <p className="preview-kicker">NGAON RIDER</p><h3>Ready for<br />what’s next.</h3>
    <MapIllustration />
    <div className="preview-info"><span className="preview-mini-icon"><Navigation size={20} /></span><div><strong>New service offers</strong><span>Review the details, then accept</span></div></div>
    <div className="preview-bottom-pair"><span><CircleCheck size={17} /> Active jobs</span><span><ArrowUpRight size={17} /> Earnings</span></div>
  </>;
  if (kind === "riderActive") return <>
    <p className="preview-kicker">NGAON RIDER</p><h3>One clear route.</h3>
    <MapIllustration />
    <div className="preview-info"><span className="preview-mini-icon"><Package size={20} /></span><div><strong>Active delivery</strong><span>Pickup → Drop-off</span></div></div>
    <div className="preview-timeline"><span><Check size={12} />Accepted</span><span><Navigation size={12} />On the way</span><span><MapPin size={12} />Drop-off</span></div>
  </>;
  if (kind === "riderEarnings") return <>
    <p className="preview-kicker">NGAON RIDER</p><h3>Your work,<br />in view.</h3>
    <div className="preview-large-icon"><Wallet size={48} strokeWidth={1.3} /></div>
    <div className="preview-list">{["Completed jobs", "Earnings summary", "Wallet and top-ups"].map((item, i) => <div key={item}><span>{String(i + 1).padStart(2, "0")}</span><strong>{item}</strong><ChevronRight size={15} /></div>)}</div>
    <p className="preview-note">A clearer view<br />of your day.</p>
  </>;
  if (kind === "merchant") return <>
    <p className="preview-kicker">NGAON MERCHANT</p><h3>Good food.<br />Clearer flow.</h3>
    <div className="preview-large-icon merchant-illustration"><Store size={48} strokeWidth={1.3} /></div>
    <div className="preview-list">{["Review incoming orders", "Prepare something good", "Ready for rider pickup"].map((item, i) => <div key={item}><span>{String(i + 1).padStart(2, "0")}</span><strong>{item}</strong><ChevronRight size={15} /></div>)}</div>
    <p className="preview-note">From your kitchen.<br />To their everyday.</p>
  </>;
  if (kind === "merchantMenu") return <>
    <p className="preview-kicker">NGAON MERCHANT</p><h3>Your menu,<br />your way.</h3>
    <div className="preview-large-icon merchant-illustration"><Utensils size={48} strokeWidth={1.3} /></div>
    <div className="preview-list">{["Menu items and add-ons", "Availability controls", "Edits saved as drafts"].map((item, i) => <div key={item}><span>{String(i + 1).padStart(2, "0")}</span><strong>{item}</strong><ChevronRight size={15} /></div>)}</div>
    <p className="preview-note">Keep your storefront<br />current.</p>
  </>;
  return <>
    <div className="preview-welcome"><div><p className="preview-kicker">MADE FOR YOUR EVERYDAY</p><h3>Hey, Bongao<span>.</span></h3></div><span className="preview-avatar"><MapPin size={17} /></span></div>
    <p className="preview-subtitle">Where are we going today?</p>
    <div className="preview-services">{[{ label: "Ride", icon: Motorbike }, { label: "Food", icon: Utensils }, { label: "Pabili", icon: ShoppingBasket }, { label: "Padala", icon: Package }].map(({ label, icon: Icon }) => <div key={label}><Icon size={25} strokeWidth={1.5} /><strong>{label}</strong><ArrowUpRight size={12} /></div>)}</div>
    <div className="preview-home-message"><span className="preview-mini-icon"><Navigation size={20} /></span><div><strong>A little closer.</strong><span>To the people and places that matter.</span></div></div>
    <div className="preview-local"><MapIllustration /><span><MapPin size={12} /> Bongao, Tawi-Tawi</span></div>
  </>;
}

export function PhonePreview({ kind = "home", image, video, className = "", eager = false }: { kind?: PreviewKind; image?: AppScreen["image"]; video?: AppScreen["video"]; className?: string; eager?: boolean }) {
  return <div className={`phone-frame${image ? " phone-frame-image" : ""} ${className}`}>
    {!image && <div className="phone-camera" aria-hidden="true" />}
    <div className="phone-screen">
      {image ? <>
        {(["light", "dark"] as const).map((mode) => video ? (
          <AutoplayVideo key={mode} base={video[mode]} poster={image[mode]} className={`actual-screenshot themed-${mode}`} width={image.width} height={image.height} label={image.alt} eager={eager} />
        ) : (
          // eslint-disable-next-line @next/next/no-img-element -- static export; light/dark pair toggled by CSS
          <img key={mode} className={`actual-screenshot themed-${mode}`} src={image[mode]} alt={mode === "light" ? image.alt : ""} aria-hidden={mode === "dark" ? true : undefined} width={image.width} height={image.height} loading={eager ? "eager" : "lazy"} fetchPriority={eager ? "high" : "auto"} decoding="async" draggable={false} />
        ))}
      </> : <div className="illustrative-screen" role="img" aria-label={`Illustrative ${kind} app concept, not an actual app screenshot`}>
        <div className="preview-status" aria-hidden="true"><span>9:41</span><span><Signal size={12} /><Wifi size={12} /><BatteryFull size={16} /></span></div>
        <div className="preview-wordmark"><Image src="/brand/ngaon-logo.png" alt="" width={60} height={40} /></div>
        <ScreenIllustration kind={kind} />
        <div className="illustration-label">ILLUSTRATIVE PREVIEW · NOT AN APP SCREENSHOT</div>
      </div>}
    </div>
    {!image && <span className="phone-home-indicator" aria-hidden="true" />}
  </div>;
}
