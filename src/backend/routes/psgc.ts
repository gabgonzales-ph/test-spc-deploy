//backend/routes/psgc.ts -- website

import { Elysia, t } from "elysia";

// Proxies requests to PSGC Cloud v2 (https://psgc.cloud/api/v2) so the
// browser only ever talks to our own origin (/api/psgc/...), avoiding CSP
// connect-src restrictions on third-party domains.
//
// NOTE: v2 is used consistently end-to-end because v1 and the legacy
// (non-versioned) endpoints use two different, incompatible code formats —
// mixing them causes "province not found" style upstream errors.

const PSGC_UPSTREAM = "https://psgc.cloud/api/v2";

async function proxyJson(url: string) {
  const res = await fetch(url, {
    headers: { Accept: "application/json" },
  });

  if (!res.ok) {
    throw new Error(`PSGC upstream error (${res.status}) for ${url}`);
  }

  return res.json();
}

export const psgcRoutes = new Elysia({ prefix: "/psgc" })
  .get("/regions", async ({ set }) => {
    try {
      return await proxyJson(`${PSGC_UPSTREAM}/regions`);
    } catch (err) {
      console.error("PSGC proxy /regions failed:", err);
      set.status = 502;
      return { success: false, message: "Failed to load regions." };
    }
  })

  .get(
    "/regions/:code/provinces",
    async ({ params, set }) => {
      try {
        return await proxyJson(
          `${PSGC_UPSTREAM}/regions/${encodeURIComponent(params.code)}/provinces`
        );
      } catch (err) {
        console.error("PSGC proxy /regions/:code/provinces failed:", err);
        set.status = 502;
        return { success: false, message: "Failed to load provinces." };
      }
    },
    { params: t.Object({ code: t.String() }) }
  )

  .get(
    "/provinces/:code/cities-municipalities",
    async ({ params, set }) => {
      try {
        return await proxyJson(
          `${PSGC_UPSTREAM}/provinces/${encodeURIComponent(
            params.code
          )}/cities-municipalities`
        );
      } catch (err) {
        console.error(
          "PSGC proxy /provinces/:code/cities-municipalities failed:",
          err
        );
        set.status = 502;
        return { success: false, message: "Failed to load cities/municipalities." };
      }
    },
    { params: t.Object({ code: t.String() }) }
  )

  .get(
    "/cities-municipalities/:code/barangays",
    async ({ params, set }) => {
      try {
        return await proxyJson(
          `${PSGC_UPSTREAM}/cities-municipalities/${encodeURIComponent(
            params.code
          )}/barangays`
        );
      } catch (err) {
        console.error(
          "PSGC proxy /cities-municipalities/:code/barangays failed:",
          err
        );
        set.status = 502;
        return { success: false, message: "Failed to load barangays." };
      }
    },
    { params: t.Object({ code: t.String() }) }
  );