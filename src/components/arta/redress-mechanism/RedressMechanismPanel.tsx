"use client";

import Image from "next/image";
import { X, ChevronDown } from "lucide-react";
import { useState } from "react";

/* ----------------------------------------------------------------------- */
/* Redress Mechanism — compact, column-stacked popout                      */
/* ----------------------------------------------------------------------- */

const REDRESS_CHANNELS = [
  {
    id: "hrmo",
    title: "City Human Resource Management Office",
    qrSrc: "/citizens-charter/qr/qr-1.png",
    lines: [
      "Email: chrmo@sanpablocity.gov.ph",
      "HR Building, City Hall Cmpd., Trese Martirez St., San Pablo City 4000",
    ],
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="size-4">
        <path strokeLinecap="round" strokeLinejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75" />
      </svg>
    ),
  },
  {
    id: "pacd",
    title: "Public Assistance Complaints Desk (PACD)",
    qrSrc: "/citizens-charter/qr/qr-2.png",
    lines: [
      "One Stop Processing Center",
      "Lobby, 2nd Flr., New Governance Bldg.",
      "Lobby, 2nd Flr., SPC Shopping Mall & Public Market",
      "Lobby, Ground Flr., CCR Building",
      "Help Desk: helpdesk@sanpablocity.gov.ph",
    ],
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="size-4">
        <path strokeLinecap="round" strokeLinejoin="round" d="M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
        <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1 1 15 0Z" />
      </svg>
    ),
  },
  {
    id: "8888",
    title: "8888 Citizens' Complaint Center",
    qrSrc: "/citizens-charter/qr/qr-3.png",
    lines: [
      "Email: 8888complaint@op.gov.ph",
      "Telephone: Dial 8888",
      "Admin concerns: (02) 8249-8310",
      "J.P. Laurel St., San Miguel, Manila",
    ],
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="size-4">
        <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 6.75c0 8.284 6.716 15 15 15h2.25a2.25 2.25 0 0 0 2.25-2.25v-1.372c0-.516-.351-.966-.852-1.091l-4.423-1.106c-.44-.11-.902.055-1.173.417l-.97 1.293c-.282.376-.769.542-1.21.38a12.035 12.035 0 0 1-7.143-7.143c-.162-.441.004-.928.38-1.21l1.293-.97c.363-.271.527-.734.417-1.173L6.963 3.102a1.125 1.125 0 0 0-1.091-.852H4.5A2.25 2.25 0 0 0 2.25 4.5v2.25Z" />
      </svg>
    ),
  },
  {
    id: "ccb",
    title: "Contact Center ng Bayan (CCB)",
    qrSrc: "/citizens-charter/qr/qr-4.png",
    lines: [
      "SMS: 0908-8816565",
      "Email: email@contactcenterngbayan.gov.ph",
      "Web: www.contactcenterngbayan.gov.ph",
      "Hotline: (02) 8932-0111",
    ],
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="size-4">
        <path strokeLinecap="round" strokeLinejoin="round" d="M20.25 8.511c.884.284 1.5 1.128 1.5 2.097v4.286c0 1.136-.847 2.1-1.98 2.193-.34.027-.68.052-1.02.072v3.091l-3-3c-1.354 0-2.694-.055-4.02-.163a2.115 2.115 0 0 1-.825-.242m9.345-8.334a2.126 2.126 0 0 0-.476-.095 48.64 48.64 0 0 0-8.048 0c-1.131.094-1.976 1.057-1.976 2.192v4.286c0 .837.46 1.58 1.155 1.951m9.345-8.334V6.637c0-1.621-1.152-3.026-2.76-3.235A48.455 48.455 0 0 0 11.25 3c-2.115 0-4.198.137-6.24.402-1.608.209-2.76 1.614-2.76 3.235v6.226c0 1.621 1.152 3.026 2.76 3.235.577.075 1.157.14 1.74.194V21l4.155-4.155" />
      </svg>
    ),
  },
  {
    id: "arta",
    title: "Anti-Red Tape Authority (ARTA)",
    qrSrc: "/citizens-charter/qr/qr-5.png",
    lines: [
      "PLDT: 1-ARTA (12782) / (02) 8246-7940",
      "Smart: 0920-925-3078 / 0998-856-8338",
      "Email: complaints@arta.gov.ph",
    ],
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="size-4">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21" />
      </svg>
    ),
  },
];

export function RedressMechanismPanel({ onClose }: { onClose: () => void }) {
  const [openId, setOpenId] = useState<string | null>(REDRESS_CHANNELS[0].id);

  const toggleChannel = (id: string) =>
    setOpenId((prev) => (prev === id ? null : id));

  return (
    <div
      className="w-full h-full bg-white shadow-2xl shadow-gray-900/15 overflow-hidden flex flex-col"
      role="dialog"
      aria-label="Redress Mechanism"
    >
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-4 bg-emerald-700">
        <div className="flex items-center gap-3">
          <span className="flex items-center justify-center h-9 w-9 rounded-lg bg-white/10 text-white shrink-0">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.75} stroke="currentColor" className="h-5 w-5">
              <path strokeLinecap="round" strokeLinejoin="round" d="M9 12h3.75M9 15h3.75M9 18h3.75m3-14.15v14.3c0 .597-.484 1.08-1.08 1.08H6.33A1.08 1.08 0 0 1 5.25 19.15V4.85c0-.597.484-1.08 1.08-1.08h5.44L16.5 8.14v.71" />
              <path strokeLinecap="round" strokeLinejoin="round" d="M11.77 3.77v3.65c0 .597.484 1.08 1.08 1.08h3.65" />
            </svg>
          </span>
          <div>
            <p className="text-[21px] font-bold text-white leading-tight tracking-tight font-[family-name:var(--font-geist-sans)]">
              Redress Mechanism
            </p>
            <p className="text-[11px] text-emerald-200 mt-0.5">
              Complaints, suggestions &amp; commendations
            </p>
          </div>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="p-1.5 -mr-1 rounded-full border border-white/20 text-emerald-200 hover:text-white hover:bg-white/10 hover:border-white/30 transition-colors shrink-0"
          aria-label="Close Redress Mechanism panel"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Decorative banner — fixed, does not scroll with the list */}
      <div className="flex items-center gap-3.5 px-4 py-5 bg-white border-b border-gray-100 shrink-0">
        <span className="flex items-center justify-center h-12 w-12 rounded-full bg-emerald-50 shrink-0">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="h-6 w-6 text-emerald-600">
            <path strokeLinecap="round" strokeLinejoin="round" d="M10.34 15.84c-.688-.06-1.386-.09-2.09-.09H7.5a4.5 4.5 0 1 1 0-9h.75c.704 0 1.402-.03 2.09-.09m0 9.18c.253.962.584 1.892.985 2.783.247.55.06 1.21-.463 1.511l-.657.38c-.551.318-1.26.117-1.527-.461a20.845 20.845 0 0 1-1.44-4.282m3.102.069a18.03 18.03 0 0 1-.59-4.59c0-1.586.205-3.124.59-4.59m0 9.18a23.848 23.848 0 0 1 8.835 2.535M10.34 6.66a23.847 23.847 0 0 0 8.835-2.535m0 0A23.74 23.74 0 0 0 18.795 3m.38 1.125a23.91 23.91 0 0 1 1.014 5.395m-1.014 8.855c-.118.38-.245.754-.38 1.125m.38-1.125a23.91 23.91 0 0 0 1.014-5.395m0-3.46c.495.413.811 1.035.811 1.73 0 .695-.316 1.317-.811 1.73m0-3.46a24.347 24.347 0 0 1 0 3.46" />
          </svg>
        </span>
        <div>
          <p className="text-[13.5px] font-bold text-emerald-800 leading-snug">
            We want to hear from you
          </p>
          <p className="text-[11.5px] text-emerald-700/80 mt-0.5 leading-snug">
            Reach any of these channels for feedback on our services.
          </p>
        </div>
      </div>

      {/* Channel list */}
      <div className="flex-1 overflow-y-auto divide-y divide-gray-100">
        {REDRESS_CHANNELS.map((channel) => {
          const isOpen = openId === channel.id;
          return (
            <div key={channel.id}>
              <button
                type="button"
                onClick={() => toggleChannel(channel.id)}
                aria-expanded={isOpen}
                className="w-full flex items-center gap-3.5 px-4 py-4 text-left hover:bg-gray-50/80 transition-colors"
              >
                <span className="flex items-center justify-center h-10 w-10 rounded-full bg-emerald-50 text-emerald-600 shrink-0">
                  {channel.icon}
                </span>
                <p className="flex-1 min-w-0 text-[13.5px] font-semibold text-gray-800 leading-snug">
                  {channel.title}
                </p>
                <ChevronDown
                  className={`h-4 w-4 text-gray-400 shrink-0 transition-transform duration-300 ${
                    isOpen ? "rotate-180" : ""
                  }`}
                />
              </button>

              <div
                className={`grid transition-all duration-300 ease-in-out ${
                  isOpen ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0"
                }`}
              >
                <div className="overflow-hidden">
                  <div className="flex gap-4 px-4 pb-4 pt-1">
                    <div className="shrink-0 bg-white p-1.5 rounded-lg border border-gray-150 shadow-sm h-fit">
                      <Image
                        src={channel.qrSrc}
                        alt={`QR code for ${channel.title}`}
                        width={200}
                        height={200}
                        className="size-28 object-contain"
                      />
                    </div>
                    <ul className="flex-1 min-w-0 space-y-1.5 py-0.5">
                      {channel.lines.map((line, i) => (
                        <li key={i} className="text-[11.5px] text-gray-600 leading-snug">
                          {line}
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Footer CTA */}
      <a

  href="https://www.sanpablocity.gov.ph/"
  target="_blank"
  rel="noopener noreferrer"
  className="flex items-center justify-center gap-1.5 px-4 py-2.5 sm:py-3 md:py-3.5 border-t border-gray-100 bg-gray-50/60 text-[13px] sm:text-[14px] md:text-[15px] font-semibold text-emerald-700 hover:bg-emerald-50 hover:text-emerald-800 transition-colors"
>
  View more about San Pablo City
  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor" className="size-3 sm:size-3.5">
    <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
  </svg>
</a>
    </div>
  );
}

export default RedressMechanismPanel;