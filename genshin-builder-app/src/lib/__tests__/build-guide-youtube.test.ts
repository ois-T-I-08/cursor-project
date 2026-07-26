import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { YoutubeGuideClient, YoutubeError } from "../build-guides/youtube-client";

describe("YoutubeGuideClient", () => {
  const env = { ...process.env };

  beforeEach(() => {
    process.env.YOUTUBE_GUIDE_ENABLED = "true";
    process.env.YOUTUBE_API_KEY = "test-key";
  });

  afterEach(() => {
    process.env = { ...env };
  });

  it("uses fixed youtube.googleapis.com host and upserts channel/video shapes", async () => {
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      expect(url.startsWith("https://www.googleapis.com/youtube/v3/")).toBe(true);
      if (url.includes("/channels?")) {
        return Response.json({
          items: [
            {
              id: "UCxxxxxxxxxxxxxxxxxxxxxx",
              snippet: {
                title: "Guide Channel",
                description: "desc",
                customUrl: "@guide",
                thumbnails: { default: { url: "https://example.com/a.jpg" } },
              },
              contentDetails: { relatedPlaylists: { uploads: "UU123" } },
            },
          ],
        });
      }
      if (url.includes("/playlistItems?")) {
        return Response.json({
          items: [{ contentDetails: { videoId: "abcdefghijk" } }],
        });
      }
      if (url.includes("/videos?")) {
        return Response.json({
          items: [
            {
              id: "abcdefghijk",
              snippet: {
                title: "Hu Tao guide",
                description: "crit",
                publishedAt: "2026-01-01T00:00:00Z",
                channelId: "UCxxxxxxxxxxxxxxxxxxxxxx",
                thumbnails: { default: { url: "https://example.com/v.jpg" } },
              },
            },
          ],
        });
      }
      throw new Error(`unexpected ${url}`);
    });

    const client = new YoutubeGuideClient({
      fetchImpl: fetchImpl as unknown as typeof fetch,
      apiKey: "test-key",
    });
    const channel = await client.fetchChannel("UCxxxxxxxxxxxxxxxxxxxxxx");
    expect(channel.uploadsPlaylistId).toBe("UU123");
    const ids = await client.listUploadVideoIds("UU123");
    expect(ids).toEqual(["abcdefghijk"]);
    const videos = await client.fetchVideos(ids);
    expect(videos[0]?.sourceUrl).toContain("youtube.com/watch");
    expect(videos[0]?.metadataHash).toHaveLength(64);
  });

  it("fails closed when disabled", async () => {
    process.env.YOUTUBE_GUIDE_ENABLED = "false";
    const client = new YoutubeGuideClient({ apiKey: "test-key" });
    await expect(client.fetchChannel("UCxxxxxxxxxxxxxxxxxxxxxx")).rejects.toBeInstanceOf(
      YoutubeError,
    );
  });
});
