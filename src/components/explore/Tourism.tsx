// src/components/explore/Tourism.tsx
"use client";

import React, { useState } from "react";
import { AnimatePresence, motion, type Variants } from "framer-motion";
import { Calendar, Sparkles, ArrowUpRight, Heart } from "lucide-react";
import type { TourismHighlight, TourismCategory } from "@/data/tourism/tourism";
import { useTourismHighlights } from "@/hooks/useTourism";
import ViewMoreButton from "./tourism/ViewMoreButton";

/* -------------------------------------------------------------------------
   Category presets — since gradient/icon aren't stored in the DB, each
   category gets a small rotation of looks so cards in the same category
   still feel distinct from one another rather than identical.
------------------------------------------------------------------------- */

const CATEGORY_PRESETS: Record<
  TourismCategory,
  { icon: React.ElementType; badgeLabel: string; gradients: string[] }
> = {
  festival: {
    icon: Sparkles,
    badgeLabel: "Festival",
    gradients: [
      "from-orange-500/90 via-amber-500/70 to-teal-600/80",
      "from-teal-700/90 via-teal-600/70 to-orange-500/70",
      "from-rose-500/90 via-orange-500/70 to-amber-500/70",
    ],
  },
  program: {
    icon: Heart,
    badgeLabel: "City Program",
    gradients: [
      "from-pink-600/90 via-fuchsia-500/70 to-indigo-600/80",
      "from-indigo-600/90 via-violet-500/70 to-pink-500/70",
    ],
  },
};

function getPreset(category: TourismCategory, indexWithinCategory: number) {
  const preset = CATEGORY_PRESETS[category];
  const gradient =
    preset.gradients[indexWithinCategory % preset.gradients.length];
  return { icon: preset.icon, badgeLabel: preset.badgeLabel, gradient };
}

const VISIBLE_COUNT = 3;

const cardReveal: Variants = {
  hidden: { opacity: 0, y: 40 },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: "easeOut", delay: i * 0.12 },
  }),
};

function HighlightCard({
  item,
  index,
  categoryIndex,
}: {
  item: TourismHighlight;
  index: number;
  categoryIndex: number;
}) {
  const { icon: Icon, badgeLabel, gradient } = getPreset(item.category, categoryIndex);

  return (
    <motion.a
      href={item.href}
      // Same-tab navigation by design — these are official city sub-sites,
      // not third-party links, so keeping the visitor in the same tab
      // matches how the rest of the site navigates.
      rel="noopener"
      custom={index}
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, amount: 0.3 }}
      variants={cardReveal}
      whileHover="hover"
      className="group relative block w-full overflow-hidden rounded-sm border border-emerald-100 shadow-sm hover:shadow-2xl transition-shadow duration-300"
    >
      <div className="relative h-64 md:h-80 w-full bg-slate-900">
        <motion.div
          className="absolute inset-0"
          variants={{ hover: { scale: 1.06 } }}
          transition={{ duration: 0.5, ease: "easeOut" }}
        >
          {item.image ? (
            <img
              src={item.image}
              alt={item.name}
              loading="lazy"
              className="absolute inset-0 w-full h-full object-cover"
            />
          ) : null}
        </motion.div>

        {/* Category-colored gradient wash, deepest at the bottom so text
            always stays legible regardless of the source banner's own
            contrast. */}
        <div
          className={`absolute inset-0 bg-gradient-to-t ${gradient} mix-blend-multiply`}
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/10 to-transparent" />

        {/* Content */}
        <div className="relative h-full flex flex-col justify-end p-6 md:p-8 text-white">
          <div className="flex items-center gap-2 mb-3">
            {item.date ? (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-white/20 backdrop-blur-sm px-3 py-1 text-xs font-medium">
                <Calendar className="w-3.5 h-3.5" />
                {item.date}
              </span>
            ) : (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-white/20 backdrop-blur-sm px-3 py-1 text-xs font-medium">
                <Icon className="w-3.5 h-3.5" />
                {badgeLabel}
              </span>
            )}
          </div>

          <h3 className="text-2xl md:text-3xl font-bold leading-tight mb-2">
            {item.name}
          </h3>
          <p className="text-sm md:text-base text-white/85 max-w-xl">
            {item.tagline}
          </p>

          <motion.div
            className="mt-5 inline-flex items-center gap-2 w-fit rounded-full bg-white text-gray-900 px-4 py-2 text-sm font-semibold"
            variants={{ hover: { gap: "0.75rem" } }}
            transition={{ duration: 0.25 }}
          >
            Visit site
            <motion.span
              className="inline-flex"
              variants={{ hover: { x: 3, y: -3 } }}
              transition={{ duration: 0.25 }}
            >
              <ArrowUpRight className="w-4 h-4" />
            </motion.span>
          </motion.div>
        </div>
      </div>
    </motion.a>
  );
}

// Assigns each highlight its position *within its own category* so the
// gradient rotation in getPreset() varies card-to-card instead of every
// festival (or every program) reusing the same look.
function withCategoryIndex(items: TourismHighlight[]) {
  const counters: Partial<Record<TourismCategory, number>> = {};
  return items.map((item) => {
    const categoryIndex = counters[item.category] ?? 0;
    counters[item.category] = categoryIndex + 1;
    return { item, categoryIndex };
  });
}

export default function Tourism() {
  const { highlights, loading, error, isStale } = useTourismHighlights();
  const [showAll, setShowAll] = useState(false);

  const indexed = withCategoryIndex(highlights);
  const visibleHighlights = indexed.slice(0, VISIBLE_COUNT);
  const hiddenHighlights = indexed.slice(VISIBLE_COUNT);
  const hasMore = hiddenHighlights.length > 0;

  return (
    <div className="w-full">
      <div className="text-center mb-10">
        <div className="inline-flex items-center justify-center w-16 h-16 md:w-20 md:h-20 bg-emerald-100 rounded-2xl mb-6">
          <Sparkles className="w-8 h-8 md:w-10 md:h-10 text-emerald-700" />
        </div>
        <h2 className="text-3xl md:text-4xl font-bold mb-4">Tourism</h2>
        <p className="text-gray-600 text-base md:text-lg">
          Festivals, celebrations, and programs shaping San Pablo City
        </p>
      </div>

      {isStale && (
        <p className="text-center text-xs text-amber-700 mb-4">
          Showing saved data — reconnecting…
        </p>
      )}

      {loading && highlights.length === 0 && (
        <p className="text-center text-sm text-gray-500">Loading highlights…</p>
      )}

      {!loading && error && highlights.length === 0 && (
        <p className="text-center text-sm text-gray-500">
          Couldn&apos;t load tourism highlights right now. Please try again shortly.
        </p>
      )}

      {highlights.length > 0 && (
        <div className="max-w-6xl mx-auto">
          {visibleHighlights.map(({ item, categoryIndex }, index) => (
            <HighlightCard
              key={item.id}
              item={item}
              index={index}
              categoryIndex={categoryIndex}
            />
          ))}

          <AnimatePresence initial={false}>
            {showAll && (
              <motion.div
                key="more-highlights"
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ duration: 0.4, ease: "easeOut" }}
                className="space-y-6 md:space-y-8 overflow-hidden"
              >
                {hiddenHighlights.map(({ item, categoryIndex }, index) => (
                  <HighlightCard
                    key={item.id}
                    item={item}
                    index={index}
                    categoryIndex={categoryIndex}
                  />
                ))}
              </motion.div>
            )}
          </AnimatePresence>

          {hasMore && (
            <ViewMoreButton
              expanded={showAll}
              onToggle={() => setShowAll((prev) => !prev)}
            />
          )}
        </div>
      )}
    </div>
  );
}