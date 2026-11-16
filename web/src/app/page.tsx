import { SiteHeader } from "@/components/site-header";
import { Hero } from "@/components/hero";
import { Features } from "@/components/features";
import { HowItWorks } from "@/components/how-it-works";
import { AppShowcase } from "@/components/app-showcase";
import { About, Download, Ecosystem, Faq, Footer } from "@/components/sections";
import { Reveal } from "@/components/motion";
import { SectionHeading } from "@/components/ui";
import { PhonePreview } from "@/components/phone-preview";
import { appScreens } from "@/content/site-content";

export default function HomePage() {
  return <div id="top"><SiteHeader /><main id="main" tabIndex={-1}>
    <Hero /><Features /><HowItWorks />
    <section id="showcase" tabIndex={-1} className="section showcase-section" aria-labelledby="showcase-heading"><div className="container"><Reveal><SectionHeading centered eyebrow="Meet the experience" title="Take a closer look." description="Thoughtfully connected, from the first tap to the last stop." id="showcase-heading" /></Reveal><AppShowcase previews={Object.fromEntries(appScreens.map((screen) => [screen.id, <PhonePreview key={screen.id} kind={screen.kind} image={screen.image} />]))} /></div></section>
    <Ecosystem /><About /><Download /><Faq />
  </main><Footer /></div>;
}
