"use client";

import { useState } from "react";
import {
  Languages,
  MessageSquareText,
  Motorbike,
  Package,
  ShoppingBasket,
  Sparkles,
  Utensils,
} from "lucide-react";
import {
  dialectCapabilities,
  dialectProfiles,
  nameMeanings,
  type DialectId,
} from "@/content/site-content";
import { Reveal } from "./motion";
import { IconBox, SectionHeading } from "./ui";

const serviceIcons = {
  Ride: Motorbike,
  Food: Utensils,
  Pabili: ShoppingBasket,
  Padala: Package,
} as const;

export function DialectFeature() {
  const [activeDialect, setActiveDialect] = useState<DialectId>("sinama");
  const current =
    dialectProfiles.find((d) => d.id === activeDialect) ?? dialectProfiles[0];

  return (
    <section
      id="dialects"
      tabIndex={-1}
      className="section dialect-section"
      aria-labelledby="dialects-heading"
    >
      <div className="container">
        <Reveal>
          <div className="heading-row">
            <SectionHeading
              eyebrow="Why we’re called Ngaon"
              title="One name. Two local meanings. Three local dialects."
              description="Rooted in the languages spoken every day across Bongao, Tawi-Tawi, and Mindanao."
              id="dialects-heading"
            />
            <p className="heading-aside">
              In Sinama: <strong>“to get or grab.”</strong>
              <br />
              In Bisaya: <strong>“kumain — to eat.”</strong>
            </p>
          </div>
        </Reveal>

        {/* Etymology cards: Sinama ("get/grab") & Bisaya ("kumain") */}
        <div className="meaning-grid">
          {nameMeanings.map((item, index) => (
            <Reveal key={item.id} delay={index * 0.07}>
              <article className={`meaning-card meaning-${item.id}`}>
                <div className="meaning-card-top">
                  <span className="meaning-badge">{item.language}</span>
                  <span className="meaning-tag">{item.tag}</span>
                </div>
                <p className="meaning-word">
                  ngaon <span>/ {item.meaning}</span>
                </p>
                <h3>{item.headline}</h3>
                <p className="meaning-description">{item.description}</p>
              </article>
            </Reveal>
          ))}
        </div>

        {/* Interactive Local Dialect Experience: Sinama, Tausug, Bisaya */}
        <Reveal delay={0.1}>
          <div className="dialect-panel">
            <div className="dialect-panel-header">
              <div>
                <p className="eyebrow">
                  <span />
                  Local dialect features · Sinama · Tausug · Bisaya
                </p>
                <h3>An app that speaks the languages of home.</h3>
                <p className="dialect-panel-sub">
                  Switch between <strong>Sinama</strong>, <strong>Tausug</strong>,
                  and <strong>Bisaya</strong> to preview how Ngaon brings local
                  dialect prompts, service actions, and rider-customer quick chat
                  into the everyday experience.
                </p>
              </div>
              <div
                className="dialect-tabs"
                role="tablist"
                aria-label="Choose a local dialect to preview"
              >
                {dialectProfiles.map((dialect) => {
                  const active = dialect.id === activeDialect;
                  return (
                    <button
                      key={dialect.id}
                      type="button"
                      role="tab"
                      aria-selected={active}
                      className={`dialect-tab${active ? " is-active" : ""}`}
                      onClick={() => setActiveDialect(dialect.id)}
                    >
                      <Languages size={14} aria-hidden="true" />
                      <span>{dialect.name}</span>
                    </button>
                  );
                })}
              </div>
            </div>

            <div className="dialect-stage" role="tabpanel" aria-live="polite">
              <div className="dialect-greeting-card">
                <div className="dialect-greeting-meta">
                  <span className="dialect-region-pill">
                    <Sparkles size={12} aria-hidden="true" />
                    {current.name} · {current.badge}
                  </span>
                  <span className="dialect-tagline">{current.tagline}</span>
                </div>
                <blockquote className="dialect-quote">
                  “{current.greeting}”
                </blockquote>
                <p className="dialect-translation">
                  {current.greetingTranslation}
                </p>
                <p className="dialect-summary">{current.summary}</p>

                <div className="dialect-chat-box">
                  <p className="dialect-chat-label">
                    <MessageSquareText size={14} aria-hidden="true" />
                    Quick {current.name} in-app chat presets
                  </p>
                  <div className="dialect-chat-list">
                    {current.chatPresets.map((chat) => (
                      <div key={chat.speaker} className="dialect-chat-item">
                        <span
                          className={`dialect-speaker speaker-${chat.speaker.toLowerCase()}`}
                        >
                          {chat.speaker}
                        </span>
                        <div>
                          <strong>“{chat.local}”</strong>
                          <span>{chat.english}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>

              <div className="dialect-services-col">
                <p className="dialect-col-title">
                  Everyday services in <strong>{current.name}</strong>
                </p>
                <div className="dialect-service-cards">
                  {current.servicePhrases.map((item) => {
                    const Icon = serviceIcons[item.service];
                    return (
                      <div
                        key={item.service}
                        className={`dialect-service-card svc-${item.service.toLowerCase()}`}
                      >
                        <IconBox icon={Icon} />
                        <div>
                          <span className="dialect-svc-name">
                            {item.service} · {current.name}
                          </span>
                          <h4>“{item.phrase}”</h4>
                          <p>{item.meaning}</p>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>

            <div className="dialect-capabilities">
              {dialectCapabilities.map((cap) => (
                <div key={cap.title} className="dialect-capability-item">
                  <h4>{cap.title}</h4>
                  <p>{cap.description}</p>
                </div>
              ))}
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
