import { bookingSteps } from "@/content/site-content";
import { Reveal } from "./motion";
import { PhonePreview } from "./phone-preview";
import { SectionHeading } from "./ui";

/** One real food order, from checkout to rating, across the three apps. */
export function BookingSteps() {
  return (
    <section id="booking" tabIndex={-1} className="section booking-section" aria-labelledby="booking-heading">
      <div className="container">
        <Reveal>
          <SectionHeading
            centered
            eyebrow="A real order, step by step"
            title="How a food order works."
            description="Real screens from one order, from checkout to the doorstep, across the customer, store and rider apps."
            id="booking-heading"
          />
        </Reveal>
      </div>
      <ol className="booking-track" aria-label="Food order steps">
        {bookingSteps.map((step, i) => (
          <li key={step.id} className="booking-step">
            <Reveal delay={Math.min(i, 4) * 0.05}>
              <PhonePreview image={step.image} className="booking-phone" />
              <div className="booking-copy">
                <span className="booking-num">{String(i + 1).padStart(2, "0")}</span>
                <span className={`booking-app booking-app-${step.app.toLowerCase()}`}>{step.app}</span>
                <h3>{step.title}</h3>
                <p>{step.description}</p>
              </div>
            </Reveal>
          </li>
        ))}
      </ol>
    </section>
  );
}
