"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronRight } from "lucide-react";

interface NewsCardProps {
  id: string;
  title: string;
  date: string;
  imageUrl: string;
  excerpt: string;
  category: string;
}

export default function NewsCard({
  id,
  title,
  date,
  imageUrl,
  excerpt,
  category,
}: NewsCardProps) {
  const [imgSrc, setImgSrc] = useState(
    imageUrl && imageUrl.trim() !== ""
      ? imageUrl
      : "https://placehold.co/500x300?text=No+Image"
  );

  return (
    <article className="bg-white rounded-2xl shadow-lg hover:shadow-2xl transition-all duration-300 overflow-hidden group hover:scale-105 h-full flex flex-col">
      <div className="relative overflow-hidden">
        <div className="relative w-full h-52 bg-emerald-900/5 flex items-center justify-center overflow-hidden">

          {/* Main image — plain <img>, bypasses Vercel Image Optimization */}
          <img
            src={imgSrc}
            alt={title || "News Image"}
            loading="lazy"
            className="absolute inset-0 w-full h-full object-contain p-2 z-10 transition-transform duration-300 group-hover:scale-110"
            onError={() => setImgSrc("https://placehold.co/500x300?text=No+Image")}
          />
        </div>
        <div className="absolute top-2 left-2 z-20">
          <span className="inline-block bg-emerald-600 text-white text-xs font-semibold px-4 py-2 rounded-full shadow-lg">
            {category}
          </span>
        </div>
      </div>

      <div className="p-6 flex flex-col flex-grow">
        <div className="flex items-center justify-between text-sm text-gray-500 mb-3">
          <time>{date}</time>
        </div>
        <h3 className="text-xl font-bold text-gray-900 mb-3 group-hover:text-emerald-600 transition-colors">
          {title}
        </h3>
        <p className="text-gray-600 mb-4 line-clamp-3">{excerpt}</p>
        <div className="mt-auto">
          {id && id.trim() !== "" ? (
            <Link
              href={`/news/${id}`}
              className="inline-flex items-center text-emerald-600 hover:text-emerald-800 font-semibold"
            >
              Read More
              <ChevronRight className="w-4 h-4 ml-1 group-hover:translate-x-1 transition-transform" />
            </Link>
          ) : (
            <span className="inline-flex items-center text-gray-400 font-semibold cursor-not-allowed">
              Read More
              <ChevronRight className="w-4 h-4 ml-1" />
            </span>
          )}
        </div>
      </div>
    </article>
  );
}