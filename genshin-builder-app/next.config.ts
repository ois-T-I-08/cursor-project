import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    // キャラクター・武器・素材のアイコンを外部APIから直接表示する
    remotePatterns: [
      {
        protocol: "https",
        hostname: "gi.yatta.moe",
      },
    ],
  },
};

export default nextConfig;
