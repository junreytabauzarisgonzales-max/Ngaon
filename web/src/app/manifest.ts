import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Ngaon",
    short_name: "Ngaon",
    description: "Rides, food, shopping errands, and parcel delivery—together in Ngaon, built for Bongao, Tawi-Tawi.",
    start_url: "/",
    scope: "/",
    display: "standalone",
    orientation: "portrait",
    background_color: "#FFFFFF",
    theme_color: "#FFFFFF",
    icons: [
      { src: "/brand/icon-32.png", sizes: "32x32", type: "image/png" },
      { src: "/brand/apple-touch-icon.png", sizes: "180x180", type: "image/png" },
      { src: "/brand/ngaon-logo-192.png", sizes: "192x192", type: "image/png" },
    ],
  };
}
