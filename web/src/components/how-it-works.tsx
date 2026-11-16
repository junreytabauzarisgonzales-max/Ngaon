import { CircleCheck, Grid2X2, MapPin, Route } from "lucide-react";
import { workflow } from "@/content/site-content";
import { Reveal, WorkflowConnector } from "./motion";
import { SectionHeading } from "./ui";

const icons = { grid: Grid2X2, pin: MapPin, check: CircleCheck, route: Route };

export function HowItWorks() {
  return <section id="how-it-works" tabIndex={-1} className="section workflow-section" aria-labelledby="workflow-heading"><div className="container">
    <Reveal><SectionHeading centered eyebrow="Simple by design" title="From your first tap to the final stop." description="A few clear steps. A little less to think about." id="workflow-heading" /></Reveal>
    <ol className="workflow-grid">{workflow.map((step, index) => { const Icon = icons[step.icon]; return <li key={step.title}><Reveal delay={index * 0.08}><div className="workflow-step-top"><span className="workflow-step-icon"><Icon size={25} strokeWidth={1.5} aria-hidden="true" /><span>0{index + 1}</span></span>{index < 3 && <WorkflowConnector />}</div><h3>{step.title}</h3><p>{step.description}</p></Reveal></li>; })}</ol>
    <Reveal><div className="workflow-footnote"><span className="eyebrow">Every service, thoughtfully connected</span><p><strong>Food</strong> includes merchant acceptance and preparation. <strong>Pabili</strong> includes approval of the receipt total before delivery continues. For Food, Pabili, and Padala, riders submit proof of delivery at completion.</p></div></Reveal>
  </div></section>;
}
