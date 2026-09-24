"use client";

import { useState, useEffect, useMemo, useRef } from "react";
import Image from "next/image";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
  type CarouselApi,
} from "@/components/ui/carousel";
import Autoplay from "embla-carousel-autoplay";
import { ChevronLeft, ChevronRight } from "lucide-react";
import type { Banner } from "@/app/page";
import { Play, Pause } from "lucide-react";

function ImageCarouselItem({
  src, alt, title, subtitle,
  isActive = false,
  isPriority = false,
  isVisible = false,
  onToggle,
  isPlaying = true,
  showIcon = false,
  index,
  onImageLoad,
  mobileHeight,
}: {
  src: string; alt: string; title: string; subtitle: string;
  isActive?: boolean; isPriority?: boolean; isVisible?: boolean;
  onToggle?: () => void; isPlaying?: boolean; showIcon?: boolean;
  index: number;
  onImageLoad?: (index: number, ratio: number) => void;
  mobileHeight?: number | null;
}) {
  const [hovered, setHovered] = useState(false);

  const heightClass = "h-[60vh] sm:h-[70vh] md:h-[80vh]";
  const heightStyle = mobileHeight ? { height: `${mobileHeight}px` } : undefined;

  if (!isVisible && !isPriority) {
    return (
      <CarouselItem className="pl-2 md:pl-4">
        <div className="w-full aspect-[16/9] sm:aspect-auto sm:h-[70vh] md:h-[80vh] bg-slate-100 rounded-2xl" />
      </CarouselItem>
    );
  }

  const hasText = title || subtitle;

  return (
    <CarouselItem className="pl-2 md:pl-4">
      <div className="relative rounded-2xl overflow-hidden group">
        {/* Mobile: image fits its own natural aspect ratio, no cropping/letterboxing */}
        <div className="relative w-full sm:hidden cursor-pointer"
        onClick={onToggle}>
     
          <Image
            src={src}
            alt={alt}
            width={1600}
            height={900}
            unoptimized
            
            className="w-full h-auto object-contain rounded-2xl"
            sizes="100vw"
            priority={isPriority}
            {...(isPriority ? { fetchPriority: "high" } : { loading: "lazy" })}
          />

          {hasText && (
            <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent transition-opacity duration-500 group-hover:opacity-0" />
          )}

            {showIcon && (
    <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
      <div className="bg-black/50 rounded-full p-5 animate-[fadeOut_0.6s_ease-in-out]">
        {isPlaying ? (
          <Play className="w-10 h-10 text-white fill-white" />
        ) : (
          <Pause className="w-10 h-10 text-white fill-white" />
        )}
      </div>
    </div>
  )}

          {hasText && (
            <div className="absolute bottom-0 left-0 right-0 p-4 sm:p-6">
              <div className={`transform transition-all duration-700 ease-out
                ${isActive ? "translate-y-0 opacity-100" : "translate-y-2 opacity-90"}
                group-hover:opacity-0 group-hover:translate-y-4`}>
                <h3 className="text-left text-lg font-bold text-white mb-1 drop-shadow-lg leading-tight">
                  {title}
                </h3>
                <p className="text-left text-xs text-white/90 max-w-2xl drop-shadow-md leading-relaxed">
                  {subtitle}
                </p>
              </div>
            </div>
          )}
        </div>

        {/* sm and up: fixed-height container with blurred background + contained image */}
        <div className="hidden sm:block relative w-full sm:h-[70vh] md:h-[80vh] overflow-hidden cursor-pointer"
        onClick={onToggle}>


          {isActive && (
            <Image
              src={src}
              alt=""
              fill
              
              className="object-cover scale-110 blur-2xl opacity-60"
              sizes="10vw"
              priority={isPriority}
              {...(isPriority ? { fetchPriority: "low" } : { loading: "lazy" })}
              aria-hidden="true"
              unoptimized
            />
          )}

          <Image
            src={src}
            alt={alt}
            fill
            unoptimized
            
            className={`object-contain transition-all duration-700 ease-out
              ${isActive ? "scale-[1.00]" : "scale-100"}`}
            sizes="(max-width: 1024px) 90vw, 1200px"
            priority={isPriority}
            {...(isPriority ? { fetchPriority: "high" } : { loading: "lazy" })}
            onLoad={(e) => {
              const img = e.currentTarget;
              if (img.naturalWidth && img.naturalHeight) {
                onImageLoad?.(index, img.naturalHeight / img.naturalWidth);
              }
            }}
          />

          {hasText && (
            <div
              className={`absolute inset-x-0 bottom-0 h-[45%] sm:h-2/5
                bg-gradient-to-t from-black/75 via-black/20 to-transparent
                transition-opacity duration-500 ease-out
                ${hovered ? "opacity-100" : "opacity-0"}`}
            />
          )}

          {showIcon && (
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
              <div className="bg-black/50 rounded-full p-5 sm:p-6 animate-[fadeOut_0.6s_ease-in-out]">
                {isPlaying ? (
                  <Play className="w-10 h-10 sm:w-12 sm:h-12 text-white fill-white" />
                ) : (
                  <Pause className="w-10 h-10 sm:w-12 sm:h-12 text-white fill-white" />
                )}
              </div>
            </div>
          )}

          {hasText && (
            <div className="absolute bottom-0 left-0 right-0 p-6 md:p-8 lg:p-12">
              <div className={`transform transition-all duration-700 ease-out
                ${isActive ? "translate-y-0 opacity-100" : "translate-y-2 opacity-90"}
                group-hover:opacity-0 group-hover:translate-y-4`}>
                <h3 className="text-left text-2xl md:text-3xl lg:text-4xl xl:text-5xl font-bold text-white mb-2 md:mb-3 drop-shadow-lg leading-tight">
                  {title}
                </h3>
                <p className="text-left text-sm md:text-base lg:text-lg xl:text-xl text-white/90 max-w-2xl drop-shadow-md leading-relaxed">
                  {subtitle}
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </CarouselItem>
  );
}

export default function HomeCarousel({ banners }: { banners: Banner[] }) {
  const [api, setApi] = useState<CarouselApi>();
  const [currentSlide, setCurrentSlide] = useState(0);
  const [autoplayReady, setAutoplayReady] = useState(false);
  const [isPlaying, setIsPlaying] = useState(true);
  const [showIcon, setShowIcon] = useState(false);

  const [isMobile, setIsMobile] = useState(false);
  const [containerWidth, setContainerWidth] = useState(0);
  const [aspectRatios, setAspectRatios] = useState<Record<number, number>>({});
  const wrapperRef = useRef<HTMLDivElement>(null);

  const autoplay = useMemo(
    () => Autoplay({ delay: 5000, stopOnInteraction: false, playOnInit: true }),
    []
  );

  const isPlayingRef = useRef(true);

  const togglePlayPause = () => {
    if (!api) return;
    const autoplayPlugin = api.plugins()?.autoplay;
    if (!autoplayPlugin) return;

    const nextIsPlaying = !isPlayingRef.current;
    isPlayingRef.current = nextIsPlaying;

    if (nextIsPlaying) {
      autoplayPlugin.play();
    } else {
      autoplayPlugin.stop();
    }

    setIsPlaying(nextIsPlaying);
    setShowIcon(true);
    window.setTimeout(() => setShowIcon(false), 600);
  };

  useEffect(() => {
    if (!api) return;
    const syncSlide = () => setCurrentSlide(api.selectedScrollSnap());
    syncSlide();
    api.on("select", syncSlide);
    api.on("reInit", syncSlide);
    return () => {
      api.off("select", syncSlide);
      api.off("reInit", syncSlide);
    };
  }, [api]);

  useEffect(() => {
    const rafId = requestAnimationFrame(() => setAutoplayReady(true));
    return () => cancelAnimationFrame(rafId);
  }, []);

  // Track mobile breakpoint (matches Tailwind's sm: 640px)
  useEffect(() => {
    const mq = window.matchMedia("(max-width: 639px)");
    const update = () => setIsMobile(mq.matches);
    update();
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, []);

  // Track rendered width of the carousel to convert aspect ratio -> px height
  useEffect(() => {
    const el = wrapperRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      for (const entry of entries) setContainerWidth(entry.contentRect.width);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const handleImageLoad = (index: number, ratio: number) => {
    setAspectRatios((prev) => (prev[index] === ratio ? prev : { ...prev, [index]: ratio }));
  };

  const maxAspectRatio = useMemo(() => {
    const values = Object.values(aspectRatios);
    return values.length ? Math.max(...values) : 0;
  }, [aspectRatios]);

  // Fixed mobile height = tallest banner's rendered height at current width,
  // clamped so an unusually tall image can't take over the viewport.
  const mobileHeight = useMemo(() => {
    if (!isMobile || !containerWidth || !maxAspectRatio) return null;
    const computed = containerWidth * maxAspectRatio;
    const vh = window.innerHeight;
    return Math.min(Math.max(computed, vh * 0.4), vh * 0.85);
  }, [isMobile, containerWidth, maxAspectRatio]);

  if (banners.length === 0) return null;

  const opts = useMemo(() => ({ loop: banners.length > 1 }), [banners.length]);
  const plugins = useMemo(
    () => (autoplayReady && banners.length > 1 ? [autoplay] : []),
    [autoplayReady, banners.length, autoplay]
  );

  return (
    <div className="w-full bg-gradient-to-br from-slate-50 via-white to-emerald-50/20 pt-8 sm:pt-12">
      <div className="px-2 sm:px-4 md:px-6 lg:px-8 xl:px-12 2xl:px-24 pt-32 sm:pt-28 md:pt-32">
        <Carousel
          className="w-full mx-auto relative items-start sm:items-stretch"
          opts={{ loop: banners.length > 1 }}
          plugins={autoplayReady && banners.length > 1 ? [autoplay] : []}
          setApi={setApi}
        >
          <CarouselContent className="items-start sm:items-stretch">
            {banners.map((banner, index) => {
              const isVisible =
                Math.abs(index - currentSlide) <= 1 ||
                (currentSlide === 0 && index === banners.length - 1) ||
                (currentSlide === banners.length - 1 && index === 0);

                return (
                  <ImageCarouselItem
                    key={banner.banner_id}
                    index={index}
                    src={banner.media?.file_path || ""}
                    alt={banner.title || ""}
                    title={banner.title || ""}
                    subtitle={banner.description || ""}
                    isActive={index === currentSlide}
                    isPriority={index === 0}
                    isVisible={isVisible}
                    onToggle={togglePlayPause}
                    isPlaying={isPlaying}
                    showIcon={showIcon && index === currentSlide}
                    onImageLoad={handleImageLoad}
                    mobileHeight={mobileHeight}
                  />
                );
              })}
            </CarouselContent>

            {banners.length > 1 && (
              <>
                <CarouselPrevious aria-label="Previous slide" className="hidden xs:flex absolute left-2 sm:left-4 top-1/2 -translate-y-1/2 z-10 w-10 h-10 sm:w-14 sm:h-14 rounded-full bg-white/90 backdrop-blur-sm border-0 shadow-lg hover:bg-emerald-500 hover:text-white transition-all">
                  <ChevronLeft className="w-6 h-6" />
                </CarouselPrevious>
                <CarouselNext aria-label="Next slide" className="hidden xs:flex absolute right-2 sm:right-4 top-1/2 -translate-y-1/2 z-10 w-10 h-10 sm:w-14 sm:h-14 rounded-full bg-white/90 backdrop-blur-sm border-0 shadow-lg hover:bg-emerald-500 hover:text-white transition-all">
                  <ChevronRight className="w-6 h-6" />
                </CarouselNext>
              </>
            )}
          </Carousel>
        </div>

        {banners.length > 1 && (
          <div className="flex justify-center mt-6">
            <div className="flex space-x-2 bg-emerald-500/20 backdrop-blur-md rounded-full px-3 py-2 shadow-md border border-emerald-500/30">
              {banners.map((_, index) => (
                <button
                  key={index}
                  onClick={() => api?.scrollTo(index)}
                  aria-label={`Show banner slide ${index + 1}`}
                  className={`h-2 w-2 md:h-3 md:w-3 rounded-full transition-all duration-300
                    ${index === currentSlide
                      ? "bg-gradient-to-r from-emerald-500 to-teal-500 w-6 md:w-8 shadow"
                      : "bg-emerald-300/70 hover:bg-emerald-400/90"}`}
                />
              ))}
            </div>
          </div>
        )}
      </div>

  );
}