import type { NextConfig } from "next";

const config: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  images: {
    // Screenshots only, all copied into public/shots by scripts/build-content.mjs.
    localPatterns: [{ pathname: "/shots/**" }],
    deviceSizes: [420, 640, 828, 1080, 1280, 1920],
    imageSizes: [160, 280],
    qualities: [75],
    minimumCacheTTL: 2678400,
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "X-Frame-Options", value: "DENY" },
        ],
      },
    ];
  },
};

export default config;
