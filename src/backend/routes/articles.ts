// src/backend/routes/articles.ts

import { Elysia, t } from "elysia";
import { supabase } from "@/backend/config/database";
import { successResponse } from "@/backend/utils/response";
import { errorHandler, throwNotFoundError } from "@/backend/utils/error";
import { formatPaginationResponse, getPublicMediaUrl } from "@/backend/utils/helpers";

type ArticleStatus = "draft" | "review" | "published" | "archived";

export const articleRoutes = new Elysia({ prefix: "/articles" })
  .use(errorHandler)

  // Public routes - Get published articles WITH MEDIA AND CATEGORY
  .get("/", async ({ query }) => {
    const page = parseInt(query.page as string) || 1;
    const limit = parseInt(query.limit as string) || 10;
    const search = query.search as string;
    const categoryId = query.category_id as string;
    const authorId = query.author as string;
    const fromDate = query.from_date as string;
    const toDate = query.to_date as string;

    // Build count query - only published articles for public
    let countQuery = supabase
      .from("articles")
      .select("*", { count: "exact", head: true })
      .eq("status", "published");

    if (search) {
      countQuery = countQuery.or(
        `title.ilike.%${search}%,excerpt.ilike.%${search}%,body.ilike.%${search}%`
      );
    }
    if (categoryId)
      countQuery = countQuery.eq("category_id", parseInt(categoryId));
    if (authorId) countQuery = countQuery.eq("author", parseInt(authorId));
    if (fromDate) countQuery = countQuery.gte("published_at", fromDate);
    if (toDate) countQuery = countQuery.lte("published_at", toDate);

    const { count, error: countError } = await countQuery;

    if (countError) {
      throw new Error("Failed to fetch article count");
    }

    // Build data query WITH MEDIA AND CATEGORY JOIN
    const from = (page - 1) * limit;
    const to = page * limit - 1;

    let dataQuery = supabase
      .from("articles")
      .select(
        `
        article_id,
        title,
        slug,
        excerpt,
        featured_media_id,
        author,
        category_id,
        published_at,
        created_at,
        featured_media:featured_media_id (
          media_id,
          file_path,
          caption,
          media_type
        ),
        category:category_id (
          category_id,
          name,
          slug
        )
      `
      )
      .eq("status", "published")
      .order("published_at", { ascending: false })
      .range(from, to);

    if (search) {
      dataQuery = dataQuery.or(
        `title.ilike.%${search}%,excerpt.ilike.%${search}%,body.ilike.%${search}%`
      );
    }
    if (categoryId)
      dataQuery = dataQuery.eq("category_id", parseInt(categoryId));
    if (authorId) dataQuery = dataQuery.eq("author", parseInt(authorId));
    if (fromDate) dataQuery = dataQuery.gte("published_at", fromDate);
    if (toDate) dataQuery = dataQuery.lte("published_at", toDate);

    const { data, error } = await dataQuery;

    if (error) {
      console.error("Articles fetch error:", error);
      throw new Error("Failed to fetch articles");
    }

    // Rewrite featured_media.file_path into a full public URL against the
    // currently configured Supabase project, so the frontend never has to
    // know which project is active or handle relative paths itself.
const transformedData = (data || []).map((article) => {
  const media = Array.isArray(article.featured_media)
    ? article.featured_media[0]
    : article.featured_media;

  return {
    ...article,
    featured_media: media
      ? {
          ...media,
          file_path: getPublicMediaUrl(media.file_path),
        }
      : null,
  };
});

    return formatPaginationResponse({
      data: transformedData as unknown[],
      page,
      limit,
      total: count || 0,
    });
  })

  // Public route - Get single published article by slug WITH MEDIA AND CATEGORY
  .get(
    "/slug/:slug",
    async ({ params }) => {
      const { slug } = params;

      console.log("Fetching article with slug:", slug);

      // First, try to find the article with case-sensitive match
      let { data, error } = await supabase
        .from("articles")
        .select(
          `
        *,
        featured_media:featured_media_id (
          media_id,
          file_path,
          caption,
          media_type
        ),
        category:category_id (
          category_id,
          name,
          slug,
          description
        )
      `
        )
        .eq("slug", slug)
        .eq("status", "published")
        .single();

      // If not found, try case-insensitive search and check status
      if (error && error.code === "PGRST116") {
        console.log("Case-sensitive match failed, trying case-insensitive...");

        // Try case-insensitive search to see if article exists
        const { data: caseInsensitiveData, error: caseInsensitiveError } =
          await supabase
            .from("articles")
            .select("slug, status, title")
            .ilike("slug", slug)
            .limit(1);

        if (
          !caseInsensitiveError &&
          caseInsensitiveData &&
          caseInsensitiveData.length > 0
        ) {
          const foundArticle = caseInsensitiveData[0];
          console.log(
            `Found article with matching slug (case-insensitive): "${foundArticle.slug}", status: "${foundArticle.status}"`
          );

          if (foundArticle.status !== "published") {
            console.log(
              `Article exists but is not published. Status: ${foundArticle.status}`
            );
            throwNotFoundError("Article");
          }

          // Retry with the exact slug from database (case-sensitive)
          const retryResult = await supabase
            .from("articles")
            .select(
              `
            *,
            featured_media:featured_media_id (
              media_id,
              file_path,
              caption,
              media_type
            ),
            category:category_id (
              category_id,
              name,
              slug,
              description
            )
          `
            )
            .eq("slug", foundArticle.slug)
            .eq("status", "published")
            .single();

          data = retryResult.data;
          error = retryResult.error;
        } else {
          console.log(
            "Article with slug not found in database (case-insensitive search also failed)"
          );
        }
      }

      if (error) {
        console.error("Supabase error fetching article by slug:", error);
        throwNotFoundError("Article");
      }

      if (!data) {
        console.log("No data returned for slug:", slug);
        throwNotFoundError("Article");
      }

      // 1. Check exact string matching and hidden characters
      console.log(">>> INCOMING SLUG:", `"${slug}"`);
      console.log(">>> INCOMING SLUG LENGTH:", slug.length);

      // 2. Test a raw query without any relational joins
      const { data: rawData, error: rawError } = await supabase
        .from("articles")
        .select("article_id, title, slug")
        .eq("slug", slug);

      console.log(">>> RAW QUERY RESULT:", rawData);
      console.log(">>> RAW QUERY ERROR:", rawError);

      console.log("Article found:", data.title);

      // Same URL rewrite as above, applied to the single-article shape.
const media = Array.isArray(data.featured_media)
  ? data.featured_media[0]
  : data.featured_media;

const transformedData = {
  ...data,
  featured_media: media
    ? {
        ...media,
        file_path: getPublicMediaUrl(media.file_path),
      }
    : null,
};

return successResponse(transformedData);

      return successResponse(transformedData);
    },
    {
      params: t.Object({
        slug: t.String(),
      }),
    }
  );