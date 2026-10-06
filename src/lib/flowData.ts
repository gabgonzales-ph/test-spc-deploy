//spc-website\src\lib\flowData.ts

export type InputMode = "buttons" | "helpdesk-text" | "free-text";

export interface FlowNode {
  key:         string;
  message:     string;
  options:     { label: string; value: string }[];
  inputMode:   InputMode | null;
  isTerminal?: boolean;
}

export const MAIN_MENU_KEY = "main";

export const STATIC_FLOW_NODES: Record<string, FlowNode> = {

  main: {
    key: "main",
    message:
      "Kamusta! Welcome sa Opisyal na chatbot ng San Pablo.\n\nI-type o piliin ang iyong kailangan mula sa mga sumusunod na pagpipilian:",
    options: [
      { label: "Resources",            value: "serbisyo" },
      { label: "FAQs", value: "tanong" },
      { label: "Help Desk",              value: "iba-pa" },
    ],
    inputMode: "buttons",
  },

  serbisyo: {
    key: "serbisyo",
    message: "Narito ang mga available na opsyon. Pumili sa mga sumusunod:",
    options: [], // populated at runtime by buildDynamicNodes()
    inputMode: "buttons",
  },

  tanong: {
    key: "tanong",
    message: "Anong katanungan ang nais mong masagot? Pumili sa mga sumusunod:",
    options: [], // populated at runtime by buildDynamicNodes()
    inputMode: "buttons",
  },

  "iba-pa": {
    key: "iba-pa",
    message: "Isend ang iyong tanong para masagot ng aming staff.",
    options: [],
    inputMode: "free-text",
    isTerminal: true,
  },
};

export const KEYWORD_MAP: Record<string, string> = {
  serbisyo:               "serbisyo",
  "tanong o suhestiyon":  "tanong",
  tanong:                 "tanong",
  suhestiyon:             "tanong",
  "iba pa":               "iba-pa",
};