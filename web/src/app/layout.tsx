import type { Metadata, Viewport } from "next";
import { GeistSans } from "geist/font/sans";
import { MotionProvider } from "@/components/motion";
import { themeBootScript } from "@/content/theme";
import { siteUrl } from "@/content/site-content";
import "./globals.css";

const title = "Ngaon — Ride, Food, Pabili & Padala in Bongao, Tawi-Tawi.";
const description = "Ngaon means “to get or grab” in Sinama and “kumain” (to eat) in Bisaya. Rides, food, shopping errands, and parcel delivery built for Bongao, Tawi-Tawi with local dialect features for Sinama, Tausug, and Bisaya.";

const socialCard = "/social/ngaon-card.png";

export const metadata: Metadata = {
  ...(siteUrl ? { metadataBase: new URL(siteUrl), alternates: { canonical: "/" } } : {}),
  title,
  description,
  applicationName: "Ngaon",
  icons: [
    { rel: "icon", url: "/brand/icon-32.png", sizes: "32x32", type: "image/png" },
    { rel: "icon", url: "/brand/icon-192.png", sizes: "192x192", type: "image/png" },
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
    { media: "(prefers-color-scheme: dark)", color: "#0A0F0C" },
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
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeBootScript }} />
      </head>
      <body>
        <a href="#main" className="skip-link">Skip to content</a>
        <MotionProvider>{children}</MotionProvider>
        {structured && <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structured) }} />}
      </body>
    </html>
  );
}
