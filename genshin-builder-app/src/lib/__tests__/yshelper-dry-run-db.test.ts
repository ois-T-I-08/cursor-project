import { describe, expect, it } from "vitest";

import {
  hostKindFromDatabaseUrl,
  missingCharacterIds,
  parseRequireDb,
  sanitizePrismaMessage,
} from "@/lib/yshelper/dry-run-db";

describe("yshelper dry-run db helpers", () => {
  it("parses --require-db and env flag", () => {
    expect(parseRequireDb(["--require-db"], {})).toBe(true);
    expect(parseRequireDb([], { YSHELPER_DRY_RUN_REQUIRE_DB: "true" })).toBe(
      true,
    );
    expect(parseRequireDb([], { YSHELPER_DRY_RUN_REQUIRE_DB: "false" })).toBe(
      false,
    );
    expect(parseRequireDb([], {})).toBe(false);
  });

  it("classifies database host kinds without exposing secrets", () => {
    expect(hostKindFromDatabaseUrl(undefined)).toBe("missing");
    expect(
      hostKindFromDatabaseUrl(
        "postgresql://u:p@ep-example-pooler.ap-northeast-1.aws.neon.tech/db",
      ),
    ).toBe("neon-pooler");
    expect(
      hostKindFromDatabaseUrl(
        "postgresql://u:p@ep-example.ap-northeast-1.aws.neon.tech/db",
      ),
    ).toBe("neon-non-pooler");
    expect(
      hostKindFromDatabaseUrl("postgresql://postgres:postgres@localhost:5432/db"),
    ).toBe("localhost");
  });

  it("sanitizes connection strings from prisma messages", () => {
    const raw =
      "Can't reach database server at postgresql://user:super-secret-password-value@localhost:5432/db";
    const sanitized = sanitizePrismaMessage(raw);
    expect(sanitized).not.toContain("super-secret-password-value");
    expect(sanitized).toContain("postgresql://***@");
  });

  it("computes missing published character ids", () => {
    expect(
      missingCharacterIds(
        ["10000021", "10000116", "10000021"],
        new Set(["10000021"]),
      ),
    ).toEqual(["10000116"]);
    expect(
      missingCharacterIds(["10000021"], new Set(["10000021", "10000116"])),
    ).toEqual([]);
  });
});
