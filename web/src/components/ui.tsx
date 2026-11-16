import Image from "next/image";
import { ArrowUpRight, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";

export function Brand({ inverse = false, href = "#top" }: { inverse?: boolean; href?: string }) {
  return (
    <a href={href} className={`brand${inverse ? " brand-inverse" : ""}`} aria-label="Ngaon home">
      <Image src="/brand/ngaon-logo-192.png" alt="" width={38} height={38} />
      <span>ngaon<span className="brand-dot">.</span></span>
    </a>
  );
}

export function SectionHeading({ eyebrow, title, description, centered = false, id }: {
  eyebrow: string; title: string; description?: string; centered?: boolean; id?: string;
}) {
  return (
    <div className={`section-heading${centered ? " text-center mx-auto" : ""}`}>
      <p className="eyebrow"><span />{eyebrow}</p>
      <h2 id={id}>{title}</h2>
      {description && <p className="section-description">{description}</p>}
    </div>
  );
}

export function LinkButton({ children, href, secondary = false, className = "" }: {
  children: ReactNode; href: string; secondary?: boolean; className?: string;
}) {
  return <a className={`button ${secondary ? "button-secondary" : "button-primary"} ${className}`} href={href}>{children}<ArrowUpRight size={17} aria-hidden="true" /></a>;
}

export function IconBox({ icon: Icon, className = "" }: { icon: LucideIcon; className?: string }) {
  return <span className={`icon-box ${className}`}><Icon size={23} strokeWidth={1.65} aria-hidden="true" /></span>;
}
