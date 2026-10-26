import type { Metadata, Viewport } from "next";
import { Inter, Inter_Tight, JetBrains_Mono } from "next/font/google";
import type { Content } from "@/lib/content";
import "./globals.css";

// Two root layouts (/ in English, /zh/ in Chinese) so each page gets its own <html lang>.

// Self-hosted at build time by next/font; the system face still wins on a Mac.
const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });
const display = Inter_Tight({ subsets: ["latin"], variable: "--font-display" });
const mono = JetBrains_Mono({ subsets: ["latin"], variable: "--font-mono" });

export const metadataFor = (c: Content): Metadata => ({
  metadataBase: new URL("https://reporadar.passion7.cc"),
  title: c.meta.title,
  description: c.meta.description,
  alternates: { languages: { en: "/", "zh-CN": "/zh/" } },
  openGraph: { title: c.meta.title, description: c.meta.description, type: "website" },
});

export const viewport: Viewport = { themeColor: "#090b12", colorScheme: "dark" };

export function Root({ lang, children }: { lang: string; children: React.ReactNode }) {
  return (
    <html lang={lang} className={`${inter.variable} ${display.variable} ${mono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
