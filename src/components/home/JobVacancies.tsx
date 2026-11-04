"use client";

import React, { useState, useEffect, useMemo, useCallback } from "react";
import PesoCard from "@/components/publications/PesoCard";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import {
  Briefcase,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  ChevronDown,
  ChevronsUpDown,
  Inbox,
  Loader2,
  AlertCircle,
  Calendar,
  FileText,
} from "lucide-react";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
interface Publication {
  publication_id: number;
  filename:    string;
  file_path:   string;
  pdf_url:     string | null;
  uploaded_by: number | null;
  created_at:  string;
  updated_at:  string;
}

interface Vacancy {
  id:          number;
  datePosted: string;
  filename:    string;
  pdfUrl:      string | null;
}

type SortField = "datePosted" | "filename";
type SortDir   = "asc" | "desc";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const ITEMS_PER_PAGE = 10;

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", {
    year: "numeric", month: "long", day: "numeric",
  });
}

function SortIcon({
  field, sortField, sortDir,
}: {
  field: SortField; sortField: SortField; sortDir: SortDir;
}) {
  if (sortField !== field)
    return <ChevronsUpDown className="w-3.5 h-3.5 ml-1 text-gray-400" />;
  return sortDir === "asc"
    ? <ChevronUp   className="w-3.5 h-3.5 ml-1 text-emerald-600" />
    : <ChevronDown className="w-3.5 h-3.5 ml-1 text-emerald-600" />;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------
export default function JobVacancies() {
  const [vacancies,     setVacancies]     = useState<Vacancy[]>([]);
  const [loading,       setLoading]       = useState(true);
  const [error,         setError]         = useState<string | null>(null);
  const [selectedMonth, setSelectedMonth] = useState<string>("all");
  const [page,           setPage]         = useState(1);
  const [sortField,     setSortField]     = useState<SortField>("datePosted");
  const [sortDir,       setSortDir]       = useState<SortDir>("desc");

  const currentYear = new Date().getFullYear();

  const fetchVacancies = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const res = await fetch("/api/publications/vacancies");
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
const data: {
  publication_id: number;
  filename: string;
  pdf_url: string | null;
  created_at: string;
}[] = await res.json();

setVacancies(
  data.map((pub) => ({
    id:         pub.publication_id,
    datePosted: pub.created_at,
    filename:   pub.filename,
    pdfUrl:     pub.pdf_url,
  }))
);
    } catch (err) {
      console.error("Failed to fetch publications:", err);
      setError("Unable to load vacancies at this time. Please try again later.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchVacancies();
  }, [fetchVacancies]);

  function useFadeUp(threshold = 0.15) {
    const ref = React.useRef<HTMLDivElement>(null);
    const [visible, setVisible] = useState(false);

    useEffect(() => {
      const el = ref.current;
      if (!el) return;
      const observer = new IntersectionObserver(
        ([entry]) => { if (entry.isIntersecting) { setVisible(true); observer.disconnect(); } },
        { threshold }
      );
      observer.observe(el);
      return () => observer.disconnect();
    }, [threshold]);

    return { ref, visible };
  }

  const vacancyCard = useFadeUp();
  const footerNote  = useFadeUp();

  // ── Filters (Locked to Current Year) ──────────────────────────────────────
  const filtered = useMemo(() => {
    return vacancies.filter((v) => {
      const date = new Date(v.datePosted);
      const isCurrentYear = date.getFullYear() === currentYear;
      const matchMonth = selectedMonth === "all" || MONTHS[date.getMonth()] === selectedMonth;
      return isCurrentYear && matchMonth;
    });
  }, [vacancies, selectedMonth, currentYear]);

  // ── Sort ──────────────────────────────────────────────────────────────────
  const sorted = useMemo(() => {
    return [...filtered].sort((a, b) => {
      const valA = sortField === "datePosted" ? a.datePosted : a.filename;
      const valB = sortField === "datePosted" ? b.datePosted : b.filename;
      const cmp  = valA < valB ? -1 : valA > valB ? 1 : 0;
      return sortDir === "asc" ? cmp : -cmp;
    });
  }, [filtered, sortField, sortDir]);

  const totalPages = Math.max(1, Math.ceil(sorted.length / ITEMS_PER_PAGE));
  const paginated  = sorted.slice((page - 1) * ITEMS_PER_PAGE, page * ITEMS_PER_PAGE);

  function handleMonthChange(val: string) { setSelectedMonth(val); setPage(1); }

  function handleSort(field: SortField) {
    if (sortField === field) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortField(field);
      setSortDir("desc");
    }
    setPage(1);
  }

  return (
    <div className="max-w-7xl mx-auto px-4 mt-10 space-y-8 mb-5">
      <PesoCard />

      <Card
        ref={vacancyCard.ref}
        className={`border border-emerald-200/30 shadow-xl bg-white/80 backdrop-blur-sm transition-all duration-700 ease-out
          ${vacancyCard.visible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-8"}`}
      >
        <CardHeader className="px-6 pt-6 pb-0">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div>
              <h2 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
                <Briefcase className="w-6 h-6 text-emerald-600" />
                Job Openings
              </h2>
              <p className="text-sm text-gray-500 mt-1">
                Viewing vacancies for the year {currentYear}.
              </p>
            </div>

            {/* Filters */}
            <div className="flex flex-col sm:flex-row gap-2 w-full sm:w-auto">
              <div className="relative w-full sm:w-44">
                <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none" />
                <select
                  value={selectedMonth}
                  onChange={(e) => handleMonthChange(e.target.value)}
                  className="w-full pl-9 pr-4 py-2 text-sm border border-gray-200  focus:outline-none focus:ring-2 focus:ring-emerald-400 focus:border-transparent bg-white appearance-none cursor-pointer"
                  aria-label="Filter by month"
                >
                  <option value="all">All Months</option>
                  {MONTHS.map((m) => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
                <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none" />
              </div>
            </div>
          </div>
        </CardHeader>

        <CardContent className="px-6 py-6">
          {loading ? (
            <div className="flex flex-col items-center py-16 text-gray-400">
              <Loader2 className="w-10 h-10 animate-spin text-emerald-500 mb-3" />
              <p className="text-sm">Loading vacancies...</p>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center py-16 text-gray-400">
              <AlertCircle className="w-10 h-10 text-red-400 mb-3" />
              <p className="font-medium text-gray-600">Failed to load vacancies</p>
              <p className="text-sm mt-1 text-gray-500">{error}</p>
              <button
                onClick={fetchVacancies}
                className="mt-4 px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-medium rounded-lg transition-colors"
              >
                Try Again
              </button>
            </div>
          ) : (
            <>
              {/* Desktop Table */}
              <div className="hidden md:block overflow-hidden  border border-gray-100">
                <table className="w-full text-sm" aria-label="Job vacancies table">
                  <thead>
                    <tr className="bg-emerald-50 border-b border-emerald-100">
                      <th
                        scope="col"
                        className="px-5 py-3 text-center font-semibold text-gray-700 cursor-pointer select-none"
                        onClick={() => handleSort("datePosted")}
                      >
                        <div className="flex items-center justify-start">
                          Date Submitted
                          <SortIcon field="datePosted" sortField={sortField} sortDir={sortDir} />
                        </div>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-50">
                    {paginated.length === 0 ? (
                      <tr>
                        <td className="px-5 py-16 text-center">
                          <EmptyState selectedMonth={selectedMonth} currentYear={currentYear} />
                        </td>
                      </tr>
                    ) : (
                      paginated.map((v, i) => (
                        <tr
                          key={v.id}
                          className={`transition-colors hover:bg-emerald-50/50 ${
                            i % 2 === 0 ? "bg-white" : "bg-gray-50/40"
                          }`}
                        >
                          <td className="px-5 py-4 text-start">
                            {v.pdfUrl ? (
                              <a  href={v.pdfUrl}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="inline-flex items-center justify-center gap-1.5 text-emerald-700 hover:text-emerald-900 font-medium underline underline-offset-2 transition-colors"
                                aria-label={`View PDF submitted on ${formatDate(v.datePosted)}`}
                              >
                                <FileText className="w-3.5 h-3.5 flex-shrink-0" />
                                {formatDate(v.datePosted)}
                              </a>
                            ) : (
                              <span className="text-gray-500 block text-center">{formatDate(v.datePosted)}</span>
                            )}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>

              {/* Mobile Cards */}
              <div className="md:hidden space-y-2">
                {paginated.length === 0 ? (
                  <div className="py-16 text-center">
                    <EmptyState selectedMonth={selectedMonth} currentYear={currentYear} />
                  </div>
                ) : (
                  <>
                    {/* Mobile Header Row */}
                    <div className="bg-emerald-50/80  p-3 flex justify-center text-center row-gap-0">
                      <span className="text-xs text-emerald-800 uppercase tracking-wider">
                        Date Submitted
                      </span>
                    </div>
                    
                    {paginated.map((v) => (
                      <div
                        key={v.id}
                        className="bg-white/60 p-3.5 flex justify-center text-center  row-gap-0"
                      >
                        {v.pdfUrl ? (
                          <a  href={v.pdfUrl}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-2 text-emerald-700 hover:text-emerald-900 font-medium underline underline-offset-2 transition-colors text-sm"
                            aria-label={`View PDF submitted on ${formatDate(v.datePosted)}`}
                          >
                            <FileText className="w-4 h-4 flex-shrink-0" />
                            {formatDate(v.datePosted)}
                          </a>
                        ) : (
                          <span className="text-sm text-gray-500">{formatDate(v.datePosted)}</span>
                        )}
                      </div>
                    ))}
                  </>
                )}
              </div>

              {/* Pagination */}
              {sorted.length > 0 && (
                <div className="mt-6 flex flex-col sm:flex-row items-center justify-between gap-3">
                  <p className="text-xs text-gray-500">
                    Page{" "}
                    <span className="font-medium text-gray-700">{page}</span> of{" "}
                    <span className="font-medium text-gray-700">{totalPages}</span>
                  </p>
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => setPage((p) => Math.max(1, p - 1))}
                      disabled={page === 1}
                      className="p-2 rounded-lg border border-gray-200 hover:border-emerald-400 hover:text-emerald-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                      aria-label="Previous page"
                    >
                      <ChevronLeft className="w-4 h-4" />
                    </button>
                    {Array.from({ length: totalPages }, (_, i) => i + 1).map((p) => (
                      <button
                        key={p}
                        onClick={() => setPage(p)}
                        className={`w-8 h-8 text-sm rounded-lg border transition-colors ${
                          p === page
                            ? "bg-emerald-600 text-white border-emerald-600 font-semibold"
                            : "border-gray-200 text-gray-700 hover:border-emerald-400 hover:text-emerald-700"
                        }`}
                        aria-label={`Page ${p}`}
                        aria-current={p === page ? "page" : undefined}
                      >
                        {p}
                      </button>
                    ))}
                    <button
                      onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                      disabled={page === totalPages}
                      className="p-2 rounded-lg border border-gray-200 hover:border-emerald-400 hover:text-emerald-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                      aria-label="Next page"
                    >
                      <ChevronRight className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
        </CardContent>
      </Card>

    
    </div>
  );
}

// ---------------------------------------------------------------------------
// Empty State
// ---------------------------------------------------------------------------
function EmptyState({ selectedMonth, currentYear }: { selectedMonth: string, currentYear: number }) {
  return (
    <div className="flex flex-col items-center text-gray-400">
      <Inbox className="w-12 h-12 mb-3 text-gray-300" />
      {selectedMonth !== "all" ? (
        <>
          <p className="font-medium text-gray-600">No results found</p>
          <p className="text-sm mt-1">No vacancies were posted in &ldquo;{selectedMonth}&rdquo; for {currentYear}.</p>
        </>
      ) : (
        <>
          <p className="font-medium text-gray-600">No vacancies posted yet</p>
        </>
      )}
    </div>
  );
}