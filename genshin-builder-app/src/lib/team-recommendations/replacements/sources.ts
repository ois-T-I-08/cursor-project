import "server-only";

import { readFile } from "node:fs/promises";
import { resolve, sep } from "node:path";
import type { ImportedTeam, TeamSource } from "./types";
import { parseImportedTeamCollection } from "./validation";

export class LocalJsonTeamSource implements TeamSource {
  constructor(
    private readonly filePath = resolve(
      process.cwd(),
      "data",
      "team-templates",
      "approved-teams.json",
    ),
  ) {}

  async fetchTeams(): Promise<ImportedTeam[]> {
    const absolute = resolve(this.filePath);
    const root = resolve(process.cwd(), "data", "team-templates");
    if (absolute !== root && !absolute.startsWith(`${root}${sep}`)) {
      throw new Error("unsafeTeamSourcePath");
    }
    const content = await readFile(absolute, "utf8");
    if (Buffer.byteLength(content, "utf8") > 1_048_576) {
      throw new Error("teamSourceTooLarge");
    }
    return parseImportedTeamCollection(JSON.parse(content) as unknown);
  }
}

/**
 * 正式な第三者向けAPIのURL・認証・利用条件が確定するまで接続しない。
 * TODO(genshinbuilds-api): 利用許可取得後、このクラスだけを実装して差し替える。
 */
export class GenshinBuildsTeamSource implements TeamSource {
  async fetchTeams(): Promise<ImportedTeam[]> {
    throw new Error("genshinBuildsApiNotConfigured");
  }
}

export class ManualTeamSource implements TeamSource {
  constructor(private readonly teams: ImportedTeam[]) {}
  async fetchTeams(): Promise<ImportedTeam[]> {
    return [...this.teams];
  }
}
