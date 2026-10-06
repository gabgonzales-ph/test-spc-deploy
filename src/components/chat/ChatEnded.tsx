//src/components/chat/ChatEnded.tsx

import { JPAvatar } from "./ui/JPAvatar";

const BOT_NAME = "Juana";

interface ChatEndedProps {
  onNewChat: () => void;
}

export function ChatEnded({ onNewChat }: ChatEndedProps) {
  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="bg-[#2563EB] px-4 py-3.5 flex items-center gap-2.5 shrink-0">
        <JPAvatar size={32} />
        <div className="flex-1">
          <div className="text-white text-sm font-medium leading-tight">{BOT_NAME}</div>
        </div>
      </div>

      {/* Body */}
      <div className="flex-1 px-4 py-6 overflow-y-auto bg-background">
        <p className="text-[13px] font-semibold mb-1 text-foreground">
          Your chat has ended
        </p>
        <p className="text-xs text-muted-foreground leading-relaxed mb-5">
          Thank you for chatting with us. Feel free to start a new chat session.
        </p>
        <button
          onClick={onNewChat}
          className="w-full bg-[#2563EB] text-white border-none rounded-full py-2.5 text-sm font-semibold cursor-pointer transition-opacity hover:opacity-90"
        >
          Start New Chat
        </button>
      </div>
    </div>
  );
}