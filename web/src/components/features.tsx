import { ArrowUpRight, Languages, Motorbike, MapPin, MessageCircle, Package, ReceiptText, ShoppingBasket, Utensils } from "lucide-react";
import { services } from "@/content/site-content";
import { Reveal } from "./motion";
import { IconBox, SectionHeading } from "./ui";

const icons = { bike: Motorbike, utensils: Utensils, basket: ShoppingBasket, package: Package };

function ServiceArt({ service }: { service: string }) {
  if (service === "ride") return <div className="service-art ride-art" aria-hidden="true"><svg viewBox="0 0 420 150" fill="none"><path d="M35 119c81 0 53-85 147-85s87 89 204 34" /><circle cx="35" cy="119" r="7" /><circle cx="386" cy="68" r="7" /></svg><span className="ride-art-icon"><Motorbike size={35} strokeWidth={1.5} /></span><span className="art-caption caption-pickup">PICKUP</span><span className="art-caption caption-dropoff">YOUR DESTINATION</span></div>;
  if (service === "food") return <div className="service-art food-art" aria-hidden="true"><div className="food-plate"><Utensils size={46} strokeWidth={1.25} /></div><span className="mini-pill"><CheckMark />Bisaya: “Kumain”</span></div>;
  if (service === "pabili") return <div className="service-art shopping-art" aria-hidden="true"><div className="shopping-paper"><span>SINAMA: TO GRAB</span><div><CheckMark /><i /></div><div><CheckMark /><i /></div><div><CheckMark /><i /></div></div><span className="basket-art"><ShoppingBasket size={36} strokeWidth={1.4} /></span></div>;
  return <div className="service-art parcel-art" aria-hidden="true"><div className="parcel-outline"><Package size={75} strokeWidth={0.85} /></div><span className="parcel-route"><span /><i /><MapPin size={20} /></span><span className="mini-pill">A → B, with care</span></div>;
}

function CheckMark() { return <span className="tiny-check">✓</span>; }

export function Features() {
  return <section id="features" tabIndex={-1} className="section section-features" aria-labelledby="features-heading">
    <div className="container">
      <Reveal><div className="heading-row"><SectionHeading eyebrow="Sinama: to grab · Bisaya: kumain" title="One app. Four ways to get things moving." id="features-heading" /><p className="heading-aside">Whether you need to grab a ride or <em>kumain</em>,<br />there’s a Ngaon for that.</p></div></Reveal>
      <div className="features-grid">{services.map((service, index) => <Reveal key={service.id} delay={index * 0.06} className={`feature-slot slot-${service.id}`}><article className={`feature-card feature-${service.id}`}>
        <div className="feature-card-top"><IconBox icon={icons[service.icon]} /><span className="feature-number">0{index + 1}</span></div>
        <div className="feature-copy"><p className="feature-label">{service.label}</p><h3>{service.title}</h3><p>{service.description}</p></div>
        <ServiceArt service={service.id} />
        <div className="feature-card-bottom"><span>{service.detail}</span><ArrowUpRight size={18} aria-hidden="true" /></div>
      </article></Reveal>)}</div>
      <Reveal><div className="supporting-features supporting-features-four">{[{ icon: Languages, title: "Speaks your dialect", text: "Sinama, Tausug & Bisaya features." }, { icon: MapPin, title: "Follow the progress", text: "Booking updates, in the app." }, { icon: ReceiptText, title: "Know your fare", text: "Review the breakdown before booking." }, { icon: MessageCircle, title: "Stay connected", text: "Chat with your assigned rider." }].map(({ icon: Icon, title, text }) => <div key={title}><Icon size={22} strokeWidth={1.5} aria-hidden="true" /><div><h3>{title}</h3><p>{text}</p></div></div>)}</div></Reveal>
    </div>
  </section>;
}
