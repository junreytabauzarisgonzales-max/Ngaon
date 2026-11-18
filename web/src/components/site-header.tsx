import { navigation } from "@/content/site-content";
import { Brand, LinkButton } from "./ui";
import { MobileNavigation } from "./mobile-navigation";
import { ThemeToggle } from "./theme-toggle";

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="container header-inner">
        <Brand />
        <nav className="desktop-navigation" aria-label="Main navigation">
          {navigation.map((link) => <a key={link.href} href={link.href}>{link.label}</a>)}
        </nav>
        <ThemeToggle className="header-theme-toggle" />
        <LinkButton href="#download" className="header-cta">Get Ngaon</LinkButton>
        <MobileNavigation />
      </div>
    </header>
  );
}
