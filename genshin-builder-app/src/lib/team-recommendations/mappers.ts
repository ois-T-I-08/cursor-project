import {
  GCSIM_ARTIFACT_KEYS,
  GCSIM_CHARACTER_KEYS,
  GCSIM_WEAPON_KEYS,
} from "./gcsim-id-maps.generated";

export class GcsimCharacterMapper {
  map(characterId: string): string | null {
    return GCSIM_CHARACTER_KEYS[characterId] ?? null;
  }
}

export class GcsimWeaponMapper {
  map(weaponId: string): string | null {
    return GCSIM_WEAPON_KEYS[weaponId] ?? null;
  }
}

export class GcsimArtifactMapper {
  map(artifactSetId: string): string | null {
    return GCSIM_ARTIFACT_KEYS[artifactSetId] ?? null;
  }
}
