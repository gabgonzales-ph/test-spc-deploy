// src/components/explore/Map.tsx
"use client";

import React, { useMemo, useRef, useState } from "react";
import { MapContainer, TileLayer, Marker, ZoomControl, useMap } from "react-leaflet";
import L from "leaflet";
import { Search, X, MapPin, Phone, Clock, WifiOff, ChevronDown, ArrowLeft } from "lucide-react";
import type { CityOffice } from "@/data/map/map";
import { useMapOffices } from "@/hooks/useMap";
import "leaflet/dist/leaflet.css";
import styles from "./Map.module.css";

// Default center: San Pablo City Hall area (average of seeded offices)
const DEFAULT_CENTER: [number, number] = [14.0746, 121.325];
const DEFAULT_ZOOM = 19; // max zoom for OSM tiles — map loads fully zoomed in

// Custom emerald pin — built with a divIcon so we avoid Leaflet's default
// marker image paths, which break under Next.js/webpack bundling.
const officeIcon = L.divIcon({
  className: styles.markerWrapper,
  html: `
    <svg width="22" height="29" viewBox="0 0 32 42" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M16 0C7.163 0 0 7.163 0 16c0 11 16 26 16 26s16-15 16-26C32 7.163 24.837 0 16 0z" fill="white" stroke="#047857" stroke-width="1.5"/>
      <circle cx="16" cy="16" r="6.5" fill="#047857"/>
    </svg>
  `,
  iconSize: [22, 29],
  iconAnchor: [11, 29],
  popupAnchor: [0, -26],
});

const activeOfficeIcon = L.divIcon({
  className: styles.markerWrapper,
  html: `
    <svg width="27" height="35" viewBox="0 0 32 42" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M16 0C7.163 0 0 7.163 0 16c0 11 16 26 16 26s16-15 16-26C32 7.163 24.837 0 16 0z" fill="#059669"/>
      <circle cx="16" cy="16" r="6.5" fill="white"/>
    </svg>
  `,
  iconSize: [27, 35],
  iconAnchor: [14, 35],
  popupAnchor: [0, -32],
});

// Simple Levenshtein edit-distance — used to find the closest-named office
// when a search doesn't have a direct substring match (e.g. typos).
function levenshtein(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] =
        a[i - 1] === b[j - 1]
          ? dp[i - 1][j - 1]
          : 1 + Math.min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1]);
    }
  }
  return dp[m][n];
}

// Finds the best office match for a typed query: prefers a substring match
// (shortest name wins among those), and falls back to the closest name by
// edit distance so a typo like "vise mayor" still finds "Vice Mayor's Office".
function findClosestOffice(query: string, offices: CityOffice[]): CityOffice | null {
  const q = query.trim().toLowerCase();
  if (!q || offices.length === 0) return null;

  const substringMatches = offices.filter((o) => o.name.toLowerCase().includes(q));
  if (substringMatches.length > 0) {
    return substringMatches.reduce((best, o) =>
      o.name.length < best.name.length ? o : best
    );
  }

  let closest: CityOffice | null = null;
  let bestDistance = Infinity;
  for (const office of offices) {
    const distance = levenshtein(q, office.name.toLowerCase());
    if (distance < bestDistance) {
      bestDistance = distance;
      closest = office;
    }
  }
  return closest;
}

// Small helper component that lives inside <MapContainer> so it can call
// useMap() to fly to a selected office. Always flies to the *marker*
// location (the parent destination), never to a sub-office, since
// sub-offices don't have their own coordinates.
function FlyToOffice({ office }: { office: CityOffice | null }) {
  const map = useMap();
  React.useEffect(() => {
    if (office && office.lat != null && office.lng != null) {
      map.flyTo([office.lat, office.lng], 18, { duration: 0.8 });
    }
  }, [office, map]);
  return null;
}

// Dropdown shown under the destination name when `office.offices` has
// entries — lets the visitor pick which office inside the building to view.
// The main destination itself is not listed as an option; "Offices" is
// shown as the placeholder until a specific office is picked.
function OfficesDropdown({
  subOffices,
  selectedId,
  onSelect,
}: {
  subOffices: CityOffice[];
  selectedId: string;
  onSelect: (id: string) => void;
}) {
  return (
    <div className="mb-3 w-full">
      <div className="group relative w-full">
        <select
          value={selectedId}
          onChange={(e) => onSelect(e.target.value)}
          className="w-full appearance-none rounded-xl border border-gray-200 bg-white text-sm font-medium text-gray-800 pl-3.5 pr-10 py-2.5 shadow-sm transition-colors duration-150 hover:border-emerald-300 focus:outline-none focus:ring-2 focus:ring-emerald-500/40 focus:border-emerald-500 cursor-pointer"
        >
          <option value="" disabled hidden>
            Select an office
          </option>
          {subOffices.map((sub) => (
            <option key={sub.id} value={sub.id}>
              {sub.name}
            </option>
          ))}
        </select>
        <ChevronDown className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-emerald-600 pointer-events-none transition-transform duration-150 group-focus-within:rotate-180" />
      </div>
    </div>
  );
}

// "Return to building" — shown when a sub-office's details are being
// displayed, lets the visitor jump back up to the parent destination's
// own info without having to reselect it from the dropdown or search.
function ReturnToBuildingButton({
  buildingName,
  onClick,
}: {
  buildingName: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="mb-4 flex w-full items-center gap-2 rounded-xl border border-emerald-100 bg-emerald-50/60 px-3.5 py-2.5 text-left text-sm font-medium text-emerald-700 transition-colors duration-150 hover:bg-emerald-100/80 hover:border-emerald-200"
    >
      <ArrowLeft className="w-4 h-4 shrink-0" />
      <span className="truncate">
        Return to <span className="font-semibold">{buildingName}</span>
      </span>
    </button>
  );
}

// Sidebar panel that swipes in from the right when a destination is
// selected, showing its image and details.
function DestinationSidebar({
  parentOffice,
  displayedOffice,
  subOffices,
  selectedSubId,
  onSelectSub,
  onClose,
}: {
  parentOffice: CityOffice | null;
  displayedOffice: CityOffice | null;
  subOffices: CityOffice[];
  selectedSubId: string;
  onSelectSub: (id: string) => void;
  onClose: () => void;
}) {
  const isOpen = parentOffice !== null;

  return (
    <div
      className={`absolute top-0 right-0 z-[600] hidden md:block h-full w-76 bg-white shadow-2xl transform transition-transform duration-300 ease-out ${
        isOpen ? "translate-x-0" : "translate-x-full"
      }`}
      aria-hidden={!isOpen}
    >
        {parentOffice && displayedOffice && (
          <div className="flex flex-col h-full">
            {/* Image */}
            <div className="relative w-full h-43 shrink-0 bg-emerald-50">
              {displayedOffice.image ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={displayedOffice.image}
                  alt={displayedOffice.name}
                  className="w-full h-full object-cover"
                />
              ) : (
                <div className="w-full h-full flex items-center justify-center">
                  <MapPin className="w-10 h-10 text-emerald-300" />
                </div>
              )}
              <button
                onClick={onClose}
                aria-label="Close details"
                className="absolute top-3 right-3 w-8 h-8 rounded-full bg-white/90 backdrop-blur-sm shadow-md flex items-center justify-center text-gray-600 hover:text-gray-900 hover:bg-white transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Details */}
            <div className="flex-1 overflow-y-auto p-5">
              <h2 className="text-lg font-semibold text-emerald-800 mb-1">
                {displayedOffice.name}
              </h2>

              {displayedOffice.description && (
                <p className="text-sm text-gray-500 leading-relaxed mb-4">
                  {displayedOffice.description}
                </p>
              )}

              {subOffices.length > 0 && selectedSubId === parentOffice.id && (
                <OfficesDropdown
                  subOffices={subOffices}
                  selectedId=""
                  onSelect={onSelectSub}
                />
              )}

              {selectedSubId !== null && selectedSubId !== parentOffice.id && (
                <ReturnToBuildingButton
                  buildingName={parentOffice.name}
                  onClick={() => onSelectSub(parentOffice.id)}
                />
              )}

              <div className="space-y-4">
                {displayedOffice.address && (
                  <div className="flex items-start gap-3">
                    <MapPin className="w-4 h-4 text-emerald-600 mt-0.5 shrink-0" />
                    <p className="text-sm text-gray-700">{displayedOffice.address}</p>
                  </div>
                )}
                {displayedOffice.contact && (
                  <div className="flex items-start gap-3">
                    <Phone className="w-4 h-4 text-emerald-600 mt-0.5 shrink-0" />
                    <p className="text-sm text-gray-700">{displayedOffice.contact}</p>
                  </div>
                )}
                {displayedOffice.hours && (
                  <div className="flex items-start gap-3">
                    <Clock className="w-4 h-4 text-emerald-600 mt-0.5 shrink-0" />
                    <p className="text-sm text-gray-700">{displayedOffice.hours}</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
      </div>
  );
}

// Mobile-only panel rendered below the map card: a collapsed pill showing
// the selected office's name that expands into a card with image + details.
function MobileDestinationPanel({
  parentOffice,
  displayedOffice,
  subOffices,
  selectedSubId,
  onSelectSub,
  onClose,
}: {
  parentOffice: CityOffice | null;
  displayedOffice: CityOffice | null;
  subOffices: CityOffice[];
  selectedSubId: string;
  onSelectSub: (id: string) => void;
  onClose: () => void;
}) {
  const [expanded, setExpanded] = useState(false);

  // Reset/open expanded state whenever a new destination is selected.
  React.useEffect(() => {
    setExpanded(parentOffice !== null);
  }, [parentOffice]);

  if (!parentOffice || !displayedOffice) return null;

  return (
    <div className="md:hidden mt-3">
      <div
        className={`bg-white border border-emerald-100 rounded-2xl shadow-sm overflow-hidden transition-all duration-300 ease-out ${
          expanded ? "max-h-[520px]" : "max-h-14"
        }`}
      >
        {/* Expanded content */}
        <div className="px-4 pb-4 pt-4">
          <div className="w-full h-36  overflow-hidden bg-emerald-50 mb-3">
            {displayedOffice.image ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={displayedOffice.image}
                alt={displayedOffice.name}
                className="w-full h-full object-cover"
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <MapPin className="w-8 h-8 text-emerald-300" />
              </div>
            )}
          </div>

          <span className="flex-1 text-left text-md font-medium text-emerald-800 truncate block">
            {displayedOffice.name}
          </span>

          {displayedOffice.description && (
            <p className="text-xs text-gray-500 leading-relaxed mb-2">
              {displayedOffice.description}
            </p>
          )}

          {subOffices.length > 0 && selectedSubId === parentOffice.id && (
            <OfficesDropdown
              subOffices={subOffices}
              selectedId=""
              onSelect={onSelectSub}
            />
          )}

          {selectedSubId !== null && selectedSubId !== parentOffice.id && (
            <ReturnToBuildingButton
              buildingName={parentOffice.name}
              onClick={() => onSelectSub(parentOffice.id)}
            />
          )}

          <div className="space-y-3">
            {displayedOffice.address && (
              <div className="flex items-start gap-3">
                <MapPin className="w-4 h-4 text-emerald-600 mt-0.5 shrink-0" />
                <p className="text-sm text-gray-700">{displayedOffice.address}</p>
              </div>
            )}
            {displayedOffice.contact && (
              <div className="flex items-start gap-3">
                <Phone className="w-4 h-4 text-emerald-600 mt-0.5 shrink-0" />
                <p className="text-sm text-gray-700">{displayedOffice.contact}</p>
              </div>
            )}
            {displayedOffice.hours && (
              <div className="flex items-start gap-3">
                <Clock className="w-4 h-4 text-emerald-600 mt-0.5 shrink-0" />
                <p className="text-sm text-gray-700">{displayedOffice.hours}</p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

export default function Map() {
  const { offices: cityOffices, loading, error, isStale } = useMapOffices();

  const [query, setQuery] = useState("");
  // Whether the search results dropdown is visible. Separate from
  // `query` so a successful search (Enter or clicking a result) can
  // collapse the list while leaving the matched name in the input.
  const [resultsOpen, setResultsOpen] = useState(false);
  // selectedId = the destination whose marker is active / map flies to.
  const [selectedId, setSelectedId] = useState<string | null>(null);
  // selectedSubId = which office's details are shown in the sidebar.
  // Equals selectedId unless the visitor picked a sub-office from the dropdown.
  const [selectedSubId, setSelectedSubId] = useState<string | null>(null);
  const markerRefs = useRef<Record<string, L.Marker | null>>({});

  // Map of subOfficeId -> parentId, built from every office's `offices` list.
  // NOTE: uses a plain object, not `new Map()` — this component is itself
  // named `Map`, which shadows the global Map constructor in this scope.
  const parentByOfficeId = useMemo(() => {
    const lookup: Record<string, string> = {};
    for (const office of cityOffices) {
      for (const subId of office.offices ?? []) {
        lookup[subId] = office.id;
      }
    }
    return lookup;
  }, [cityOffices]);

  // Only destinations that are NOT embedded inside another one get a pin —
  // this is what avoids duplicate markers for offices sharing a building.
  const markerOffices = useMemo(
    () =>
      cityOffices.filter(
        (o) => !(o.id in parentByOfficeId) && o.lat != null && o.lng != null
      ),
    [cityOffices, parentByOfficeId]
  );

  const filteredOffices = useMemo(() => {
    if (!query.trim()) return [];
    const q = query.toLowerCase();
    return cityOffices.filter((o) => o.name.toLowerCase().includes(q));
  }, [query, cityOffices]);

  // The destination whose marker is active (always has coordinates).
  const parentOffice = useMemo(
    () => cityOffices.find((o) => o.id === selectedId) ?? null,
    [selectedId, cityOffices]
  );

  // The office whose details are actually shown in the sidebar — either
  // the parent itself, or a sub-office picked from the dropdown/search.
  const displayedOffice = useMemo(
    () => cityOffices.find((o) => o.id === selectedSubId) ?? parentOffice,
    [selectedSubId, parentOffice, cityOffices]
  );

  // Sub-offices that live inside the currently selected parent destination.
  const subOffices = useMemo(() => {
    if (!parentOffice?.offices?.length) return [];
    return parentOffice.offices
      .map((id) => cityOffices.find((o) => o.id === id))
      .filter((o): o is CityOffice => Boolean(o));
  }, [parentOffice, cityOffices]);

  // Selecting from search: if the chosen office is itself a sub-office
  // (embedded in another destination), fly to its parent's marker but show
  // the sub-office's own details in the sidebar.
  // Curated shortlist of frequently-searched destinations, shown as a
  // quick-access panel so visitors don't have to type. Preserves this
  // order regardless of the underlying data order.
  const POPULAR_DESTINATION_NAMES = [
    "San Pablo City Hall",
    "One Stop Processing Center",
    "San Pablo Mega Capitol",
  ];

  
  const popularOffices = useMemo(() => {
    return POPULAR_DESTINATION_NAMES.map((name) =>
      cityOffices.find((o) => o.name === name)
    ).filter((o): o is CityOffice => Boolean(o));
  }, [cityOffices]);

  const handleSelect = (office: CityOffice) => {
    const parentId = parentByOfficeId[office.id] ?? office.id;
    setSelectedId(parentId);
    setSelectedSubId(office.id);
    setQuery(office.name);
    setResultsOpen(false);
  };

  // Pressing Enter searches for the closest-matching office (substring
  // match preferred, falling back to edit distance for typos) and selects
  // it directly, collapsing the results dropdown.
  const handleSearchSubmit = () => {
    const match = findClosestOffice(query, cityOffices);
    if (match) handleSelect(match);
  };

  const handleMarkerClick = (office: CityOffice) => {
    setSelectedId(office.id);
    setSelectedSubId(office.id);
  };

  const clearSearch = () => {
    setQuery("");
    setResultsOpen(false);
    setSelectedId(null);
    setSelectedSubId(null);
  };

  const closeSidebar = () => {
    setSelectedId(null);
    setSelectedSubId(null);
  };

  return (
    <div className="w-full">
      <div className="relative isolate w-full h-[260px] sm:h-[320px] md:h-[600px] rounded-2xl overflow-hidden border border-emerald-100 shadow-sm">
        {/* Search box */}
        <div className="absolute top-3 left-3 right-3 md:top-4 md:left-4 md:right-auto md:w-80 z-[500]">
          <div className="relative">
            <Search className="absolute left-2.5 md:left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 md:w-4 md:h-4 text-gray-400" />
            <input
              type="text"
              value={query}
              onChange={(e) => {
                setQuery(e.target.value);
                setResultsOpen(true);
                setSelectedId(null);
                setSelectedSubId(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  handleSearchSubmit();
                }
              }}
              placeholder="Search for a City Office..."
              className="w-full pl-8 pr-8 py-2.5 md:pl-9 md:pr-9 md:py-2.5 border border-gray-200 bg-white/95 backdrop-blur-sm shadow-md text-xs md:text-sm text-gray-800 placeholder:text-gray-400 focus:outline-none "
            />
            {query && (
              <button
                onClick={clearSearch}
                aria-label="Clear search"
                className="absolute right-2.5 md:right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
              >
                <X className="w-3.5 h-3.5 md:w-4 md:h-4" />
              </button>
            )}
          </div>

          {/* Results dropdown */}
          {query.trim() && resultsOpen && (
            <div className="bg-white/95 backdrop-blur-sm shadow-md border border-gray-100 max-h-40 md:max-h-56 overflow-y-auto">
              {filteredOffices.length > 0 ? (
                filteredOffices.map((office) => (
                  <button
                    key={office.id}
                    onClick={() => handleSelect(office)}
                    className="w-full text-left px-3 py-2 md:px-4 md:py-2.5 text-xs md:text-sm text-gray-700 hover:bg-emerald-50 transition-colors border-b border-gray-50 last:border-0"
                  >
                    {office.name}
                  </button>
                ))
              ) : (
                <p className="px-3 py-2 md:px-4 md:py-2.5 text-xs md:text-sm text-gray-400">No offices found</p>
              )}
            </div>
          )}

          {/* Popular destinations — quick-access shortcuts shown right
              below the search box while it's idle (hidden once the
              visitor starts typing, so it doesn't collide with the
              results dropdown above). Desktop only — the 260px mobile
              map height is too tight for this alongside everything else. */}
          {!query.trim() && popularOffices.length > 0 && (
            <div className="hidden md:block mt-2 bg-white/95 backdrop-blur-sm shadow-md border border-gray-100 rounded-xl overflow-hidden">
              <p className="px-4 pt-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wide text-emerald-700/70">
                Popular Destinations
              </p>
              <div className="pb-1">
                {popularOffices.map((office) => (
                  <button
                    key={office.id}
                    onClick={() => handleSelect(office)}
                    className={`w-full flex items-center gap-2 text-left px-4 py-2 text-sm transition-colors ${
                      selectedId === office.id
                        ? "bg-emerald-50 text-emerald-800 font-medium"
                        : "text-gray-700 hover:bg-emerald-50"
                    }`}
                  >
                    <MapPin className="w-3.5 h-3.5 shrink-0 text-emerald-600" />
                    <span className="truncate">{office.name}</span>
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Offline / cached-data notice */}
        {isStale && (
          <div className="absolute bottom-3 left-3 z-[500] flex items-center gap-1.5 bg-white/95 backdrop-blur-sm shadow-md border border-amber-200 rounded-md px-2.5 py-1.5 text-[11px] md:text-xs text-amber-700">
            <WifiOff className="w-3.5 h-3.5" />
            Showing saved data — reconnecting…
          </div>
        )}

        {loading && cityOffices.length === 0 && (
          <div className="absolute inset-0 z-[500] flex items-center justify-center bg-white/80 backdrop-blur-sm">
            <p className="text-sm text-gray-500">Loading office locations…</p>
          </div>
        )}

        {!loading && error && cityOffices.length === 0 && (
          <div className="absolute inset-0 z-[500] flex items-center justify-center bg-white/80 backdrop-blur-sm">
            <p className="text-sm text-gray-500 px-4 text-center">
              Couldn&apos;t load office locations right now. Please try again shortly.
            </p>
          </div>
        )}

        <MapContainer
          center={DEFAULT_CENTER}
          zoom={DEFAULT_ZOOM}
          scrollWheelZoom={false}
          zoomControl={false}
          className="w-full h-full"
        >
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />

          <ZoomControl position="bottomleft" />

          <FlyToOffice office={parentOffice} />

          {markerOffices.map((office) => (
            <Marker
              key={office.id}
              position={[office.lat as number, office.lng as number]}
              icon={office.id === selectedId ? activeOfficeIcon : officeIcon}
              ref={(ref) => {
                markerRefs.current[office.id] = ref;
              }}
              eventHandlers={{
                click: () => handleMarkerClick(office),
              }}
            />
          ))}
        </MapContainer>

        <DestinationSidebar
          parentOffice={parentOffice}
          displayedOffice={displayedOffice}
          subOffices={subOffices}
          selectedSubId={selectedSubId ?? ""}
          onSelectSub={setSelectedSubId}
          onClose={closeSidebar}
        />
      </div>

      <MobileDestinationPanel
        parentOffice={parentOffice}
        displayedOffice={displayedOffice}
        subOffices={subOffices}
        selectedSubId={selectedSubId ?? ""}
        onSelectSub={setSelectedSubId}
        onClose={closeSidebar}
      />
    </div>
  );
}