import type { Metadata, Viewport } from "next";
import { GeistSans } from "geist/font/sans";
import Script from "next/script";
import { MotionProvider } from "@/components/motion";
import { siteUrl } from "@/content/site-content";
import "./globals.css";

const title = "Ngaon — Ride, Food, Pabili & Padala in Bongao, Tawi-Tawi.";
const description = "Rides, food, shopping errands, and parcel delivery—together in Ngaon, built for Bongao, Tawi-Tawi. Explore the customer, rider, and merchant apps.";

const socialCard = "/social/ngaon-card.png";

export const metadata: Metadata = {
  ...(siteUrl ? { metadataBase: new URL(siteUrl), alternates: { canonical: "/" } } : {}),
  title,
  description,
  applicationName: "Ngaon",
  icons: [
    { rel: "icon", url: "/brand/icon-32.png", sizes: "32x32", type: "image/png" },
    { rel: "icon", url: "/brand/ngaon-logo-192.jpg", sizes: "192x192", type: "image/jpeg" },
    { rel: "apple-touch-icon", url: "/brand/apple-touch-icon.png", sizes: "180x180", type: "image/png" },
  ],
  openGraph: {
    title,
    description,
    type: "website",
    locale: "en_PH",
    siteName: "Ngaon",
    ...(siteUrl ? { url: siteUrl, images: [{ url: socialCard, width: 1200, height: 630, alt: "Ngaon brand card. ngaon. Your everyday, delivered. Ride · Food · Pabili · Padala — Built for Bongao, Tawi-Tawi." }] } : {}),
  },
  twitter: {
    card: siteUrl ? "summary_large_image" : "summary",
    title,
    description,
    ...(siteUrl ? { images: [socialCard] } : {}),
  },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#FFFFFF" },
    { media: "(prefers-color-scheme: dark)", color: "#07130D" },
  ],
  colorScheme: "light dark",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const structured = siteUrl ? {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: "Ngaon",
    url: siteUrl,
    description,
    inLanguage: "en-PH",
    publisher: {
      "@type": "Organization",
      name: "Ngaon",
      url: siteUrl,
      logo: `${siteUrl}${socialCard}`,
    },
    potentialAction: {
      "@type": "SearchAction",
      target: "/",
      "query-input": "required",
    },
  } : null;

  return (
    <html lang="en" className={GeistSans.variable} suppressHydrationWarning>
      <body>
        <Script id="theme-init" strategy="beforeInteractive">{`(() => { try { const stored = window.localStorage.getItem("ngaon-theme"); const theme = stored === "dark" || stored === "light" ? stored : (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"); document.documentElement.dataset.theme = theme; } catch { document.documentElement.dataset.theme = "light"; } })();`}</Script>
        <a href="#main" className="skip-link">Skip to content</a>
        <MotionProvider>{children}</MotionProvider>
        {structured && <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structured) }} />}
      </body>
    </html>
  );
}
