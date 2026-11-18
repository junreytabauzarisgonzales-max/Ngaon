import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";
import { termsSections } from "@/content/legal-content";
import { Footer } from "@/components/sections";
import { SiteHeader } from "@/components/site-header";

export const metadata: Metadata = {
  title: "Terms of Service | Ngaon",
  description: "Starter Terms of Service for the Ngaon website and applications.",
};

export default function TermsPage() {
  return <><SiteHeader /><main id="main"><LegalPage eyebrow="The fine print" title="Terms of Service" description="The common rules for using the Ngaon website and connected applications." sections={termsSections} /></main><Footer /></>;
}
