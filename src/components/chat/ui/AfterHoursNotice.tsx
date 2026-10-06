"use client";

export function AfterHoursNotice({
  nextOpenAt, onAcknowledge,
}: { nextOpenAt: string | null; onAcknowledge: () => void }) {
  const when = nextOpenAt
    ? new Date(nextOpenAt).toLocaleString("en-PH", {
        weekday: "long", hour: "numeric", minute: "2-digit", timeZone: "Asia/Manila",
      })
    : null;

  return (
    <div role="dialog" aria-modal="true" aria-labelledby="ah-title"
         className="absolute inset-0 z-20 flex items-center justify-center bg-background/95 p-5">
      <div className="space-y-3 text-center">
        <h3 id="ah-title" className="text-sm font-semibold">Sarado na ang help desk</h3>
        <p className="text-xs text-muted-foreground">
          ChatBot operating hours has ended. You can leave messages and our staff will ac{when ? ` (${when})` : ""}.
        </p>
        <button onClick={onAcknowledge}
                className="rounded-lg bg-blue-700 px-4 py-2 text-xs font-medium text-white hover:bg-blue-800">
          OK, naiintindihan ko
        </button>
      </div>
    </div>
  );
}