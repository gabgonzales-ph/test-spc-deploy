//src/components/explore/ImageGallery.tsx

"use client";

import React, { useEffect, useMemo, useRef, useState } from "react";
import { ImageOff, X } from "lucide-react";
import { motion, type Variants } from "framer-motion";
import { Button } from "@/components/ui/button";
import { useAboutUs } from "@/hooks/useAboutUs";

// ---------------------------------------------------------------------------
// ImageGallery — CMS-driven, fetches from the "about-us" Supabase folder
// Uses plain <img> tags (not next/image) to avoid Vercel Image Optimization
// quota/billing — see NewsCard.tsx for the same change and rationale.
// ---------------------------------------------------------------------------

const imageFrameHoverClass =
  "transition-[box-shadow,filter,transform] duration-300 shadow-lg shadow-emerald-950/10 md:hover:ring-2 md:hover:ring-white md:hover:shadow-2xl md:hover:shadow-emerald-950/25 md:hover:drop-shadow-[0_18px_28px_rgba(6,78,59,0.28)] active:scale-[0.98]";

// Framer Motion Stagger Variants
const containerVariants: Variants = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.12, // Slight delay between each image's appearance
    },
  },
};

const itemVariants: Variants = {
  hidden: { opacity: 0, y: 24 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      duration: 0.5,
      ease: "easeOut",
    },
  },
};

export const ImageGallery = () => {
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);
  const [visibleCaptionIds, setVisibleCaptionIds] = useState<Set<string>>(
    () => new Set()
  );
  const touchStartX = useRef<number | null>(null);
  const photoRefs = useRef(new Map<string, HTMLDivElement>());
  const { photos, loading, error } = useAboutUs();
  const collagePhotos = useMemo(() => photos.slice(0, 6), [photos]);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const mobileQuery = window.matchMedia("(max-width: 767px)");
    let observer: IntersectionObserver | null = null;
    let animationFrame: number | null = null;

    // Recalculate which 2 images are currently most visible on the screen
    const refreshVisibleCaptions = () => {
      if (!mobileQuery.matches) {
        setVisibleCaptionIds((prev) => (prev.size === 0 ? prev : new Set()));
        return;
      }

      const visibilityData: { photoId: string; ratio: number }[] = [];

      collagePhotos.forEach((photo) => {
        const photoId = String(photo.photo_id);
        const node = photoRefs.current.get(photoId);
        if (!node) return;

        const rect = node.getBoundingClientRect();
        const visibleHeight =
          Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0);
        
        if (visibleHeight > 0) {
          const visibleRatio = visibleHeight / rect.height;
          visibilityData.push({ photoId, ratio: visibleRatio });
        }
      });

      // Sort by visibility ratio descending and take the top 2
      const topTwoIds = visibilityData
        .sort((a, b) => b.ratio - a.ratio)
        .slice(0, 2)
        .map((item) => item.photoId);

      // Value-based reference comparison to stop infinite loop crashes
      setVisibleCaptionIds((currentSet) => {
        if (currentSet.size === topTwoIds.length && topTwoIds.every((id) => currentSet.has(id))) {
          return currentSet; // Return old state reference; prevents infinite re-render loop
        }
        return new Set(topTwoIds);
      });
    };

    const requestRefresh = () => {
      if (animationFrame !== null) return;

      animationFrame = window.requestAnimationFrame(() => {
        animationFrame = null;
        refreshVisibleCaptions();
      });
    };

    const setupObservation = () => {
      observer?.disconnect();
      observer = null;

      if (!mobileQuery.matches) {
        setVisibleCaptionIds((prev) => (prev.size === 0 ? prev : new Set()));
        return;
      }

      // Use an intersection observer to prompt recalculations when elements cross thresholds
      observer = new IntersectionObserver(
        () => {
          requestRefresh();
        },
        { threshold: [0.1, 0.3, 0.5, 0.7] }
      );

      // Observe all photo nodes
      collagePhotos.forEach((photo) => {
        const node = photoRefs.current.get(String(photo.photo_id));
        if (node) observer?.observe(node);
      });

      refreshVisibleCaptions();
    };

    setupObservation();
    mobileQuery.addEventListener("change", setupObservation);
    window.addEventListener("scroll", requestRefresh, { passive: true });
    window.addEventListener("resize", requestRefresh);

    return () => {
      if (animationFrame !== null) {
        window.cancelAnimationFrame(animationFrame);
      }
      observer?.disconnect();
      mobileQuery.removeEventListener("change", setupObservation);
      window.removeEventListener("scroll", requestRefresh);
      window.removeEventListener("resize", requestRefresh);
    };
  }, [collagePhotos]);

  if (loading) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-3 animate-pulse">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="bg-emerald-100/60 aspect-[5/4]" />
        ))}
      </div>
    );
  }

  if (error || photos.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-gray-400 gap-1">
        <ImageOff className="w-10 h-10" />
        <p className="text-sm">
          {error ? "Failed to load photos." : "No photos available yet."}
        </p>
      </div>
    );
  }

  const selectedPhoto =
    selectedIndex !== null ? collagePhotos[selectedIndex] : null;
  const setPhotoRef =
    (photoId: string) => (node: HTMLDivElement | null) => {
      if (node) {
        photoRefs.current.set(photoId, node);
      } else {
        photoRefs.current.delete(photoId);
      }
    };
  const showPreviousPhoto = () => {
    setSelectedIndex((current) =>
      current === null
        ? current
        : (current - 1 + collagePhotos.length) % collagePhotos.length
    );
  };
  const showNextPhoto = () => {
    setSelectedIndex((current) =>
      current === null ? current : (current + 1) % collagePhotos.length
    );
  };
  const handleTouchEnd = (x: number) => {
    if (touchStartX.current === null) return;

    const distance = touchStartX.current - x;
    touchStartX.current = null;

    if (Math.abs(distance) < 50) return;
    if (distance > 0) {
      showNextPhoto();
    } else {
      showPreviousPhoto();
    }
  };

  return (
    <motion.div
      initial="hidden"
      whileInView="visible"
      viewport={{ once: true, amount: 0.15 }}
      variants={containerVariants}
    >
      {/* Row 1: 20% | 50% | 30% */}
      <div className="flex flex-col md:flex-row gap-1 mb-1">
        {([0, 1, 2] as const).map((index) => {
          const widthClasses = ["md:w-[20%]", "md:w-[50%]", "md:w-[30%]"] as const;
          const photo = collagePhotos[index];
          if (!photo) return null;
          const photoId = String(photo.photo_id);
          const captionIsVisible = visibleCaptionIds.has(photoId);
          return (
            <motion.div
              key={photo.photo_id}
              ref={setPhotoRef(photoId)}
              data-photo-id={photoId}
              variants={itemVariants}
              className={`relative group cursor-pointer overflow-hidden aspect-[16/9] w-full ${widthClasses[index]} md:flex-shrink-0 ${imageFrameHoverClass}`}
              onClick={() => setSelectedIndex(index)}
            >
              <img
                src={photo.url}
                alt={photo.caption ?? `San Pablo City photo ${index + 1}`}
                loading="lazy"
                className="absolute inset-0 w-full h-full object-cover"
              />
              {photo.caption && (
                <div
                  className={`absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-transparent pointer-events-none transition-all duration-500 ease-out md:opacity-0 md:translate-y-0 md:group-hover:opacity-100 ${
                    captionIsVisible
                      ? "opacity-100 translate-y-0"
                      : "opacity-0 translate-y-4"
                  }`}
                >
                  <p className="absolute bottom-4 left-5 right-5 max-h-16 overflow-y-auto text-white text-base md:text-md font-bold drop-shadow-md">{photo.caption}</p>
                </div>
              )}
            </motion.div>
          );
        })}
      </div>

      {/* Row 2: 50% | 30% | 20% */}
      <div className="flex flex-col md:flex-row gap-1">
        {([3, 4, 5] as const).map((index) => {
          const widthClasses = ["md:w-[50%]", "md:w-[30%]", "md:w-[20%]"] as const;
          const photo = collagePhotos[index];
          if (!photo) return null;
          const photoId = String(photo.photo_id);
          const captionIsVisible = visibleCaptionIds.has(photoId);
          return (
            <motion.div
              key={photo.photo_id}
              ref={setPhotoRef(photoId)}
              data-photo-id={photoId}
              variants={itemVariants}
              className={`relative group cursor-pointer overflow-hidden aspect-[16/9] w-full ${widthClasses[index - 3]} md:flex-shrink-0 ${imageFrameHoverClass}`}
              onClick={() => setSelectedIndex(index)}
            >
              <img
                src={photo.url}
                alt={photo.caption ?? `San Pablo City photo ${index + 1}`}
                loading="lazy"
                className="absolute inset-0 w-full h-full object-cover"
              />
              {photo.caption && (
                <div
                  className={`absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-transparent pointer-events-none transition-all duration-500 ease-out md:opacity-0 md:translate-y-0 md:group-hover:opacity-100 ${
                    captionIsVisible
                      ? "opacity-100 translate-y-0"
                      : "opacity-0 translate-y-4"
                  }`}
                >
                  <p className="absolute bottom-4 left-5 right-5 max-h-16 overflow-y-auto text-white text-base md:text-md font-bold drop-shadow-md">{photo.caption}</p>
                </div>
              )}
            </motion.div>
          );
        })}
      </div>

      {/* Lightbox */}
      {selectedPhoto && (
        <div
          className="fixed inset-0 bg-black/90 backdrop-blur-md z-[100] flex items-center justify-center p-0 md:p-4"
          onClick={() => setSelectedIndex(null)}
          onTouchStart={(e) => {
            touchStartX.current = e.changedTouches[0].clientX;
          }}
          onTouchEnd={(e) => handleTouchEnd(e.changedTouches[0].clientX)}
        >
          <Button
            variant="ghost"
            size="icon"
            className="absolute top-4 right-4 z-10 text-white hover:bg-white/10"
            onClick={(e) => {
              e.stopPropagation();
              setSelectedIndex(null);
            }}
          >
            <X className="w-8 h-8" />
          </Button>
          <div
            className="relative flex h-dvh w-full max-w-5xl flex-col justify-center md:h-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="relative min-h-0 flex-1 md:flex-none">
              <img
                src={selectedPhoto.url}
                alt={selectedPhoto.caption ?? `San Pablo City photo ${(selectedIndex ?? 0) + 1}`}
                className="h-full w-full object-contain md:h-auto md:max-h-[80vh] md:rounded-lg md:shadow-2xl"
              />
            </div>
            {selectedPhoto.caption && (
              <p className="max-h-32 overflow-y-auto px-5 py-4 text-center text-lg font-bold text-white md:mt-6 md:max-h-none md:p-0 md:text-2xl">
                {selectedPhoto.caption}
              </p>
            )}
          </div>
        </div>
      )}
    </motion.div>
  );
};

export default ImageGallery;