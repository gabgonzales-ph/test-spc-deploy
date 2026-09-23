// src/data/map/map.ts

export interface CityOffice {
  id: string;
  name: string;
  lat: number | null;
  lng: number | null;
  directions?: string | null;
  address?: string | null;
  contact?: string | null;
  hours?: string | null;
  image?: string | null;
  sort_order?: number;
  /** Short blurb shown under the office name in the sidebar/panel. */
  description?: string | null;
  /** IDs of other CityOffice rows located inside this destination (e.g. offices inside a building). */
  offices?: string[];
}

// Office data now lives in the `map` table in Supabase and is fetched
// through the backend via the `useMapOffices` hook (src/hooks/useMapOffices.ts).
// This file only keeps the shared type so existing imports of
// `CityOffice` elsewhere in the app keep working.