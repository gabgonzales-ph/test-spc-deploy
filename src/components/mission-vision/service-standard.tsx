//src/components/mission-vision/service-standard.tsx

"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import Image from "next/image";
import { motion, AnimatePresence, type PanInfo } from "framer-motion";
import { ChevronLeft, ChevronRight } from "lucide-react";
import type { ServiceStandard } from "@/hooks/useServiceStandard";

interface ServiceStandardStackProps {
  standards: ServiceStandard[];
  autoPlayMs?: number;
}

const SWIPE_THRESHOLD = 60;
const SWIPE_VELOCITY = 400;
const FALLBACK_IMAGE = "/";

export default function ServiceStandardStack({
  standards,
  autoPlayMs = 2500,
}: ServiceStandardStackProps) {
  const [index, setIndex] = useState(0);
  const [direction, setDirection] = useState<1 | -1>(1);
  const [paused, setPaused] = useState(false);
  const [hintPlayed, setHintPlayed] = useState(false);
  const wasDragged = useRef(false);

  const total = standards.length;

  const next = useCallback(() => {
    setDirection(1);
    setIndex((prev) => (prev + 1) % total);
  }, [total]);

  const prev = useCallback(() => {
    setDirection(-1);
    setIndex((current) => (current - 1 + total) % total);
  }, [total]);

  useEffect(() => {
    if (paused || total === 0) return;
    const timer = setInterval(next, autoPlayMs);
    return () => clearInterval(timer);
  }, [next, autoPlayMs, paused, total]);

  useEffect(() => {
    const timer = setTimeout(() => setHintPlayed(true), 1200);
    return () => clearTimeout(timer);
  }, []);

  if (total === 0) return null;

  const cardVariants = {
    initial: (dir: 1 | -1) => ({
      opacity: 0,
      x: dir === 1 ? 80 : -80,
      scale: 0.92,
      rotate: dir === 1 ? 2 : -2,
    }),
    animate: (_dir: 1 | -1) =>
      hintPlayed
        ? { opacity: 1, x: 0, scale: 1, rotate: 0 }
        : {
            opacity: [0, 1, 1, 1, 1],
            x: [80, 0, -18, 10, 0],
            scale: [0.92, 1, 1, 1, 1],
            rotate: [2, 0, 0, 0, 0],
          },
    exit: (dir: 1 | -1) => ({
      opacity: 0,
      x: dir === 1 ? -100 : 100,
      scale: 0.95,
      rotate: dir === 1 ? -3 : 3,
    }),
  };

  const handleDragEnd = (
    _event: MouseEvent | TouchEvent | PointerEvent,
    info: PanInfo
  ) => {
    const { offset, velocity } = info;
    if (offset.x < -SWIPE_THRESHOLD || velocity.x < -SWIPE_VELOCITY) {
      wasDragged.current = true;
      next();
    } else if (offset.x > SWIPE_THRESHOLD || velocity.x > SWIPE_VELOCITY) {
      wasDragged.current = true;
      prev();
    }
    setTimeout(() => {
      wasDragged.current = false;
    }, 50);
  };

  const handleClick = () => {
    if (wasDragged.current) return;
    next();
  };

  const behind = [1, 2].map((offset) => standards[(index + offset) % total]);
  const activeImage = standards[index].image_url ?? FALLBACK_IMAGE;
  const prevImage = standards[(index - 1 + total) % total].image_url ?? FALLBACK_IMAGE;
  const nextImage = standards[(index + 1) % total].image_url ?? FALLBACK_IMAGE;

  return (
    <div className="grid grid-cols-1 md:grid-cols-1 gap-0 md:gap-0 items-center">
      {/* Image column - fixed aspect-ratio box so swapping images never shifts layout */}
      {/* <div className="flex justify-center">
        <div className="relative w-full max-w-[480px] sm:max-w-[650px] aspect-[11/13]">
          <Image
            key={activeImage}
            src={activeImage}
            alt={`Service standard ${index + 1}`}
            fill
            sizes="(max-width: 640px) 400px, 550px"
            className="object-contain"
            priority
          />

          <Image
            key={`preload-prev-${prevImage}`}
            src={prevImage}
            alt=""
            fill
            aria-hidden="true"
            loading="eager"
            className="object-contain opacity-0 pointer-events-none"
          />
          <Image
            key={`preload-next-${nextImage}`}
            src={nextImage}
            alt=""
            fill
            aria-hidden="true"
            loading="eager"
            className="object-contain opacity-0 pointer-events-none"
          />
        </div>
      </div> */}

      {/* Cards column */}
      <div className="relative mx-auto w-full max-w-2xl overflow-hidden px-4 sm:px-6">
        <div className="relative h-80 sm:h-72 isolate touch-none">
          {/* Back cards */}
          {behind.map((_, i) => {
            const depth = i + 1;
            return (
              <div
                key={`${index}-behind-${depth}`}
                className="absolute inset-y-0 right-4 left-4 sm:right-0 sm:left-auto rounded-2xl border border-border bg-card shadow-sm transition-all duration-300"
                style={{
                  width: "calc(100% - 32px)",
                  transform: `translateX(-${depth * 12}px) scale(${1 - depth * 0.04})`,
                  opacity: 1 - depth * 0.35,
                  zIndex: 10 - depth,
                }}
              />
            );
          })}

          {/* Active card */}
          <AnimatePresence mode="popLayout" custom={direction}>
            <motion.div
              key={index}
              custom={direction}
              variants={cardVariants}
              initial="initial"
              animate="animate"
              exit="exit"
              transition={
                hintPlayed
                  ? { type: "spring", stiffness: 260, damping: 24 }
                  : { duration: 1.2, ease: "easeInOut" }
              }
              drag="x"
              dragConstraints={{ left: 0, right: 0 }}
              dragElastic={0.5}
              onDragEnd={handleDragEnd}
              onClick={handleClick}
              onPointerDown={() => setPaused(true)}
              onPointerUp={() => setPaused(false)}
              onPointerCancel={() => setPaused(false)}
              whileTap={{ cursor: "grabbing" }}
              className="absolute inset-0 z-20 flex h-full cursor-grab flex-col justify-between rounded-2xl border border-border bg-card p-6 sm:p-10 shadow-lg active:cursor-grabbing select-none"
            >
              {/* Top row: star + swipe hint */}
              <div className="flex items-center justify-between">
                <span className="flex h-14 w-14 items-center justify-center rounded-full bg-primary/10 text-primary text-3xl font-semibold">
                  {String(index + 1).padStart(2, "0")}
                </span>

                {/* Swipe hint */}
                <div className="flex items-center gap-1 select-none">
                  <motion.div
                    animate={{ x: [0, -4, 0] }}
                    transition={{
                      duration: 1.6,
                      repeat: Infinity,
                      ease: "easeInOut",
                      repeatDelay: 1,
                    }}
                  >
                    <ChevronLeft className="h-4 w-4 text-muted-foreground/50" />
                  </motion.div>
                  <span className="text-[11px] font-medium uppercase tracking-widest text-muted-foreground/50">
                    swipe
                  </span>
                  <motion.div
                    animate={{ x: [0, 4, 0] }}
                    transition={{
                      duration: 1.6,
                      repeat: Infinity,
                      ease: "easeInOut",
                      repeatDelay: 1,
                    }}
                  >
                    <ChevronRight className="h-4 w-4 text-muted-foreground/50" />
                  </motion.div>
                </div>
              </div>

              <p
                className="pointer-events-none text-base font-medium leading-relaxed text-foreground sm:text-2xl"
                aria-live="polite"
              >
                {standards[index].description}
              </p>

              {/* Bottom row: counter + drag handle dots */}
              <div className="flex items-center justify-between">
                <span className="pointer-events-none text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Standard {index + 1} of {total}
                </span>
                <div className="flex gap-1">
                  {[0, 1, 2].map((d) => (
                    <div
                      key={d}
                      className="h-1 w-1 rounded-full bg-muted-foreground/30"
                    />
                  ))}
                </div>
              </div>
            </motion.div>
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}