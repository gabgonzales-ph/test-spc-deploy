//src/app/about-us/explore/page.tsx

"use client";

import React, { useState, useEffect, useCallback, useRef } from "react";
import { Building2, MapPin, Eye, Mountain, BookOpen, XIcon, Calendar, Users } from "lucide-react";
import dynamic from "next/dynamic";
import { motion, type Variants } from "framer-motion";
import Section from "@/components/city-government/Section";
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
  type CarouselApi,
} from "@/components/ui/carousel";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogClose,
} from "@/components/ui/dialog";
import { ImageGallery } from "@/components/explore/ImageGallery";
import { Stat } from "@/components/city-government/types";
import { Card, CardContent } from "@/components/ui/card";
import IconBadge from "@/components/city-government/IconBadge";
import Tourism from "@/components/explore/Tourism";

// Leaflet touches `window`/`document` on load, so it must never be
// server-rendered.
const CityOfficesMap = dynamic(() => import("@/components/explore/Map"), {
  ssr: false,
  loading: () => (
    <div className="w-full h-[500px] md:h-[600px] rounded-2xl border border-emerald-100 bg-emerald-50/50 animate-pulse flex items-center justify-center">
      <p className="text-emerald-700/60 text-sm">Loading map…</p>
    </div>
  ),
});

const sectionReveal: Variants = {
  hidden: { opacity: 0, y: 48 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: "easeOut", staggerChildren: 0.1 },
  },
};

const ScrollRevealSection = ({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) => (
  <motion.section
    className={className}
    initial="hidden"
    whileInView="visible"
    viewport={{ once: true, amount: 0.22, margin: "0px 0px -80px 0px" }}
    variants={sectionReveal}
  >
    {children}
  </motion.section>
);

/* -------------------- Data -------------------- */
const cityStats: Stat[] = [
  { label: "Population", value: "285,348", icon: Users, color: "emerald" },
  { label: "Land Area", value: "197.56 km²", icon: MapPin, color: "blue" },
  { label: "Barangays", value: "80", icon: Building2, color: "purple" },
  { label: "Established", value: "1940", icon: Calendar, color: "orange" },
];

// ---------------------------------------------------------------------------
// SevenLakesCarousel — auto-scrolling with pause on hover/interaction
// Image URLs are built from NEXT_PUBLIC_SUPABASE_URL so they follow
// whichever project is currently configured. Uses a plain <img> tag
// (not next/image) to avoid Vercel Image Optimization quota/billing —
// see NewsCard.tsx, ImageGallery.tsx, and Tourism.tsx for the same change.
// ---------------------------------------------------------------------------

interface Lake {
  name: string;
  description: string;
  image: string; // filename only, e.g. "lakebunot_rev01-ssdiaries.webp"
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const LAKES_BUCKET_PATH = "storage/v1/object/public/media/lakes";

function getLakeImageUrl(filename: string) {
  if (!SUPABASE_URL) {
    // Fails loud in dev/build rather than silently rendering broken images
    console.error("NEXT_PUBLIC_SUPABASE_URL is not set — lake images will not load");
    return "";
  }
  return `${SUPABASE_URL}/${LAKES_BUCKET_PATH}/${filename}`;
}

const SCROLL_INTERVAL = 2000;

const SevenLakesCarousel = () => {
  const [selectedLake, setSelectedLake] = useState<Lake | null>(null);
  const [tilt, setTilt] = useState({ x: 0, y: 0 });
  const [api, setApi] = useState<CarouselApi>();
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const lakes: Lake[] = [
    {
      name: "Bunot Lake",
      description: "The smallest but most charming lake, surrounded by verdant landscapes.",
      image: "lakebunot_rev01-ssdiaries.webp",
    },
    {
      name: "Yambo Lake",
      description: "A picturesque lake offering stunning views and fishing opportunities.",
      image: "lake_yambo20mod-crop-ssdiaries.webp",
    },
    {
      name: "Pandin Lake",
      description: "Famous for its bamboo raft rides and pristine natural beauty.",
      image: "lakepandin-rev02-ssdiaries.webp",
    },
    {
      name: "Mohicap Lake",
      description: "Known for its crystal-clear waters and tranquil atmosphere.",
      image: "lake_mohicap02-ssd.webp",
    },
    {
      name: "Calibato Lake",
      description: "A hidden gem with calm waters perfect for kayaking and nature walks.",
      image: "lake_calibato01mod-ssdiaries.webp",
    },
    {
      name: "Palakpakin Lake",
      description: "A serene lake surrounded by lush vegetation, ideal for peaceful retreats.",
      image: "lake_palakpakin01ss_diaries.webp",
    },
    {
      name: "Sampaloc Lake",
      description: "The largest and most popular of the seven lakes, perfect for water activities and scenic views.",
      image: "lakesampaloc00-ssdiaries.webp",
    },
  ];

  const startAutoScroll = useCallback(() => {
    if (intervalRef.current) clearInterval(intervalRef.current);
    intervalRef.current = setInterval(() => {
      if (!api) return;
      if (api.canScrollNext()) {
        api.scrollNext();
      } else {
        api.scrollTo(0);
      }
    }, SCROLL_INTERVAL);
  }, [api]);

  const stopAutoScroll = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
  }, []);

  useEffect(() => {
    if (!api) return;
    startAutoScroll();
    return () => stopAutoScroll();
  }, [api, startAutoScroll, stopAutoScroll]);

  useEffect(() => {
    const handleDeviceOrientation = (event: DeviceOrientationEvent) => {
      if (event.beta !== null && event.gamma !== null) {
        setTilt({
          x: Math.max(-15, Math.min(15, event.gamma / 2)),
          y: Math.max(-15, Math.min(15, event.beta / 2)),
        });
      }
    };

    if (typeof window !== "undefined" && window.DeviceOrientationEvent) {
      window.addEventListener("deviceorientation", handleDeviceOrientation);
    }

    return () => {
      if (typeof window !== "undefined") {
        window.removeEventListener("deviceorientation", handleDeviceOrientation);
      }
    };
  }, []);

  return (
    <div
      className="w-full max-w-6xl mx-auto px-4 overflow-hidden"
      onMouseEnter={stopAutoScroll}
      onMouseLeave={startAutoScroll}
    >
      <Carousel
        className="w-full"
        setApi={setApi}
        opts={{ loop: true, duration: 40 }}
      >
        <CarouselContent className="-ml-2 md:-ml-4">
          {lakes.map((lake, index) => (
            <CarouselItem key={index} className="pl-2 md:pl-4 basis-[85%] md:basis-1/2 lg:basis-1/3">
              <div className="p-1">
                <div
                  className="cursor-pointer overflow-hidden rounded-xl"
                  onClick={() => {
                    stopAutoScroll();
                    setSelectedLake(lake);
                  }}
                >
                  <div className="relative w-full h-64 overflow-hidden rounded-xl">
                    <img
                      src={getLakeImageUrl(lake.image)}
                      alt={lake.name}
                      loading="lazy"
                      className="absolute inset-0 w-full h-full object-cover"
                    />
                    <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/20 to-transparent" />
                    <div className="absolute bottom-0 left-0 right-0 p-4 text-white">
                      <h3 className="text-xl font-bold">{lake.name}</h3>
                      <p className="text-sm text-emerald-100 mt-1 line-clamp-2">
                        {lake.description}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </CarouselItem>
          ))}
        </CarouselContent>
        <CarouselPrevious
          className="hidden md:flex bg-white/90 hover:bg-emerald-500 hover:text-white"
          onClick={() => { stopAutoScroll(); startAutoScroll(); }}
        />
        <CarouselNext
          className="hidden md:flex bg-white/90 hover:bg-emerald-500 hover:text-white"
          onClick={() => { stopAutoScroll(); startAutoScroll(); }}
        />
      </Carousel>

      <Dialog
        open={selectedLake !== null}
        onOpenChange={(open) => {
          if (!open) {
            setSelectedLake(null);
            startAutoScroll();
          }
        }}
      >
        <DialogContent
          className="max-w-7xl w-[95vw] h-[90vh] md:h-[85vh] p-0 overflow-hidden border-none"
          showCloseButton={false}
        >
          {selectedLake && (
            <div className="h-full flex flex-col overflow-hidden">
              <div
                className="relative w-full h-1/2 md:h-2/3 overflow-hidden bg-slate-900"
                style={{ perspective: "1000px" }}
              >
                <div
                  className="absolute inset-0 w-full h-full"
                  style={{
                    transform: `rotateY(${tilt.x}deg) rotateX(${-tilt.y}deg) scale(1.1)`,
                    transition: "transform 0.1s ease-out",
                  }}
                >
                  <img
                    src={getLakeImageUrl(selectedLake.image)}
                    alt={selectedLake.name}
                    className="absolute inset-0 w-full h-full object-cover"
                  />
                </div>
                <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent" />
              </div>

              <div className="flex-1 p-6 md:p-12 flex flex-col justify-start md:justify-center overflow-hidden bg-white">
                <DialogHeader className="text-left">
                  <DialogTitle className="text-3xl md:text-5xl font-bold text-emerald-800">
                    {selectedLake.name}
                  </DialogTitle>
                  <DialogDescription className="text-gray-700 text-lg md:text-xl leading-relaxed pt-4">
                    {selectedLake.description}
                  </DialogDescription>
                </DialogHeader>
              </div>
            </div>
          )}
          <DialogClose className="absolute top-4 right-4 z-50 p-2 text-white hover:bg-emerald-700/70 transition-colors">
            <XIcon className="size-4" />
            <span className="sr-only">Close</span>
          </DialogClose>
        </DialogContent>
      </Dialog>
    </div>
  );
};

// ---------------------------------------------------------------------------
// NeighboringMunicipalities
// ---------------------------------------------------------------------------

const NeighboringMunicipalities = () => {
  const municipalities = [
    { name: "Calauan, Laguna", distance: "9.5" },
    { name: "Alaminos, Laguna", distance: "10" },
    { name: "Nagcarlan, Laguna", distance: "14" },
    { name: "Rizal, Laguna", distance: "14" },
    { name: "Tiaong, Quezon", distance: "14" },
    { name: "Dolores, Quezon", distance: "14" },
    { name: "Lipa, Batangas", distance: "36" },
  ];

  return (
    <div className="w-full overflow-x-auto rounded-xl border border-gray-200 shadow-sm">
      <table className="min-w-full divide-y divide-gray-200 bg-white">
        <thead>
          <tr className="bg-emerald-50">
            <th className="px-4 md:px-6 py-4 text-left text-sm font-semibold text-gray-900">
              Name of Municipality
            </th>
            <th className="px-4 md:px-6 py-4 text-left text-sm font-semibold text-gray-900">
              Distance (km)
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100">
          {municipalities.map((municipality, index) => (
            <tr
              key={index}
              className={`${
                index % 2 === 0 ? "bg-gray-50/50" : "bg-white"
              } hover:bg-emerald-50/50 transition-colors`}
            >
              <td className="px-4 md:px-6 py-3 text-sm text-gray-800 whitespace-nowrap">
                {municipality.name}
              </td>
              <td className="px-4 md:px-6 py-3 text-sm text-gray-800 font-medium">
                {municipality.distance}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function SanPabloCityInfoPage() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 via-white to-emerald-50/30 max-w-[100vw]">

      
      {/* Hero Section */}
      <section className="relative py-20 pt-32 md:pt-40 px-4 bg-gradient-to-r from-emerald-600 to-emerald-800 text-white overflow-hidden">
        <div className="relative max-w-7xl mx-auto text-center">
          <div className="inline-flex items-center px-4 py-2 bg-white/20 rounded-full text-xs md:text-sm font-medium mb-6 backdrop-blur-sm">
            <Building2 className="w-4 h-4 mr-2" />
            About City
          </div>
          <h1 className="text-4xl md:text-6xl font-bold mb-6 tracking-tight leading-tight">
            Explore San Pablo City
          </h1>
          <p className="text-lg md:text-xl text-emerald-50 max-w-2xl mx-auto opacity-90">
            Learn its rich history, notable landmarks, and cultural heritage that reflect the city's identity and legacy of public service.
          </p>
        </div>
      </section>

            {/* City Statistics */}
      <Section className="-mt-8 relative z-10">
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {cityStats.map((stat, index) => (
            <Card
              key={index}
              className="bg-white/80 backdrop-blur-sm border border-emerald-200/30 hover:shadow-lg transition-all duration-300 group"
            >
              <CardContent className="p-6 flex items-center space-x-4">
                <IconBadge icon={stat.icon} color={stat.color} />
                <div>
                  <p className="text-2xl font-bold text-gray-900">
                    {stat.value}
                  </p>
                  <p className="text-gray-600 text-sm">{stat.label}</p>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </Section>

      {/* City Location */}
      <ScrollRevealSection className="py-12 md:py-16 px-4">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-10">
            <div className="inline-flex items-center justify-center w-16 h-16 md:w-20 md:h-20 bg-emerald-100 rounded-2xl mb-6">
              <MapPin className="w-8 h-8 md:w-10 md:h-10 text-emerald-700" />
            </div>
            <h2 className="text-3xl md:text-4xl font-bold mb-4">City Location</h2>
          </div>
          <div className="bg-white rounded-2xl shadow-sm border border-emerald-100 p-6 md:p-8">
            <p className="text-gray-700 leading-relaxed text-base md:text-lg text-justify">
              San Pablo City is located at the Southern tip of the Province of
              Laguna in the island of Luzon at geographical coordinates, 14°
              4&apos; north latitude and 121° 19&apos; east longitude. It is
              bounded by 6 municipalities and 1 city namely Calauan, Laguna in
              the northwest; Nagcarlan, Laguna in the northeast; Alaminos,
              Laguna in the west; Rizal, Laguna in the east; Lipa City, Batangas
              in the southeastern tip; and the municipalities of Tiaong and
              Dolores, Quezon in the south.
            </p>
            <p className="text-gray-700 leading-relaxed text-base md:text-lg mt-4 text-justify">
              Kilometerage distance from the National Capital Region is about 82
              kilometers and located southwesterly of Manila.
            </p>
          </div>
        </div>
      </ScrollRevealSection>

            {/* City Offices Map */}
        {/* <ScrollRevealSection className="py-12 md:py-16 px-4">
          <div className="max-w-6xl mx-auto">
            <div className="text-center mb-10">
              <div className="inline-flex items-center justify-center w-16 h-16 md:w-20 md:h-20 bg-emerald-100 rounded-2xl mb-6">
                <Building2 className="w-8 h-8 md:w-10 md:h-10 text-emerald-700" />
              </div>
              <h2 className="text-3xl md:text-4xl font-bold mb-4">Find a City Office</h2>
              <p className="text-gray-600 text-base md:text-lg">
                Locate city government offices within San Pablo City
              </p>
            </div>
            <CityOfficesMap />
          </div>
        </ScrollRevealSection> */}


<ScrollRevealSection className="py-12 md:py-16 px-4 bg-white/70">
  <div className="max-w-6xl mx-auto">
    <Tourism />
  </div>
</ScrollRevealSection>

            {/* Distance Table */}
      <ScrollRevealSection className="py-12 md:py-16 px-4 bg-white/70">
        <div className="max-w-3xl mx-auto">
          <div className="text-center mb-10">
            <div className="inline-flex items-center justify-center w-16 h-16 md:w-20 md:h-20 bg-emerald-100 rounded-2xl mb-6">
              <MapPin className="w-8 h-8 md:w-10 md:h-10 text-emerald-700" />
            </div>
            <h2 className="text-3xl md:text-4xl font-bold mb-4">
              Neighboring Municipalities
            </h2>
            <p className="text-gray-600 text-base md:text-lg">
              Accessibility from all directions
            </p>
          </div>
          <NeighboringMunicipalities />
        </div>
      </ScrollRevealSection>

      {/* Image Gallery — CMS-driven */}
      <motion.section 
        className="py-12 md:py-16 px-4 bg-emerald-50/30"
        initial="hidden"
        whileInView="visible"
        viewport={{ once: true, amount: 0.25, margin: "0px 0px -100px 0px" }}
        variants={sectionReveal}
      >
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-12">
            <div className="inline-flex items-center justify-center w-16 h-16 md:w-20 md:h-20 bg-emerald-100 rounded-2xl mb-6">
              <Eye className="w-8 h-8 md:w-10 md:h-10 text-emerald-700" />
            </div>
            <h2 className="text-3xl md:text-4xl font-bold mb-4">Discover Our City</h2>
            <p className="text-gray-600 text-base md:text-lg">
              A visual journey through our beautiful city
            </p>
          </div>
          <ImageGallery />
        </div>
      </motion.section>

      {/* Seven Lakes Carousel */}
      <ScrollRevealSection className="py-12 md:py-16 px-4">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-10">
            <div className="inline-flex items-center justify-center w-16 h-16 md:w-20 md:h-20 bg-emerald-100 rounded-2xl mb-6">
              <Mountain className="w-8 h-8 md:w-10 md:h-10 text-emerald-700" />
            </div>
            <h2 className="text-3xl md:text-4xl font-bold mb-4">The City of Seven Lakes</h2>
            <p className="text-gray-600 text-base md:text-lg">
              Explore the natural wonders that define our city
            </p>
          </div>
          <SevenLakesCarousel />
        </div>

        <footer className="py-8 px-4 border-t border-gray-100 bg-white">
        <div className="max-w-2xl mx-auto text-center space-y-4">
          <p className="text-xs text-gray-500">
            <span className="font-semibold">Photo Credits:</span> All images courtesy of SS Diaries
          </p>
          <p className="text-[10px] text-gray-400 leading-tight">
            The information provided about the Seven Lakes is for general informational purposes only. Conditions, accessibility, and activities may vary.
          </p>
        </div>
      </footer>
      </ScrollRevealSection>



      {/* Geography */}
      <ScrollRevealSection className="py-12 md:py-16 px-4">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-10">
            <div className="inline-flex items-center justify-center w-16 h-16 md:w-20 md:h-20 bg-emerald-100 rounded-2xl mb-6">
              <Mountain className="w-8 h-8 md:w-10 md:h-10 text-emerald-700" />
            </div>
            <h2 className="text-3xl md:text-4xl font-bold mb-4">Geography and Topology</h2>
          </div>
          <div className="bg-white rounded-2xl shadow-sm border border-emerald-100 p-6 md:p-8">
            <p className="text-gray-700 leading-relaxed text-base md:text-lg mb-6 text-justify">
San Pablo City, also known as the City of Seven Lakes, is located at geographical coordinates 14° 4′ north latitude and 121° east longitude. It is about 87 kilometers south-southwest of the City of Manila, with Rizal Park as the reference point. The City is the center of other progressive cities in Southern Luzon as it belongs to a vital economic hub. The City at 14° 15′ 20″ north latitude is bounded by the mountain ranges of Kaisungan and Calauan Hills in the south; Mabilog in the northwest; San Cristobal and Banahaw Mountains in the east; and Susong-Dalaga, Napayong, and Masalukot Hills in the south to the southeast.
            </p>
            <div className="bg-emerald-50 p-6 rounded-xl border border-emerald-100">
              <h3 className="text-lg font-bold text-emerald-800 mb-2">
                Total Land Area
              </h3>
              <p className="text-gray-700">
                The City of San Pablo has a total land area of{" "}
                <span className="font-semibold">19,899 hectares</span>, 77.16%
                of which is devoted to crop production.
              </p>
            </div>
          </div>
        </div>
      </ScrollRevealSection>

      {/* History */}
      <ScrollRevealSection className="relative py-16 md:py-24 px-4 overflow-hidden">
        {/* Background photo with 50% black overlay */}
        <div
          className="absolute inset-0 bg-cover bg-center"
          style={{ backgroundImage: "url('/cathedral.webp')" }}
          aria-hidden="true"
        />
        <div className="absolute inset-0 bg-black/80" aria-hidden="true" />

        <div className="relative max-w-4xl mx-auto">
          <div className="text-center mb-12">
            <div className="inline-flex items-center justify-center w-16 h-16 md:w-20 md:h-20 rounded-xl bg-white/20 backdrop-blur-sm mb-6">
              <BookOpen className="w-8 h-8 md:w-13 md:h-13 text-white" strokeWidth={1.5} />
            </div>
            <h2 className="text-3xl md:text-4xl font-bold mb-4 text-white">
              History of San Pablo City
            </h2>

          </div>

          <div className=" p-6 md:p-10">
            <p className="text-white leading-relaxed mb-4 text-base md:text-lg text-justify">
 San Pablo City is located at the southern tip of the Province of Laguna in the Island of Luzon at geographic coordinates, 14° 4′ north latitude and 121° 19′ east longitude. It is bounded by 6 municipalities and 1 city namely Calauan, Laguna in the northwest; Nagcarlan, Laguna in the northeast; Alaminos, Laguna in the west; Rizal, Laguna in the east; Lipa City, Batangas in the southeastern tip; and the municipalities of Tiaong and Dolores, Quezon in the south. All adjoining municipalities and city have entry points making San Pablo accessible from virtually all directions.
            </p>
            <p className="text-white leading-relaxed mb-4 text-base md:text-lg text-justify">
Kilometerage distance from the National Capital Region is about 82 kilometers and located southwesterly of Manila. Approximate distance with neighboring municipalities is shown in the following Table 1.
            </p>
            <p className="text-white leading-relaxed text-base md:text-lg text-justify">
San Pablo was known as "Sampalok Village".
            </p>
          </div>
        </div>
      </ScrollRevealSection>

      
    </div>
  );
}