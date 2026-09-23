// src/backend/schemas/map.ts
import { t } from "elysia";

export const cityOfficeSchema = t.Object({
  id: t.String(),
  name: t.String(),
  lat: t.Union([t.Number(), t.Null()]),
  lng: t.Union([t.Number(), t.Null()]),
  address: t.Optional(t.Union([t.String(), t.Null()])),
  directions: t.Optional(t.Union([t.String(), t.Null()])),
  contact: t.Optional(t.Union([t.String(), t.Null()])),
  hours: t.Optional(t.Union([t.String(), t.Null()])),
  image: t.Optional(t.Union([t.String(), t.Null()])),
  sort_order: t.Optional(t.Number()),
  offices: t.Optional(t.Array(t.String())),
  description: t.Optional(t.Union([t.String(), t.Null()])),
});

export const cityOfficeListResponse = t.Object({
  success: t.Boolean(),
  data: t.Array(cityOfficeSchema),
});

export type CityOffice = typeof cityOfficeSchema.static;