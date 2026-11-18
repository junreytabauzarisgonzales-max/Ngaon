export type AppRole = "customer" | "rider" | "merchant";
export type PreviewKind =
  | "home"
  | "tracking"
  | "activity"
  | "pabili"
  | "food"
  | "padala"
  | "rider"
  | "riderActive"
  | "riderEarnings"
  | "merchant"
  | "merchantMenu";

export type AppScreen = {
  id: string;
  role: AppRole;
  kind: PreviewKind;
  title: string;
  description: string;
  image?: { src: string; width: number; height: number; alt: string };
};

export const navigation = [
  { label: "Features", href: "#features" },
  { label: "How it works", href: "#how-it-works" },
  { label: "The app", href: "#showcase" },
  { label: "About", href: "#about" },
] as const;

export const services = [
  { id: "ride", title: "Ride", label: "A little closer.", description: "Motorcycle ride booking with pickup, drop-off, fare quotes, and tracking.", detail: "Your pickup. Your destination.", icon: "bike" },
  { id: "food", title: "Food", label: "Something good.", description: "Browse merchants, choose meals, customize orders, and request delivery.", detail: "From their kitchen to your door.", icon: "utensils" },
  { id: "pabili", title: "Pabili", label: "One less errand.", description: "Create a shopping list, set an item budget, and approve the rider’s receipt total.", detail: "Your list, with a helping hand.", icon: "basket" },
  { id: "padala", title: "Padala", label: "Send it on its way.", description: "Arrange parcel pickup and delivery with recipient and package details.", detail: "A thoughtful way to send.", icon: "package" },
] as const;

export const workflow = [
  { title: "Choose a service", description: "A ride, a meal, an errand, or a parcel. Start with what you need.", icon: "grid" },
  { title: "Enter the details", description: "Add your locations, pick your meals, or tell your rider what to buy or send.", icon: "pin" },
  { title: "Review and confirm", description: "See the fare breakdown, choose an available payment method, and confirm.", icon: "check" },
  { title: "Follow the progress", description: "Keep up with preparation, rider assignment, pickup, and completion in the app.", icon: "route" },
] as const;

export const applications: {
  id: AppRole;
  name: string;
  shortName: string;
  description: string;
  detail: string;
  downloadUrl: string | null;
  releaseStatus: string | null;
}[] = [
  { id: "customer", name: "Ngaon Customer", shortName: "Customer", description: "Book rides, order food, request errands, and arrange parcel delivery.", detail: "For your everyday", downloadUrl: null, releaseStatus: null },
  { id: "rider", name: "Ngaon Rider", shortName: "Rider", description: "Receive service offers, manage delivery jobs, and track earnings.", detail: "For the journey", downloadUrl: null, releaseStatus: null },
  { id: "merchant", name: "Ngaon Merchant", shortName: "Merchant", description: "Manage incoming orders, menu items, preparation, and store activity.", detail: "For your business", downloadUrl: null, releaseStatus: null },
];

export const appScreens: AppScreen[] = [
  { id: "customer-home", role: "customer", kind: "home", title: "Your day starts here.", description: "Four everyday services, together in the customer app. Choose what you need and take the next step.", image: { src: "/screenshots/customer-home.webp", width: 640, height: 1426, alt: "Ngaon customer home screen showing Juan and the Ride, Food, Pabili, and Padala services" } },
  { id: "customer-ride", role: "customer", kind: "home", title: "A ride when you need one.", description: "Review a motorcycle route, fare, payment method, and booking action before you confirm.", image: { src: "/screenshots/customer-ride.webp", width: 640, height: 1426, alt: "Ngaon customer ride quote screen showing a motorcycle route and forty peso fare" } },
  { id: "customer-food", role: "customer", kind: "food", title: "Something good, nearby.", description: "Browse a customer food screen with clearly labeled demonstration menu choices.", image: { src: "/screenshots/customer-food.webp", width: 640, height: 1426, alt: "Ngaon customer food screen showing demo menu choices from local merchants" } },
  { id: "customer-pabili", role: "customer", kind: "pabili", title: "Your list. A helping hand.", description: "Build a shopping list, set the store and drop-off details, and review the price before requesting the errand.", image: { src: "/screenshots/customer-pabili.webp", width: 640, height: 1426, alt: "Ngaon customer Pabili screen showing store, delivery, and shopping list fields" } },
  { id: "customer-padala", role: "customer", kind: "padala", title: "Send with care.", description: "Set parcel pickup and drop-off details, add recipient information, and choose a parcel size.", image: { src: "/screenshots/customer-padala.webp", width: 640, height: 1426, alt: "Ngaon customer Padala screen showing parcel pickup, drop-off, recipient, and size fields" } },
  { id: "customer-tracking-map", role: "customer", kind: "tracking", title: "See the journey.", description: "The active booking map shows the pickup, destination, and the current search for a rider.", image: { src: "/screenshots/customer-tracking-map.webp", width: 640, height: 1426, alt: "Ngaon customer active ride map showing pickup, destination, and finding a rider status" } },
  { id: "customer-tracking-details", role: "customer", kind: "tracking", title: "Stay in the loop.", description: "Review the route, fare, payment status, and booking timeline as the ride progresses.", image: { src: "/screenshots/customer-tracking-details.webp", width: 640, height: 1426, alt: "Ngaon customer ride tracking details showing route, fare, payment, and status timeline" } },
  { id: "customer-activity", role: "customer", kind: "activity", title: "Your bookings, together.", description: "Active and past activity stay in one place, with the current booking ready to open.", image: { src: "/screenshots/customer-activity.webp", width: 640, height: 1426, alt: "Ngaon customer activity screen showing an active ride booking and navigation tabs" } },
  { id: "rider-jobs", role: "rider", kind: "rider", title: "A clearer next step.", description: "New offers, active-job steps, and delivery proof stay together while you ride." },
  { id: "rider-active", role: "rider", kind: "riderActive", title: "Every step, in order.", description: "Move through pickup, drop-off, and delivery proof with the job details kept together." },
  { id: "rider-earnings", role: "rider", kind: "riderEarnings", title: "Your work, in view.", description: "Review completed jobs, earnings summaries, and wallet information in the rider app." },
  { id: "merchant-orders", role: "merchant", kind: "merchant", title: "Keep your kitchen connected.", description: "Review incoming orders, set preparation time, and mark orders ready for rider pickup." },
  { id: "merchant-menu", role: "merchant", kind: "merchantMenu", title: "Your menu, your way.", description: "Update menu items and add-ons, manage availability, and keep your storefront current." },
];

export const faqs = [
  { question: "What is Ngaon?", answer: "Ngaon is a delivery super-app designed for Bongao, Tawi-Tawi. It brings Ride, Food, Pabili, and Padala together through connected customer, rider, and merchant applications." },
  { question: "What services does Ngaon offer?", answer: "Ride is for motorcycle trips. Food lets you browse merchants and order meals. Pabili is for shopping errands. Padala is for parcel pickup and delivery. Actual booking availability is determined in the application." },
  { question: "What is Pabili?", answer: "Pabili lets you create a shopping list, specify a store name and estimated item budget, and enter a delivery location. A store map pin is optional. The rider uploads a receipt and item total for your approval before continuing the delivery. The initial quote covers fees; the actual receipt total is added to the job’s fare when the rider submits it." },
  { question: "How does delivery tracking work?", answer: "The app shows booking status updates and the assigned rider’s location. Food orders also include merchant preparation updates. Tracking happens inside the application; this website is a product introduction." },
  { question: "What are the three Ngaon applications?", answer: "Ngaon Customer is for booking services. Ngaon Rider is for receiving and completing jobs and viewing earnings. Ngaon Merchant is for registered merchants to manage food orders, menus, store settings, and sales." },
  { question: "How can I access the applications?", answer: "The project currently includes Android applications. Verified public APK or app-store links have not been supplied for this website, so downloads are not offered here yet. Public release or beta status has not been confirmed." },
] as const;

// Supply the real public origin at build time. Never invent a production domain.
const configuredUrl = process.env.NEXT_PUBLIC_SITE_URL;
export const siteUrl = configuredUrl ? new URL(configuredUrl).origin : undefined;
