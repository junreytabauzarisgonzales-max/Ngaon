import type { MetadataRoute } from "next";
import { siteUrl } from "@/content/site-content";

export const dynamic = "force-static";
export default function sitemap(): MetadataRoute.Sitemap {
  return siteUrl ? [{ url: siteUrl, changeFrequency: "monthly", priority: 1 }] : [];
}
