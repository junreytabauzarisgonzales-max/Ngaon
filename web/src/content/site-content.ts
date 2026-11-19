export type AppRole = "customer" | "rider" | "merchant";
export type PreviewKind =
  | "home"
  | "tracking"
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
  /** Real app screenshot in both themes; the site shows the one matching the visitor's device. */
  image?: { light: string; dark: string; width: number; height: number; alt: string };
  /** Optional screen recording (light + dark), played instead of the still image.
   *  Paths without extension: a .webm and an .mp4 of each are served. */
  video?: { light: string; dark: string };
};

export const navigation = [
  { label: "Services", href: "#features" },
  { label: "Our voice", href: "#dialects" },
  { label: "The journey", href: "#booking" },
  { label: "The apps", href: "#showcase" },
  { label: "About", href: "#about" },
] as const;

export const nameMeanings = [
  {
    id: "sinama",
    language: "Sinama",
    meaning: "“To get” or “to grab”",
    tag: "RIDE · PABILI · PADALA",
    headline: "Grab a ride. Get your errands done.",
    description:
      "In Sinama—the language of the Sama people of Tawi-Tawi—Ngaon means to get, fetch, or grab. It captures the heart of an everyday super-app: grabbing a ride across Bongao, getting your market list picked up, or fetching a parcel from town.",
  },
  {
    id: "bisaya",
    language: "Bisaya",
    meaning: "“Kumain” or “to eat”",
    tag: "FOOD · LOCAL KITCHENS",
    headline: "Gather around. Let’s eat.",
    description:
      "In Bisaya, Ngaon means “kumain” or “to eat.” Mukaon also means “to eat.” From neighborhood carinderias to favorite local cafes, Ngaon brings freshly cooked comfort food from Bongao’s kitchens straight to your table.",
  },
] as const;

export type DialectId = "sinama" | "tausug" | "bisaya";

export type DialectProfile = {
  id: DialectId;
  name: string;
  badge: string;
  greeting: string;
  greetingTranslation: string;
  tagline: string;
  summary: string;
  servicePhrases: {
    service: "Ride" | "Food" | "Pabili" | "Padala";
    phrase: string;
    meaning: string;
  }[];
  chatPresets: {
    speaker: "Customer" | "Rider" | "Merchant";
    local: string;
    english: string;
  }[];
};

export const dialectProfiles: DialectProfile[] = [
  {
    id: "sinama",
    name: "Sinama",
    badge: "Tawi-Tawi & Sulu Archipelago",
    greeting: "Hap p’ddi! Ngaon kita.",
    greetingTranslation: "Good day! Let’s get things moving with Ngaon.",
    tagline: "Where the name Ngaon comes from—meaning “to get” or “to grab.”",
    summary:
      "Built for everyday conversations in Bongao and across the islands, Sinama dialect support makes booking a ride, ordering food, or sending errands feel natural for every generation.",
    servicePhrases: [
      { service: "Ride", phrase: "Ngaon motor / sakayan", meaning: "Grab a motorcycle ride to your destination" },
      { service: "Food", phrase: "Ngaon kinakan", meaning: "Get freshly prepared meals from local kitchens" },
      { service: "Pabili", phrase: "Pabilli ma tabu’", meaning: "Ask a rider to buy essentials from the market" },
      { service: "Padala", phrase: "Pabo’o barang", meaning: "Send a parcel safely to family or friends" },
    ],
    chatPresets: [
      { speaker: "Customer", local: "Maitu na aku ma bihing lān.", english: "I’m right here by the roadside." },
      { speaker: "Rider", local: "Pa’asek na aku paitu, agad-agad.", english: "I’m heading over now, almost there." },
      { speaker: "Merchant", local: "Lutu’ na in order nu!", english: "Your food order is cooked and ready!" },
    ],
  },
  {
    id: "tausug",
    name: "Tausug",
    badge: "Bongao, Sulu & Zamboanga Peninsula",
    greeting: "Marayaw adlaw! Kari na kaw.",
    greetingTranslation: "Good day! Come along, your everyday is ready.",
    tagline: "Spoken widely across Bongao’s markets, ports, and neighborhoods.",
    summary:
      "From the public market to Poblacion and beyond, Tausug language prompts and quick-chat replies let customers, riders, and store owners coordinate without barriers.",
    servicePhrases: [
      { service: "Ride", phrase: "Sumakat misan hain tungud", meaning: "Book a ride anywhere around town" },
      { service: "Food", phrase: "Mamiy pagkaun", meaning: "Order hot meals and local favorites" },
      { service: "Pabili", phrase: "Mag Pa bih pa tabu’", meaning: "Have your shopping list bought at the market" },
      { service: "Padala", phrase: "Hipahatod in parsèl", meaning: "Have a package picked up and delivered" },
    ],
    chatPresets: [
      { speaker: "Customer", local: "Yari ra aku ha tungud sin tinda.", english: "I’m waiting right in front of the store." },
      { speaker: "Rider", local: "Harap maun na aku, tagad-tagad kaw.", english: "I’m on my way now, please wait a moment." },
      { speaker: "Merchant", local: "Sakap na in pagkaun mu.", english: "Your meal is packed and ready for pickup." },
    ],
  },
  {
    id: "bisaya",
    name: "Bisaya",
    badge: "Mindanao & Visayas Community",
    greeting: "Maayong adlaw! Mangaon ug mag-Ngaon ta.",
    greetingTranslation: "Good day! Let’s eat and get moving with Ngaon.",
    tagline: "Where “Ngaon” means “kumain” or “to eat.” “Mukaon” also means “to eat.”",
    summary:
      "Bringing the warmth of “Mangaon ta!” (Let’s eat!) and “Mukaon” (to eat) into the app, Bisaya dialect features make ordering food, chatting with riders, and checking delivery updates effortless.",
    servicePhrases: [
      { service: "Ride", phrase: "Sakay na ta", meaning: "Hop on a quick, reliable motorcycle ride" },
      { service: "Food", phrase: "Ngaon / Mangaon ta!", meaning: "Kumain—order delicious meals to enjoy together" },
      { service: "Pabili", phrase: "Palihug ko’g palit", meaning: "Let a rider handle your grocery and errand list" },
      { service: "Padala", phrase: "Padala og pakete", meaning: "Send packages and essentials across town" },
    ],
    chatPresets: [
      { speaker: "Customer", local: "Naa na ko sa gawas, duol sa gate.", english: "I’m outside now, near the gate." },
      { speaker: "Rider", local: "Padulong na ko diha, hapit na.", english: "I’m heading your way, almost there." },
      { speaker: "Merchant", local: "Andam na ang imong gi-order nga pagkaon!", english: "Your food order is ready to go!" },
    ],
  },
];

export const dialectCapabilities = [
  {
    title: "Interface in your own tongue",
    description: "Switch between English, Sinama, Tausug, and Bisaya so key menus, status updates, and prompts speak the language you use at home.",
  },
  {
    title: "One-tap dialect chat presets",
    description: "Riders, customers, and merchants can send quick Sinama, Tausug, or Bisaya updates for landmarks, prep times, and arrivals.",
  },
  {
    title: "Built for local landmarks",
    description: "Designed around how Bongao residents naturally describe places, wharves, public markets, and neighborhood corners.",
  },
] as const;

export const services = [
  { id: "ride", title: "Ride", label: "Sinama: “To get a ride.”", description: "Motorcycle ride booking with pickup, drop-off, fare quotes, and tracking across Bongao.", detail: "Your pickup. Your destination.", icon: "bike" },
  { id: "food", title: "Food", label: "Bisaya: “Kumain — to eat.”", description: "Browse local merchants, choose meals, customize orders, and bring comfort food home.", detail: "From their kitchen to your door.", icon: "utensils" },
  { id: "pabili", title: "Pabili", label: "Sinama: “To grab for you.”", description: "Create a shopping list, set an item budget, and approve the rider’s receipt total.", detail: "Your list, with a helping hand.", icon: "basket" },
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

// Real screenshots from the Android apps (light + dark), captured from the
// current builds. Files live in public/screens/<id>-light.webp / -dark.webp.
const shot = (id: string, alt: string) => ({ light: `/screens/${id}-light.webp`, dark: `/screens/${id}-dark.webp`, width: 600, height: 1335, alt });

export const appScreens: AppScreen[] = [
  { id: "customer-home", role: "customer", kind: "home", title: "Your day starts here.", description: "Ride, Food, Pabili, and Padala together on one home screen, with your saved places one tap away.", image: shot("customer-home", "Ngaon customer app home screen with the four services"), video: { light: "/video/hero-light", dark: "/video/hero-dark" } },
  { id: "customer-food", role: "customer", kind: "food", title: "From local kitchens.", description: "Browse shops and dishes near you, filter by what’s open or fastest, and order in a few taps.", image: shot("customer-food", "Ngaon Food screen listing nearby restaurants") },
  { id: "customer-store", role: "customer", kind: "food", title: "A whole menu in your hand.", description: "Every dish with a photo, a short description and its price, grouped the way the kitchen serves them.", image: shot("customer-store", "Kusina ni Juan menu in the Ngaon app with rice meals and noodles") },
  { id: "customer-pabili", role: "customer", kind: "pabili", title: "Your list. A helping hand.", description: "Write your shopping list and pick the store. Your rider buys it and sends the receipt for you to approve.", image: shot("customer-pabili", "Ngaon Pabili screen with store, drop-off, and shopping list") },
  { id: "customer-padala", role: "customer", kind: "padala", title: "Send with care.", description: "The rider picks up the parcel from you and delivers it to your recipient, who you can keep updated.", image: shot("customer-padala", "Ngaon Padala screen with pickup, drop-off, and recipient") },
  { id: "rider-offer", role: "rider", kind: "rider", title: "A job, right on the map.", description: "New offers slide up over your map with what you earn, the pickup distance, the trip, and a countdown. Slide to accept.", image: shot("book-rider-offer", "Ngaon Rider job offer with earnings and slide to accept") },
  { id: "rider-pickup", role: "rider", kind: "riderActive", title: "Every step, in order.", description: "Head to the store with one-tap navigation, see what to collect, and move the job along with one big button.", image: shot("book-rider-job", "Ngaon Rider active job heading to the store") },
  { id: "rider-dropoff", role: "rider", kind: "riderActive", title: "Straight to the customer.", description: "After pickup the route switches to the drop-off, with the amount to collect and quick chat or call.", image: shot("book-rider-dropoff", "Ngaon Rider on the way to the drop-off") },
  { id: "rider-proof", role: "rider", kind: "riderActive", title: "Proof at the door.", description: "Snap a photo of the delivered order to complete the job, so everyone knows it arrived.", image: shot("book-rider-proof", "Ngaon Rider proof of delivery photo step") },
  { id: "rider-done", role: "rider", kind: "riderActive", title: "Job done.", description: "Delivered and paid. Back to the map for the next offer.", image: shot("book-rider-done", "Ngaon Rider job complete screen") },
  { id: "rider-earnings", role: "rider", kind: "riderEarnings", title: "Your work, in view.", description: "Today, this week, or any dates: earnings, trips, best day, and a daily chart. Export it all to PDF.", image: shot("rider-earnings", "Ngaon Rider earnings screen with weekly total and daily chart") },
  { id: "rider-wallet", role: "rider", kind: "riderEarnings", title: "Always ready to ride.", description: "See your commission balance and every top-up, earning, and commission in one place.", image: shot("rider-wallet", "Ngaon Rider wallet with balance and transactions") },
  { id: "merchant-new", role: "merchant", kind: "merchant", title: "Never miss an order.", description: "New orders pop up over any screen and ring until you answer: items, what you earn, prep time, and Accept.", image: shot("book-merchant-new", "Ngaon Merchant new order panel with accept and prep time") },
  { id: "merchant-board", role: "merchant", kind: "merchant", title: "Keep your kitchen connected.", description: "Pause or close the store with one tap and follow every order from new to ready.", image: shot("book-merchant-preparing", "Ngaon Merchant order board with an order being prepared") },
  { id: "merchant-order", role: "merchant", kind: "merchant", title: "Know who’s coming.", description: "Each order shows the rider assigned to pick it up and the match code, so food only leaves with the right rider.", image: shot("book-merchant-order", "Ngaon Merchant order page with the assigned rider") },
  { id: "merchant-menu", role: "merchant", kind: "merchantMenu", title: "Your menu, your way.", description: "Organise items into categories, switch anything to sold out, and add items right where they belong.", image: shot("merchant-menu", "Ngaon Merchant menu with categories and items") },
  { id: "merchant-sales", role: "merchant", kind: "merchant", title: "Know how you’re doing.", description: "Net earnings, orders, and a daily chart for today, this week, or any dates you choose.", image: shot("merchant-sales", "Ngaon Merchant sales screen with weekly earnings") },
];

/** One real food order, step by step (screens from the three apps). */
export const bookingSteps = [
  { id: "checkout", app: "Customer", title: "Check out", description: "Review the route, the price and where it’s going.", image: shot("book-checkout", "Food order checkout with route and price") },
  { id: "payment", app: "Customer", title: "Choose how to pay", description: "Cash, GCash, Maya, card or QR Ph.", image: shot("book-payment", "Payment options: cash, GCash, Maya, card and QR Ph") },
  { id: "store", app: "Merchant", title: "The store accepts", description: "The kitchen gets the order instantly and sets a prep time.", image: shot("book-merchant-new", "Store receives the new order and accepts it") },
  { id: "finding", app: "Customer", title: "Finding a rider", description: "Ngaon offers the job to the nearest verified rider.", image: shot("book-finding", "Customer sees the store preparing and a rider being found") },
  { id: "offer", app: "Rider", title: "A rider accepts", description: "The rider sees the earnings and route, and slides to accept.", image: shot("book-rider-offer", "Rider receives and accepts the job offer") },
  { id: "coming", app: "Customer", title: "Rider on the way", description: "Follow the rider to the store, then on to you.", image: shot("book-rider-coming", "Customer tracks the rider heading to the store") },
  { id: "delivery", app: "Customer", title: "On the way to you", description: "Live route, arrival time, chat and call.", image: shot("book-on-the-way", "Customer tracks the order on the way") },
  { id: "rate", app: "Customer", title: "Delivered. Rate it.", description: "Rate the rider and the food in a few taps.", image: shot("book-rate", "Customer rates the rider and the food") },
];

export const faqs = [
  { question: "What does the name “Ngaon” mean?", answer: "Ngaon carries two everyday meanings close to home: in Sinama, it means “to get” or “to grab”—whether grabbing a motorcycle ride, getting errands done, or picking up a parcel. In Bisaya, it means “kumain” or “to eat.” “Mukaon” also means “to eat”—an everyday invitation to enjoy hot meals from local kitchens." },
  { question: "Does Ngaon support local dialects like Sinama, Tausug, and Bisaya?", answer: "Yes. Alongside English, Ngaon is built with local dialect features for Sinama, Tausug, and Bisaya—including localized service prompts, status updates, and one-tap rider-customer chat presets tailored for everyday communication in Bongao, Tawi-Tawi." },
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
