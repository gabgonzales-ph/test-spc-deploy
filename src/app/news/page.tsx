//src/app/news/page.tsx

"use client";

import { useState, useEffect, useCallback } from "react";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Building2, ChevronRight, ChevronLeft, Newspaper } from "lucide-react";
import Link from "next/link";
import Image from "next/image";
import { useGetArticles } from "@/hooks/useApi";

interface Article {
  article_id: number;
  slug: string;
  title: string;
  excerpt: string;
  published_at: string;
  category: { name: string } | null;
  featured_media: { file_path: string } | null;
}

const ARTICLES_PER_PAGE = 6;
const PLACEHOLDER = "https://placehold.co/500x300?text=No+Image";

const formatDate = (dateString: string) => {
  if (!dateString) return "Date not available";
  return new Date(dateString).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
};

const ArticleCard = ({
  item,
  isFirst,
}: {
  item: Article;
  isFirst: boolean;
}) => {
  const initialSrc = item.featured_media?.file_path || PLACEHOLDER;
  const [imgSrc, setImgSrc] = useState(initialSrc);

  const handleError = useCallback(() => {
    setImgSrc(PLACEHOLDER);
  }, []);

  return (
    <article className="bg-white rounded-2xl shadow-lg hover:shadow-2xl transition-all duration-300 overflow-hidden group hover:scale-105 h-full flex flex-col">
      <div className="relative w-full h-52 bg-emerald-900/5 flex items-center justify-center overflow-hidden">
        <img
          src={imgSrc}
          alt={item.title || "News Image"}
          loading={isFirst ? "eager" : "lazy"}
          className="absolute inset-0 w-full h-full object-contain p-2 z-10 transition-transform duration-300 group-hover:scale-110"
          onError={handleError}
        />
        <div className="absolute top-2 left-2 z-10">
          <span className="inline-block bg-emerald-600 text-white text-xs font-semibold px-3 py-1 rounded-full shadow-lg">
            {item.category?.name || "Uncategorized"}
          </span>
        </div>
      </div>

      <div className="p-6 flex flex-col flex-grow">
        <time className="text-sm text-gray-600 mb-2">
          {formatDate(item.published_at)}
        </time>
        <h3 className="text-xl font-bold text-gray-900 mb-2 group-hover:text-emerald-600 transition-colors">
          {item.title}
        </h3>
        <p className="text-gray-600 mb-4 line-clamp-3">{item.excerpt}</p>
        <div className="mt-auto">
          <Link
            href={`/news/${item.slug}`}
            className="inline-flex items-center text-emerald-600 hover:text-emerald-800 font-semibold"
            aria-label={`Read more about ${item.title}`}
          >
            Read More
            <ChevronRight className="w-4 h-4 ml-1 group-hover:translate-x-1 transition-transform" />
          </Link>
        </div>
      </div>
    </article>
  );
};

const LoadingSkeleton = () => (
  <>
    {[...Array(ARTICLES_PER_PAGE)].map((_, index) => (
      <Card key={index} className="bg-white shadow-md transition-shadow">
        <CardHeader>
          <div className="flex justify-between items-center">
            <span className="inline-block bg-gray-200 h-6 w-24 rounded-full animate-pulse" />
            <p className="text-sm bg-gray-200 h-4 w-20 rounded-full animate-pulse" />
          </div>
          <CardTitle className="text-2xl font-semibold text-gray-900 mt-2">
            <div>
              <div className="relative rounded-xl w-full h-48 overflow-hidden bg-gray-200 animate-pulse" />
              <div className="pt-4 space-y-2">
                <div className="bg-gray-200 h-6 w-3/4 rounded-full animate-pulse" />
                <div className="bg-gray-200 h-6 w-1/2 rounded-full animate-pulse" />
              </div>
            </div>
          </CardTitle>
          <CardDescription className="text-gray-600 space-y-2">
            <div className="bg-gray-200 h-4 w-full rounded-full animate-pulse" />
            <div className="bg-gray-200 h-4 w-full rounded-full animate-pulse" />
            <div className="bg-gray-200 h-4 w-2/3 rounded-full animate-pulse" />
          </CardDescription>
          <div className="bg-gray-200 h-5 w-24 rounded-full animate-pulse mt-2" />
        </CardHeader>
      </Card>
    ))}
  </>
);

export default function NewsPage() {
  // useApi already splits the response: `data` = Article[], `pagination` = pagination object
  const { data, loading, error, pagination, execute: fetchArticles } = useGetArticles();
  const [currentPage, setCurrentPage] = useState(1);

  const loadPage = useCallback(
    (page: number) => {
      fetchArticles({ page, limit: ARTICLES_PER_PAGE });
    },
    [fetchArticles]
  );

  useEffect(() => {
    loadPage(1);
  }, [loadPage]);

  const articles = (data as Article[] | null) ?? [];

  const goToPrev = useCallback(() => {
    const prev = currentPage - 1;
    setCurrentPage(prev);
    loadPage(prev);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }, [currentPage, loadPage]);

  const goToNext = useCallback(() => {
    const next = currentPage + 1;
    setCurrentPage(next);
    loadPage(next);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }, [currentPage, loadPage]);

  const goToPage = useCallback(
    (page: number) => {
      setCurrentPage(page);
      loadPage(page);
      window.scrollTo({ top: 0, behavior: "smooth" });
    },
    [loadPage]
  );

  const visiblePages = (() => {
    if (!pagination) return [];
    const delta = 2;
    const start = Math.max(1, currentPage - delta);
    const end = Math.min(pagination.totalPages, currentPage + delta);
    return Array.from({ length: end - start + 1 }, (_, i) => start + i);
  })();

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 via-white to-emerald-50/30">
      <section className="relative py-20 pt-40 px-4 bg-gradient-to-r from-emerald-600 to-emerald-800 text-white overflow-hidden">
        <div className="relative max-w-7xl mx-auto text-center">
          <div className="inline-flex items-center px-4 py-2 bg-white/20 rounded-full text-sm font-medium mb-6">
            <Building2 className="w-4 h-4 mr-2" />
            Local Updates
          </div>
          <h1 className="text-5xl md:text-6xl font-bold mb-6">
            News and Updates
          </h1>
          <p className="text-xl text-emerald-50 max-w-3xl mx-auto">
            From upcoming events and community projects to local stories that
            inspire — here's your hub for the latest updates that bring San
            Pableños together. Stay connected, stay informed!
          </p>
          
        </div>
      </section>

      <section className="py-20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {loading ? (
              <LoadingSkeleton />
            ) : error ? (
              <div className="col-span-full text-center py-12 bg-red-50 text-red-700 rounded-lg">
                <p>Error loading articles: {error}</p>
                <button
                  onClick={() => loadPage(currentPage)}
                  className="mt-3 text-sm underline font-semibold"
                >
                  Try again
                </button>
              </div>
            ) : articles.length === 0 ? (
              <div className="col-span-full text-center py-12">
                <Newspaper className="w-16 h-16 text-gray-300 mx-auto mb-4" />
                <p className="text-gray-600 text-lg">No news articles found.</p>
              </div>
            ) : (
              articles.map((item, index) => (
                <ArticleCard
                  key={item.article_id}
                  item={item}
                  isFirst={currentPage === 1 && index === 0}
                />
              ))
            )}
          </div>

          {pagination && pagination.totalPages > 1 && (
            <div className="flex items-center justify-center gap-2 mt-12">
              <button
                onClick={goToPrev}
                disabled={!pagination.hasPrevious || loading}
                className="flex items-center gap-1 px-4 py-2 rounded-lg border border-gray-200 text-gray-600 hover:bg-emerald-50 hover:border-emerald-300 hover:text-emerald-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
              >
                <ChevronLeft className="w-4 h-4" />
                Previous
              </button>

              {visiblePages[0] > 1 && (
                <>
                  <button
                    onClick={() => goToPage(1)}
                    disabled={loading}
                    className="w-10 h-10 rounded-lg text-sm font-medium border border-gray-200 text-gray-600 hover:bg-emerald-50 hover:border-emerald-300 hover:text-emerald-700 transition-colors disabled:opacity-40"
                  >
                    1
                  </button>
                  {visiblePages[0] > 2 && <span className="px-1 text-gray-400">…</span>}
                </>
              )}

              {visiblePages.map((page) => (
                <button
                  key={page}
                  onClick={() => goToPage(page)}
                  disabled={loading}
                  aria-current={page === currentPage ? "page" : undefined}
                  className={`w-10 h-10 rounded-lg text-sm font-medium transition-colors disabled:opacity-40 ${
                    page === currentPage
                      ? "bg-emerald-600 text-white"
                      : "border border-gray-200 text-gray-600 hover:bg-emerald-50 hover:border-emerald-300 hover:text-emerald-700"
                  }`}
                >
                  {page}
                </button>
              ))}

              {visiblePages[visiblePages.length - 1] < pagination.totalPages && (
                <>
                  {visiblePages[visiblePages.length - 1] < pagination.totalPages - 1 && (
                    <span className="px-1 text-gray-400">…</span>
                  )}
                  <button
                    onClick={() => goToPage(pagination.totalPages)}
                    disabled={loading}
                    className="w-10 h-10 rounded-lg text-sm font-medium border border-gray-200 text-gray-600 hover:bg-emerald-50 hover:border-emerald-300 hover:text-emerald-700 transition-colors disabled:opacity-40"
                  >
                    {pagination.totalPages}
                  </button>
                </>
              )}

              <button
                onClick={goToNext}
                disabled={!pagination.hasNext || loading}
                className="flex items-center gap-1 px-4 py-2 rounded-lg border border-gray-200 text-gray-600 hover:bg-emerald-50 hover:border-emerald-300 hover:text-emerald-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
              >
                Next
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>
      </section>
    </div>
  );
}