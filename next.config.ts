// next.config.ts (spc-website)

import type { NextConfig } from "next";
import bundleAnalyzer from "@next/bundle-analyzer";

const withBundleAnalyzer = bundleAnalyzer({
  enabled: process.env.ANALYZE === "true",
});

const isProd = process.env.NODE_ENV === "production";

const securityHeaders = [
  {
    key: "X-Frame-Options",
    value: "SAMEORIGIN",
  },
  {
    key: "Cross-Origin-Opener-Policy",
    value: "same-origin",
  },
  {
    key: "Content-Security-Policy",
    value: [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://www.google.com https://www.gstatic.com",
      "style-src 'self' 'unsafe-inline' https://www.gstatic.com",
      "img-src 'self' data: blob: https://xpyfthmcffrsehkljgtv.supabase.co https://www.sanpablocity.gov.ph https://sanpablocity.gov.ph https://webapi.sanpablocitygov.org https://placehold.co https://*.tile.openstreetmap.org",
      "font-src 'self'",
      // wss:// required for Supabase Realtime WebSocket connections
      `connect-src 'self'  https://www.google.com https://www.gstatic.com https://xpyfthmcffrsehkljgtv.supabase.co wss://xpyfthmcffrsehkljgtv.supabase.co${isProd ? "" : " http://localhost:3001"}`,
      "frame-src 'self' https://xpyfthmcffrsehkljgtv.supabase.co http://oras.pagasa.dost.gov.ph https://www.google.com",
      "frame-ancestors 'self'",
    ].join("; "),
  },
];

const nextConfig: NextConfig = {
  transpilePackages: ["react-pdf", "pdfjs-dist"],

  experimental: {
    optimizeCss: true,
    optimizePackageImports: [
      "lucide-react",
      "@tabler/icons-react",
      "@radix-ui/react-accordion",
      "@radix-ui/react-dialog",
      "@radix-ui/react-slot",
      "framer-motion",
    ],
  },

  images: {
    formats: ["image/avif", "image/webp"],
    remotePatterns: [
      {
        protocol: "https",
        hostname: "www.sanpablocity.gov.ph",
      },
      {
        protocol: "https",
        hostname: "sanpablocity.gov.ph",
      },
      {
        protocol: "https",
        hostname: "xpyfthmcffrsehkljgtv.supabase.co",
        pathname: "/storage/v1/object/public/**",
      },
      {
        protocol: "https",
        hostname: "xpyfthmcffrsehkljgtv.supabase.co",
        pathname: "/storage/v1/object/sign/**",
      },
      {
        protocol: "https",
        hostname: "webapi.sanpablocitygov.org",
      },
      {
        protocol: "https",
        hostname: "placehold.co",
      },
    ],
  },

  async headers() {
    return [
      {
        source: "/(.*)",
        headers: securityHeaders,
      },
    ];
  },

  typescript: { ignoreBuildErrors: false },
};

export default withBundleAnalyzer(nextConfig);