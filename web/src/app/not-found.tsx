import { Brand, LinkButton } from "@/components/ui";

export default function NotFound() {
  return <main id="main" tabIndex={-1} className="not-found container"><Brand href="/" /><p className="eyebrow">A little off route</p><h1>Let’s get you<br />back home.</h1><p>This page isn’t here, but your everyday starts at Ngaon.</p><LinkButton href="/">Back to Ngaon</LinkButton></main>;
}
