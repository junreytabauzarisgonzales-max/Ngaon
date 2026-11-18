import { ArrowLeft, ArrowUpRight } from "lucide-react";
import Link from "next/link";
import type { LegalSection } from "@/content/legal-content";
import { legalReviewNote } from "@/content/legal-content";
import { Brand } from "./ui";

export function LegalPage({
  eyebrow,
  title,
  description,
  sections,
}: {
  eyebrow: string;
  title: string;
  description: string;
  sections: LegalSection[];
}) {
  return <div className="legal-page">
    <div className="container legal-page-header">
      <Link className="legal-back-link" href="/"><ArrowLeft size={16} aria-hidden="true" />Back to Ngaon</Link>
      <div className="legal-heading-row">
        <div>
          <p className="eyebrow"><span />{eyebrow}</p>
          <h1>{title}</h1>
          <p className="legal-lede">{description}</p>
        </div>
        <Brand />
      </div>
      <aside className="legal-review-note"><strong>Review before publication.</strong> {legalReviewNote}</aside>
    </div>
    <div className="container legal-content-grid">
      <nav className="legal-toc" aria-label={`${title} sections`}>
        <p>On this page</p>
        {sections.map((section) => <a key={section.id} href={`#${section.id}`}>{section.heading.replace(/^\d+\. /, "")}</a>)}
      </nav>
      <article className="legal-article">
        <p className="legal-updated">Effective date: To be confirmed</p>
        {sections.map((section) => <section key={section.id} id={section.id} className="legal-section" aria-labelledby={`${section.id}-heading`}>
          <h2 id={`${section.id}-heading`}>{section.heading}</h2>
          {section.paragraphs?.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
          {section.bullets && <ul>{section.bullets.map((bullet) => <li key={bullet}>{bullet}</li>)}</ul>}
        </section>)}
        <Link className="text-link legal-home-link" href="/"><span>Return to the homepage</span><ArrowUpRight size={16} aria-hidden="true" /></Link>
      </article>
    </div>
  </div>;
}
