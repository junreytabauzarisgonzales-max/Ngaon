export type LegalSection = {
  id: string;
  heading: string;
  paragraphs?: string[];
  bullets?: string[];
};

export const legalReviewNote = "Starter policy for review. Confirm the effective date, contact details, legal entity, data practices, and governing law before relying on this policy.";

export const termsSections: LegalSection[] = [
  {
    id: "acceptance",
    heading: "1. About these terms",
    paragraphs: [
      "These Terms of Service describe the rules for using the Ngaon website and the Ngaon Customer, Rider, and Merchant applications. By accessing or using a Ngaon service, you agree to these terms and any service-specific instructions shown in the application.",
      "If you do not agree with these terms, do not use the website or applications. Additional terms may apply to a particular booking, order, delivery, or account feature.",
    ],
  },
  {
    id: "eligibility",
    heading: "2. Eligibility and accounts",
    paragraphs: [
      "You must provide accurate information and keep your account information current. You are responsible for activity performed through your account and for keeping account credentials secure.",
      "The services are intended for people who can legally enter into an agreement. If you use Ngaon on behalf of another person or business, you confirm that you are authorized to do so.",
    ],
  },
  {
    id: "services",
    heading: "3. Services and bookings",
    paragraphs: [
      "Ngaon brings together Ride, Food, Pabili, and Padala workflows through connected applications. Actual availability, service areas, prices, estimated times, and participating providers are determined in the application and may change.",
      "A request is not necessarily accepted until the application confirms it. Details entered by a customer, rider, or merchant should be complete and accurate so that the service can be performed safely and correctly.",
    ],
  },
  {
    id: "payments",
    heading: "4. Fares, payments, and receipts",
    paragraphs: [
      "Where payment features are available, the application will show the applicable fare, fee, estimate, or payment instructions before confirmation where practical. Prices and totals may change when the details of a request change.",
      "For Pabili requests, the rider may submit a receipt and item total for customer approval before continuing. The application may distinguish service fees from the actual cost of purchased items.",
      "Payment methods, refunds, cancellation charges, and settlement timing may depend on the service, the selected payment method, and the instructions shown in the application.",
    ],
  },
  {
    id: "responsibilities",
    heading: "5. User responsibilities",
    bullets: [
      "Use the services lawfully and provide information that is accurate, complete, and not misleading.",
      "Treat customers, riders, merchants, delivery recipients, and support personnel respectfully.",
      "Do not use Ngaon to request, transport, sell, or deliver anything unlawful, unsafe, stolen, or prohibited by the application.",
      "Do not interfere with the website, applications, accounts, safety systems, or payment flows.",
      "Do not copy, reverse engineer, scrape, resell, or misuse the website or applications except where applicable law permits it.",
    ],
  },
  {
    id: "availability",
    heading: "6. Availability and changes",
    paragraphs: [
      "Ngaon may update, suspend, restrict, or discontinue a feature, service, application, or part of the website. Service availability may be affected by location, demand, weather, connectivity, provider availability, maintenance, or circumstances outside Ngaon's control.",
      "The website is a product introduction. It does not guarantee that a particular service, rider, merchant, payment method, delivery time, or booking option is available at a particular moment.",
    ],
  },
  {
    id: "intellectual-property",
    heading: "7. Content and intellectual property",
    paragraphs: [
      "The Ngaon name, logos, illustrations, written content, interface designs, and other website materials belong to Ngaon or its licensors unless stated otherwise. You may use the website for personal or internal informational purposes only.",
      "You retain rights in information and content you submit, but grant Ngaon the permissions reasonably needed to operate, improve, secure, and provide the requested service.",
    ],
  },
  {
    id: "disclaimers",
    heading: "8. Disclaimers and liability",
    paragraphs: [
      "To the extent permitted by law, the website and services are provided on an as-available basis. Ngaon does not promise that the website or every service will always be uninterrupted, error-free, secure, or available in every location.",
      "To the extent permitted by law, Ngaon is not responsible for indirect, incidental, special, consequential, or unforeseeable losses arising from use of the website or services. Nothing in these terms excludes a responsibility that cannot lawfully be excluded.",
    ],
  },
  {
    id: "changes",
    heading: "9. Changes and termination",
    paragraphs: [
      "Ngaon may update these terms when the services, laws, or operating practices change. The updated version will be posted on this page with a new review date where appropriate. Continued use after an update means you accept the updated terms.",
      "Ngaon may suspend or close an account, or restrict access to a service, when reasonably necessary for safety, security, legal compliance, non-payment, or a breach of these terms.",
    ],
  },
  {
    id: "contact",
    heading: "10. Contact and governing law",
    paragraphs: [
      "Contact details and the governing-law jurisdiction should be added here by the Ngaon owner before publication. Do not rely on this starter policy as a substitute for legal advice or a final agreement.",
    ],
  },
];

export const privacySections: LegalSection[] = [
  {
    id: "scope",
    heading: "1. Scope of this policy",
    paragraphs: [
      "This Privacy Policy explains how Ngaon may handle information when you visit the Ngaon website or use a Ngaon Customer, Rider, or Merchant application. It is written as a general starter policy and must be checked against the actual data flows, vendors, and legal requirements before publication.",
      "Some features may not be available in every location or application. If a specific feature provides its own notice, that notice also applies.",
    ],
  },
  {
    id: "information",
    heading: "2. Information that may be collected",
    bullets: [
      "Contact and account information, such as your name, phone number, email address, profile details, and login information.",
      "Service information, such as pickup and drop-off locations, delivery details, shopping lists, order details, recipient information, receipts, and booking status.",
      "Location information when a location-enabled feature is used or permission is granted, including location needed for pickup, delivery, navigation, or tracking.",
      "Payment and transaction information needed to show fares, process payments, reconcile orders, or handle refunds. Payment credentials should be handled by the relevant payment provider where applicable.",
      "Device, technical, and usage information, such as IP address, browser or device type, operating system, application version, diagnostics, and interaction events.",
      "Messages, support requests, ratings, feedback, and other information you choose to send through the services.",
    ],
  },
  {
    id: "use",
    heading: "3. How information may be used",
    bullets: [
      "Provide, coordinate, personalize, and improve Ride, Food, Pabili, and Padala services.",
      "Connect customers, riders, merchants, and recipients where needed to complete a request.",
      "Show booking progress, location status, preparation updates, delivery proof, fares, receipts, and account activity.",
      "Authenticate accounts, prevent fraud or misuse, protect safety, troubleshoot issues, and maintain service security.",
      "Communicate about bookings, service changes, support requests, policy updates, and other operational matters.",
      "Meet legal obligations, resolve disputes, enforce agreements, and protect the rights and safety of Ngaon and other people.",
    ],
  },
  {
    id: "sharing",
    heading: "4. How information may be shared",
    paragraphs: [
      "Ngaon may share information with the customer, rider, merchant, or recipient involved in a request when it is needed to provide that request. Ngaon may also share information with service providers that support hosting, communications, payments, maps, analytics, customer support, security, or other operations.",
      "Information may be disclosed when required by law, legal process, or a valid request from an authority, or when reasonably necessary to prevent fraud, abuse, security incidents, or harm.",
      "Ngaon should not sell personal information as a commercial product. Confirm this statement against the actual business and vendor arrangements before publication.",
    ],
  },
  {
    id: "permissions",
    heading: "5. Location, notifications, and device permissions",
    paragraphs: [
      "The applications may request permissions such as location, notifications, camera, photos, or device storage when a feature needs them. You can usually manage permissions in your device settings, but disabling a permission may prevent that feature from working.",
      "The website is designed as a product introduction and should not be treated as a substitute for the privacy controls provided inside the applications.",
    ],
  },
  {
    id: "retention-security",
    heading: "6. Retention and security",
    paragraphs: [
      "Information should be kept only for as long as reasonably needed for the purposes described in this policy, including service delivery, records, safety, dispute handling, and legal obligations. Actual retention periods should be confirmed by the Ngaon owner.",
      "Ngaon uses reasonable administrative, technical, and organizational safeguards appropriate to the information handled. No online service can guarantee absolute security.",
    ],
  },
  {
    id: "rights",
    heading: "7. Your choices and rights",
    paragraphs: [
      "Depending on where you live, you may have rights to access, correct, delete, restrict, object to, or obtain a copy of certain personal information. You may also withdraw permissions or unsubscribe from non-essential communications where the service supports those controls.",
      "Requests should be sent to the official Ngaon privacy contact once one is supplied. Ngaon may need to verify identity and may retain information where the law or legitimate service needs require it.",
    ],
  },
  {
    id: "children",
    heading: "8. Children",
    paragraphs: [
      "The services are not intended for children who cannot lawfully use them. If you believe a child provided personal information improperly, contact Ngaon through the official privacy channel so the matter can be reviewed.",
    ],
  },
  {
    id: "updates-contact",
    heading: "9. Updates and contact",
    paragraphs: [
      "Ngaon may update this policy as the services, data practices, or legal requirements change. The latest version will be posted on this page.",
      "The Ngaon owner should add the effective date, legal entity, privacy contact, and applicable jurisdiction here before publication. This starter policy is not legal advice.",
    ],
  },
];
