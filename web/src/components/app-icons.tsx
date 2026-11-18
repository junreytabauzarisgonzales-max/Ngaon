import Image from "next/image";

export type ServiceIconName = "ride" | "food" | "pabili" | "padala";

export const serviceIconSources: Record<ServiceIconName, string> = {
  ride: "/brand/service-icons/ride.webp",
  food: "/brand/service-icons/food.webp",
  pabili: "/brand/service-icons/pabili.webp",
  padala: "/brand/service-icons/padala.webp",
};

export const appIconSources = {
  customer: "/brand/apps/customer.webp",
  rider: "/brand/apps/rider.webp",
  merchant: "/brand/apps/merchant.webp",
} as const;

export function AppIcon({ src, size = 48, className = "" }: { src: string; size?: number; className?: string }) {
  return <Image src={src} width={size} height={size} alt="" className={className} />;
}

export function ServiceIcon({ service, size = 48, className = "" }: { service: ServiceIconName; size?: number; className?: string }) {
  return <AppIcon src={serviceIconSources[service]} size={size} className={`service-icon-image ${className}`} />;
}
