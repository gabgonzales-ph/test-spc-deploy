//src/app/arta/citizens-charter/page.tsx

"use client";

import { useState, useEffect } from "react";
import Image from "next/image";
import { motion, AnimatePresence } from "framer-motion";
import CharterHeader from "@/components/arta/citizens-charter/charter-header";
import OfficeSearch from "@/components/arta/citizens-charter/office-search";
import OfficeList from "@/components/arta/citizens-charter/office-list";
import CharterFeedbackAccordion from "@/components/arta/citizens-charter/charter-feedback-accordion";
import { useCitizensCharterSearch } from "@/hooks/useCitizensCharterSearch";

const fadeInUp = {
  hidden: { opacity: 0, y: 24 },
  visible: { opacity: 1, y: 0 },
};

const staggerContainer = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.12 } },
};

export default function CitizensCharterPage() {
  const { query, setQuery, results, clearQuery } = useCitizensCharterSearch();
  const [showIntro, setShowIntro] = useState(true);

  useEffect(() => {
    const skipIntro = sessionStorage.getItem("cc_skip_intro");
    if (skipIntro) {
      setShowIntro(false);
      sessionStorage.removeItem("cc_skip_intro");
    }
  }, []);

  return (
    <>
      {/* Full-Screen Splash Overlay */}
      <AnimatePresence>
        {showIntro && (
          <motion.section
            key="splash-overlay"
            initial={{ opacity: 0, y: 40 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -40 }}
            transition={{ duration: 0.6, ease: "easeInOut" }}
            onClick={() => setShowIntro(false)}
            className="fixed inset-0 z-50 bg-gradient-to-t from-[#009A68] to-emerald-500 text-white flex items-center justify-center px-4 cursor-pointer"
          >
            <div className="text-center flex flex-col items-center space-y-4">
              <div className="mb-6">
                <h1 className="text-3xl md:text-4xl font-bold font-mono">
                  KARTA NG MAMAMAYAN
                </h1>
                <p className="text-xl md:text-3xl font-semibold">
                  CITIZEN'S CHARTER
                </p>
              </div>

<Image
  src="/citizens-charter/logo/am-carmela.png"
  alt="City Seal"
  width={160}
  height={160}
  className="drop-shadow-[0_0_0.4rem_rgba(255,255,255,0.5)] mb-6 w-[240px] md:w-[302px]"
  priority
/>
              <p className="text-sm md:text-xl font-medium italic uppercase">
                "Tuloy po kayo sa digital na pamahalaan Ng lungsod Ng pitong lawa"
              </p>

              {/* Click to continue prompt */}
              <motion.p
                className="text-xs lg:text-base font-semibold tracking-wide mt-8 uppercase"
                animate={{ opacity: [1, 0.4, 1] }}
                transition={{ duration: 1.8, repeat: Infinity, ease: "easeInOut" }}
              >
                Click anywhere to continue
              </motion.p>
            </div>
          </motion.section>
        )}
      </AnimatePresence>

      {/* Main Page Content */}
      {!showIntro && (
        <motion.section
className="flex flex-col min-h-screen gap-4"
          initial="hidden"
          animate="visible"
          variants={staggerContainer}
        >
          {/* Charter header */}
          <motion.div
            variants={fadeInUp}
            transition={{ duration: 0.4, ease: "easeOut" }}
          >
            <CharterHeader />
          </motion.div>
<div className="px-4 max-w-10xl mx-auto w-full flex flex-col gap-4">
          {/* Feedback / Complaints Accordion */}
          <motion.div
            variants={fadeInUp}
            transition={{ duration: 0.4, ease: "easeOut" }}
          >
          

          </motion.div>

          {/* Prompt card */}
          <motion.div
            variants={fadeInUp}
            transition={{ duration: 0.4, ease: "easeOut" }}
            className="bg-gray-50 shadow-sm rounded-xl p-3 md:p-4 flex items-center gap-3"
          >
            <Image
              src="/seal.webp"
              alt="San Pablo City Seal"
              width={56}
              height={56}
              className="drop-shadow-[0_0_0.1rem_#009A68] shrink-0"
            />
            <div>
              <h2 className="text-sm sm:text-base font-bold">
                Saang opisina mo gusto magtungo?
              </h2>
              <p className="text-xs md:text-sm text-gray-500">
                (Which office do you want to transact?)
              </p>
            </div>
          </motion.div>

          {/* Search + List */}
          <motion.div
            variants={fadeInUp}
            transition={{ duration: 0.4, ease: "easeOut" }}
            className="flex flex-col flex-1 overflow-hidden"
          >
            <OfficeSearch
              query={query}
              onChange={setQuery}
              onClear={clearQuery}
            />
            <div className="flex flex-col bg-white border border-gray-200 rounded-lg shadow flex-1 overflow-hidden">
              <div className="flex-1 overflow-y-auto p-4">
                <OfficeList
                  results={results}
                  query={query}
                  onClear={clearQuery}
                />
              </div>
            </div>
            
          </motion.div>
          
                      </div>
        </motion.section>
        
      )}
    </>
  );
}