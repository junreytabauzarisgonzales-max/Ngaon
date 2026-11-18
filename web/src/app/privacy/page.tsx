import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";
import { privacySections } from "@/content/legal-content";
import { Footer } from "@/components/sections";
import { SiteHeader } from "@/components/site-header";

export const metadata: Metadata = {
  title: "Privacy Policy | Ngaon",
  description: "Starter Privacy Policy for the Ngaon website and applications.",
};

export default function PrivacyPage() {
  return <><SiteHeader /><main id="main"><LegalPage eyebrow="A little clarity" title="Privacy Policy" description="How Ngaon may handle information across the website and connected applications." sections={privacySections} /></main><Footer /></>;
}
