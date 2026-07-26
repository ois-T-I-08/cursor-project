import { stableHash } from "../cache-key";
import type {
  ImportedTeam,
  NormalizedImportedTeam,
  NormalizedTeamRole,
} from "./types";

const CHARACTER_ID = /^\d{5,12}(?:-[a-z0-9_-]{1,24})?$/i;
const SAFE_TEXT = /^[^\u0000-\u001f\u007f]{1,120}$/u;

const ROLE_ALIASES: Readonly<Record<string, NormalizedTeamRole>> = {
  maindps: "main_dps",
  main_dps: "main_dps",
  "main dps": "main_dps",
  onfield: "main_dps",
  carry: "main_dps",
  subdps: "sub_dps",
  sub_dps: "sub_dps",
  "sub dps": "sub_dps",
  offield: "sub_dps",
  support: "support",
  buffer: "support",
  debuffer: "support",
  healer: "healer",
  healing: "healer",
  shielder: "shielder",
  shield: "shielder",
  flex: "flex",
};

export function normalizeCharacterId(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!CHARACTER_ID.test(normalized)) throw new Error("invalidCharacterId");
  return normalized;
}

export function normalizeExternalRole(value: string | undefined): NormalizedTeamRole {
  if (!value) return "flex";
  const normalized = value.trim().toLowerCase().replaceAll("-", "_");
  return ROLE_ALIASES[normalized] ?? "flex";
}

export function createTeamHash(characterIds: string[]): string {
  if (characterIds.length !== 4 || new Set(characterIds).size !== 4) {
    throw new Error("invalidTeamMembers");
  }
  return stableHash([...characterIds].sort());
}

export function normalizeImportedTeam(team: ImportedTeam): NormalizedImportedTeam {
  if (!SAFE_TEXT.test(team.sourceTeamId) || !SAFE_TEXT.test(team.name)) {
    throw new Error("invalidTeamMetadata");
  }
  if (team.characters.length !== 4) throw new Error("invalidTeamMembers");
  const slots = [...team.characters]
    .sort((a, b) => a.slotIndex - b.slotIndex)
    .map((member, index) => {
      if (member.slotIndex !== index) throw new Error("invalidSlotIndex");
      const sourceRole = (member.sourceRole ?? "").trim().slice(0, 80);
      return {
        characterId: normalizeCharacterId(member.characterId),
        sourceRole,
        normalizedRole: normalizeExternalRole(sourceRole),
        slotIndex: index,
      };
    });
  const ids = slots.map((member) => member.characterId);
  const fetchedAt = parseIsoDate(team.fetchedAt, "invalidFetchedAt");
  const sourceUpdatedAt = team.sourceUpdatedAt
    ? parseIsoDate(team.sourceUpdatedAt, "invalidSourceUpdatedAt")
    : undefined;
  const sourceUrl = normalizeSourceUrl(team.sourceUrl);
  return {
    ...team,
    sourceTeamId: team.sourceTeamId.trim(),
    name: team.name.trim(),
    archetype: team.archetype?.trim().slice(0, 80),
    sourceUrl,
    fetchedAt,
    sourceUpdatedAt,
    dataVersion: team.dataVersion.trim().slice(0, 80),
    characters: slots,
    teamHash: createTeamHash(ids),
  };
}

function parseIsoDate(value: string, code: string): string {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error(code);
  return date.toISOString();
}

function normalizeSourceUrl(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new Error("invalidSourceUrl");
  }
  const allowed = (process.env.TEAM_SOURCE_ALLOWED_HOSTS ?? "")
    .split(",")
    .map((host) => host.trim().toLowerCase())
    .filter(Boolean);
  if (!allowed.includes(url.hostname.toLowerCase())) throw new Error("sourceHostNotAllowed");
  return url.toString();
}
