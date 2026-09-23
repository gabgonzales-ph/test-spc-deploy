//src/components/FloatingWidgets.tsx

"use client";

import { usePathname } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import HotlinesSidebar from "@/components/home/HotlinesSidebar";
import ChatWidgetLoader from "@/components/ChatWidgetLoader";

export default function FloatingWidgets() {
  const pathname = usePathname();

  // Hide floating widgets while on the Citizen's Charter page
  const isCitizensCharterPage = pathname?.startsWith("/arta/citizens-charter");

  return (
    <AnimatePresence>
      {!isCitizensCharterPage && (
        <motion.div
  key="floating-widgets"
  initial={{ opacity: 0 }}
  animate={{ opacity: 1 }}
  exit={{ opacity: 0 }}
  transition={{ duration: 0.35, ease: "easeInOut" }}
>
  <HotlinesSidebar />
  <ChatWidgetLoader />
</motion.div>
      )}
    </AnimatePresence>
  );
}