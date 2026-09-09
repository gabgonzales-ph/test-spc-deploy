import { Metadata } from "next";
import { unstable_cache } from "next/cache";
import { supabase } from "@/backend/config/database";
import { getPublicMediaUrl } from "@/backend/utils/helpers";
import HomeCarousel from "@/components/home/HomeCarousel";
import MergedInfoCard from "@/components/home/MergeInfoCard";
import HomeBelowFold from "@/components/client/HomeBelowFold";
import StructuredData from "@/components/StructuredData";
import JobVacancies from "@/components/home/JobVacancies";

// ============= TYPES =============
export interface Article {
  article_id: number;
  slug: string;
  title: string;
  excerpt: string;
  published_at: string;
  category: { name: string } | null;
  featured_media: { file_path: string } | null;
}

export interface Banner {
  banner_id: number;
  title: string | null;
  description: string | null;
  media?: {
    media_id: number;
    file_path: string;
    caption: string | null;
  };
}

// ============= SERVER-SIDE DATA FETCHING =============
const getLatestArticles = unstable_cache(
  async (): Promise<Article[]> => {
    console.log("Cache MISS — fetching articles from Supabase", new Date().toISOString());
    const { data, error } = await supabase
      .from("articles")
      .select(`
        article_id,
        slug,
        title,
        excerpt,
        published_at,
        featured_media:featured_media_id (file_path),
        category:category_id (name)
      `)
      .eq("status", "published")
      .order("published_at", { ascending: false })
      .limit(3);

    if (error) {
      console.error("Failed to fetch articles for homepage:", error);
      return [];
    }

    const rawArticles = (data as unknown as Article[]) || [];

    // Normalize featured_media (Supabase may return this as an array or a
    // single object depending on join inference) and rewrite file_path into
    // a full URL against the currently configured Supabase project.
    return rawArticles.map((article) => {
      const media = Array.isArray(article.featured_media)
        ? article.featured_media[0]
        : article.featured_media;

      return {
        ...article,
        featured_media: media
          ? { ...media, file_path: getPublicMediaUrl(media.file_path) ?? "" }
          : null,
      };
    });
  },
  ["homepage-articles"],
  { revalidate: 300, tags: ["homepage-articles"] }
);

const getLatestBanners = unstable_cache(
  async (): Promise<Banner[]> => {
    console.log("Cache MISS — fetching banners from Supabase", new Date().toISOString());
    const { data, error } = await supabase
      .from("banners")
      .select(`
        banner_id,
        title,
        description,
        media:image_media_id (
          media_id,
          file_path,
          caption
        )
      `)
      .eq("active", true)
      .order("order_index", { ascending: true })
      .limit(10);

    if (error) {
      console.error("Failed to fetch banners for homepage:", error);
      return [];
    }

    const rawBanners = (data as unknown as Banner[]) || [];

    return rawBanners.map((banner) => {
      const media = Array.isArray(banner.media) ? banner.media[0] : banner.media;

      return {
        ...banner,
        media: media
          ? { ...media, file_path: getPublicMediaUrl(media.file_path) ?? "" }
          : undefined,
      };
    });
  },
  ["homepage-banners"],
  { revalidate: 60, tags: ["homepage-banners"] }
);

// ============= SEO METADATA =============
export const metadata: Metadata = {
  title: "San Pablo City - Official Government Website | Laguna, Philippines",
  description:
    "Official website of City of San Pablo, Laguna, Philippines. Access city services, news, ordinances, events, and eGov services. Your gateway to efficient local government services.",
  keywords: [
    "San Pablo City", "San Pablo Laguna", "City of San Pablo",
    "San Pablo City Hall", "Laguna Philippines", "City of Seven Lakes",
    "eGov Philippines", "San Pablo services", "San Pablo news",
    "San Pablo ordinances", "San Pablo events", "local government Philippines",
  ],
  authors: [{ name: "City of San Pablo" }],
  creator: "City of San Pablo",
  publisher: "City of San Pablo",
  openGraph: {
    type: "website",
    locale: "en_PH",
    url: "https://sanpablocity.gov.ph",
    siteName: "City of San Pablo",
    title: "San Pablo City - Official Government Website",
    description:
      "Official website of City of San Pablo, Laguna, Philippines. Access city services, news, and eGov services online.",
    images: [{
      url: "https://sanpablocity.gov.ph/og-image.jpg",
      width: 1200, height: 630,
      alt: "City of San Pablo",
      type: "image/jpeg",
    }],
  },
  twitter: {
    card: "summary_large_image",
    title: "San Pablo City - Official Government Website",
    description:
      "Official website of City of San Pablo, Laguna, Philippines. Access city services, news, and eGov services.",
    images: ["https://sanpablocity.gov.ph/twitter-image.jpg"],
    creator: "@SanPabloCity",
  },
  robots: {
    index: true, follow: true,
    googleBot: {
      index: true, follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  category: "Government",
  other: {
    "geo.region": "PH-LAG",
    "geo.placename": "San Pablo City",
    "geo.position": "14.0683;121.3256",
  },
};

// ============= PAGE (SERVER COMPONENT) =============
export default async function HomePage() {
  const [articles, banners] = await Promise.all([
    getLatestArticles(),
    getLatestBanners(),
  ]);

  return (
    <>
      <StructuredData />
      <div className="min-h-screen bg-gradient-to-br from-slate-50 via-white to-emerald-50/30">
        {/* HERO — rendered as server component, no client boundary, LCP image loads immediately */}
        <section className="w-full mb-8" aria-label="San Pablo City Hero Banner">
          <div className="text-center -mt-8">
            <HomeCarousel banners={banners} />
          </div>
        </section>

        {/* INFO BAR — client component for live clock, isolated below hero */}
        {/* <MergedInfoCard /> */}

        {/* BELOW FOLD — news, services, egov; client boundary starts here */}
        <HomeBelowFold articles={articles} />

       
      </div>
    </>
  );
}