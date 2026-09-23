// src/backend/routes/map.ts
import { Elysia } from "elysia";
import { supabase } from "../config/database";
import { successResponse } from "../utils/response";
import { AppError } from "../utils/error";
import { cityOfficeListResponse } from "../schemas/map";

export const mapRoutes = new Elysia({ prefix: "/map" }).get(
  "/",
  async () => {
    const { data, error } = await supabase
      .from("map")
      .select(
        "id, name, lat, lng, address, directions, contact, hours, image, description, sort_order, offices"
      )
      .order("sort_order", { ascending: true });

    if (error) {
      // Bubble up as a normal AppError so the existing error middleware
      // formats it consistently with the rest of the API.
      throw new AppError(
        "Failed to fetch city office locations",
        "INTERNAL_ERROR",
        502,
        error.message
      );
    }

    // `image` is stored as just a filename (e.g. "vice-mayors-office.jpg").
    // The actual file lives in the "media" storage bucket under "map/",
    // so resolve it to a public URL here — the frontend just gets a
    // ready-to-use image URL and doesn't need to know about buckets/paths.
    const offices = (data ?? []).map((office) => {
      if (!office.image) return office;

      const { data: publicUrlData } = supabase.storage
        .from("media")
        .getPublicUrl(`map/${office.image}`);

      return { ...office, image: publicUrlData.publicUrl };
    });

    return successResponse(offices);
  },
  {
    response: cityOfficeListResponse,
    detail: {
      summary: "Get all city office map locations",
      tags: ["Map"],
    },
  }
);