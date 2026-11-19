"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Muted, looping app screen recording that reliably plays across Chrome and Brave
 * (including under Brave Autoplay Blocker, Linux Wayland VA-API, and simple static
 * HTTP servers without Range request support).
 *
 * Layers a native 30fps <video> (H.264 MP4 + VP9 WebM, 540x1200 yuv420p bt709)
 * over an always-animating WebP screen recording so the phone preview never
 * freezes on a static frame or shows a dead play button.
 */
export function AutoplayVideo({ base, poster, className, width, height, label, eager }: {
  base: string; poster: string; className: string; width: number; height: number; label: string; eager?: boolean;
}) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const [videoPlaying, setVideoPlaying] = useState(false);

  useEffect(() => {
    const v = videoRef.current;
    const wrap = wrapRef.current;
    if (!v || !wrap) return;

    v.muted = true;
    v.defaultMuted = true;
    v.playsInline = true;
    v.loop = true;

    let lastTime = -1;
    let stallTimer: ReturnType<typeof setInterval> | null = null;

    const isVisibleTheme = () => wrap.offsetParent !== null && getComputedStyle(wrap).display !== "none";

    const tryPlay = () => {
      if (!isVisibleTheme()) return;
      v.muted = true;
      const p = v.play();
      if (p !== undefined) {
        p.catch(() => {
          setVideoPlaying(false);
        });
      }
    };

    const onReady = () => tryPlay();
    const onTimeUpdate = () => {
      if (!v.paused && !v.ended && v.currentTime > 0.05) {
        setVideoPlaying(true);
      }
    };
    const onStop = () => setVideoPlaying(false);
    const onEnded = () => {
      v.currentTime = 0;
      tryPlay();
    };

    v.addEventListener("loadedmetadata", onReady);
    v.addEventListener("loadeddata", onReady);
    v.addEventListener("canplay", onReady);
    v.addEventListener("timeupdate", onTimeUpdate);
    v.addEventListener("pause", onStop);
    v.addEventListener("stalled", onStop);
    v.addEventListener("waiting", onStop);
    v.addEventListener("error", onStop);
    v.addEventListener("ended", onEnded);

    tryPlay();

    // Watchdog: if <video> stops advancing (e.g. loop stall on HTTP/1.0 server),
    // try restarting or fall back seamlessly to the animated WebP layer below.
    stallTimer = setInterval(() => {
      if (!isVisibleTheme()) return;
      if (!v.paused && !v.ended) {
        if (v.currentTime === lastTime) {
          setVideoPlaying(false);
          tryPlay();
        } else {
          lastTime = v.currentTime;
        }
      }
    }, 800);

    const io = new IntersectionObserver(
      (entries) => entries.forEach((e) => (e.isIntersecting ? tryPlay() : v.pause())),
      { threshold: 0.1 }
    );
    io.observe(wrap);

    const mo = new MutationObserver(() => requestAnimationFrame(tryPlay));
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

    const mq = matchMedia("(prefers-color-scheme: dark)");
    mq.addEventListener("change", tryPlay);

    const onVis = () => {
      if (document.visibilityState === "visible") tryPlay();
    };
    document.addEventListener("visibilitychange", onVis);

    return () => {
      if (stallTimer) clearInterval(stallTimer);
      v.removeEventListener("loadedmetadata", onReady);
      v.removeEventListener("loadeddata", onReady);
      v.removeEventListener("canplay", onReady);
      v.removeEventListener("timeupdate", onTimeUpdate);
      v.removeEventListener("pause", onStop);
      v.removeEventListener("stalled", onStop);
      v.removeEventListener("waiting", onStop);
      v.removeEventListener("error", onStop);
      v.removeEventListener("ended", onEnded);
      io.disconnect();
      mo.disconnect();
      mq.removeEventListener("change", tryPlay);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [base]);

  return (
    <div ref={wrapRef} className={className} style={{ position: "relative", width: "100%", height: "100%" }}>
      {/* eslint-disable-next-line @next/next/no-img-element -- animated WebP screen recording base layer guarantees playback in Brave & Chrome */}
      <img
        src={`${base}.webp`}
        alt={label}
        width={width}
        height={height}
        className="actual-screenshot"
        style={{ width: "100%", height: "100%", display: "block", objectFit: "cover" }}
        loading={eager ? "eager" : "lazy"}
        fetchPriority={eager ? "high" : "auto"}
        decoding="async"
        draggable={false}
      />
      <video
        ref={videoRef}
        className="actual-screenshot"
        poster={poster}
        width={width}
        height={height}
        autoPlay
        muted
        loop
        playsInline
        preload={eager ? "auto" : "metadata"}
        aria-label={label}
        disablePictureInPicture
        style={{
          position: "absolute",
          inset: 0,
          width: "100%",
          height: "100%",
          objectFit: "cover",
          opacity: videoPlaying ? 1 : 0,
          transition: "opacity 160ms ease",
          pointerEvents: "none",
        }}
      >
        <source src={`${base}.mp4`} type="video/mp4" />
        <source src={`${base}.webm`} type="video/webm" />
      </video>
    </div>
  );
}
